{-
 Copyright (c) 2012-2017 "JUSPAY Technologies"
 JUSPAY Technologies Pvt. Ltd. [https://www.juspay.in]
 This file is part of JUSPAY Platform.
 JUSPAY Platform is free software: you can redistribute it and/or modify
 it for only educational purposes under the terms of the GNU Affero General
 Public License (GNU AGPL) as published by the Free Software Foundation,
 either version 3 of the License, or (at your option) any later version.
 For Enterprise/Commerical licenses, contact <info@juspay.in>.
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  The end user will
 be liable for all damages without limitation, which is caused by the
 ABUSE of the LICENSED SOFTWARE and shall INDEMNIFY JUSPAY for such
 damages, claims, cost, including reasonable attorney fee claimed on Juspay.
 The end user has NO right to claim any indemnification based on its use
 of Licensed Software. See the GNU Affero General Public License for more details.
 You should have received a copy of the GNU Affero General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/agpl.html>.
-}

module Presto.Backend.Runtime.Interpreter
  ( module Presto.Backend.Runtime.Interpreter
  , module X
  ) where

import Prelude

import Control.Monad.Aff (forkAff)
import Control.Monad.Aff.AVar (AVAR, AVar, makeVar, readVar, takeVar, putVar)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff.Exception (Error, throwException, error)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Except.Trans (runExceptT) as E
import Control.Monad.Free (foldFree)
import Control.Monad.Reader.Trans (ask, lift, runReaderT) as R
import Control.Monad.State.Trans (get, modify, put, runStateT) as S
import Data.Exists (runExists)
import Data.Tuple (Tuple)
import Data.StrMap as StrMap
import Data.UUID (genUUID)
import Data.Maybe (Maybe(..))
import Presto.Backend.Flow (BackendFlow, BackendFlowCommands(..), BackendFlowCommandsWrapper, BackendFlowWrapper(..))
import Presto.Backend.SystemCommands (runSysCmd)
import Presto.Backend.Language.Types.EitherEx (fromEitherEx, toEitherEx)
import Presto.Backend.Language.Types.MaybeEx (fromMaybeEx, toMaybeEx)
import Presto.Backend.Language.Types.UnitEx (UnitEx(..), fromUnitEx)
import Presto.Backend.Language.Types.DB (SqlConn(..))
import Presto.Backend.Runtime.Common (lift3, throwException', getDBConn', getKVDBConn')
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', BackendRuntime(..), RunningMode(..))
import Presto.Backend.Runtime.Types as X
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)
import Presto.Backend.Playback.Entries (mkThrowExceptionEntry)
import Presto.Backend.Playback.Types (RecorderRuntime(..), PlayerRuntime(..), PlaybackError(..), PlaybackErrorType(..), mkEntryDict)
import Presto.Backend.Runtime.API (runAPIInteraction)
import Presto.Backend.Runtime.KVDBInterpreter (runKVDB)
import Presto.Backend.DB.Mock.Types (DBActionDict)

forkF :: forall eff rt st a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT rt st (Tuple Error st) eff Unit
forkF brt flow = do
  st <- R.lift $ S.get
  rt <- R.ask
  let m = E.runExceptT ( S.runStateT ( R.runReaderT ( runBackend brt flow ) rt) st)
  void $ lift3 $ forkAff m

forkRecorderRt
  :: forall eff rt st
   . String
  -> RecorderRuntime
  -> InterpreterMT' rt st eff RecorderRuntime
forkRecorderRt flowGUID rt = do
  recordingVar <- lift3 $ makeVar []
  forkedRecs   <- lift3 $ takeVar rt.forkedRecordingsVar
  let forkedRecs' = StrMap.insert flowGUID recordingVar forkedRecs
  lift3 $ putVar forkedRecs' rt.forkedRecordingsVar
  pure
    { flowGUID
    , recordingVar
    , forkedRecordingsVar : rt.forkedRecordingsVar
    , disableEntries      : rt.disableEntries
    }

forkPlayerRt
  :: forall eff rt st
   . String
  -> PlayerRuntime
  -> InterpreterMT' rt st eff (Maybe PlayerRuntime)
forkPlayerRt flowGUID rt =
  case StrMap.lookup flowGUID rt.forkedFlowRecordings of
    Nothing -> do
      let missedRecsErr = PlaybackError
            { errorType    : ForkedFlowRecordingsMissed
            , errorMessage : "No recordings found for forked flow: " <> flowGUID
            }
      forkedFlowErrors <- lift3 $ takeVar rt.forkedFlowErrorsVar
      let forkedFlowErrors' = StrMap.insert flowGUID missedRecsErr forkedFlowErrors
      lift3 $ putVar forkedFlowErrors' rt.forkedFlowErrorsVar
      pure Nothing
    Just recording -> do
      stepVar  <- lift3 $ makeVar 0
      errorVar <- lift3 $ makeVar Nothing
      pure $ Just
        { flowGUID
        , stepVar
        , errorVar
        , recording
        , forkedFlowRecordings  : rt.forkedFlowRecordings
        , forkedFlowErrorsVar   : rt.forkedFlowErrorsVar
        , disableVerify         : rt.disableVerify
        , disableMocking        : rt.disableMocking
        , skipEntries           : rt.skipEntries
        , entriesFiltered       : rt.entriesFiltered
        }

forkBackendRuntime
  :: forall eff rt st
   . String
  -> BackendRuntime
  -> InterpreterMT' rt st eff (Maybe BackendRuntime)
forkBackendRuntime flowGUID brt@(BackendRuntime rt) = do
  mbForkedMode <- case rt.mode of
    RegularMode              -> pure $ Just RegularMode
    RecordingMode recorderRt -> (Just <<< RecordingMode) <$> forkRecorderRt flowGUID recorderRt
    ReplayingMode playerRt   -> do
      mbRt <- forkPlayerRt flowGUID playerRt
      pure $ ReplayingMode <$> mbRt

  case mbForkedMode of
    Nothing         -> pure Nothing
    Just forkedMode -> pure $ Just $ BackendRuntime
          { apiRunner   : rt.apiRunner
          , connections : rt.connections
          , logRunner   : rt.logRunner
          , affRunner   : rt.affRunner
          , kvdbRuntime : rt.kvdbRuntime
          , mode        : forkedMode
          , options     : rt.options
          }

getMockedDBValue :: forall st rt eff a. BackendRuntime -> DBActionDict -> InterpreterMT' rt st eff a
getMockedDBValue brt mockedDbActDict = throwException' "Mocking is not yet implemented for DB."

interpret :: forall st rt s eff a. BackendRuntime -> BackendFlowCommandsWrapper st rt s a -> InterpreterMT' rt st eff a
interpret _ (Ask next) = R.ask >>= (pure <<< next)

interpret _ (Get next) = R.lift (S.get) >>= (pure <<< next)

interpret _ (Put d next) = R.lift (S.put d) *> (pure <<< next) d

interpret _ (Modify d next) = R.lift (S.modify d) *> S.get >>= (pure <<< next)

interpret brt@(BackendRuntime rt) (SetOption key val rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 $ do
      options <- liftAff $ takeVar rt.options
      (liftAff $ putVar (StrMap.insert key val options ) rt.options) *> pure UnitEx
    )
  pure $ next res

interpret brt@(BackendRuntime rt) (GetOption key rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 $ do
      options <- liftAff $ readVar rt.options
      pure $ toMaybeEx $ StrMap.lookup key options)
  pure $ next $ fromMaybeEx res

interpret brt@(BackendRuntime rt) (GenerateGUID rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 $ liftEff $ show <$> genUUID)
  pure $ next res

interpret brt@(BackendRuntime rt) (CallAPI apiAct rrItemDict next) = do
  resultEx <- withRunModeClassless brt rrItemDict
    (lift3 $ runAPIInteraction rt.apiRunner apiAct)
  pure $ next $ fromEitherEx resultEx

interpret _ (DoAff aff next) = next <$> lift3 aff

interpret brt@(BackendRuntime rt) (DoAffRR aff rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 $ rt.affRunner aff)
  pure $ next res

interpret brt@(BackendRuntime rt) (Log tag message rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 (rt.logRunner tag message) *> pure UnitEx)
  pure $ next res

interpret brt@(BackendRuntime rt) (Fork flow flowGUID rrItemDict next) = do
  mbForkedRt <- forkBackendRuntime flowGUID brt

  void $ withRunModeClassless brt rrItemDict
      (case mbForkedRt of
        Nothing -> (lift3 (rt.logRunner flowGUID "Failed to fork flow.") *> pure UnitEx)
        Just forkedBrt -> forkF forkedBrt flow *> pure UnitEx)

  pure $ next UnitEx

interpret brt (RunSysCmd cmd rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (lift3 $ runSysCmd cmd)
  pure $ next res

interpret brt (ThrowException errorMessage) = do
  void $ withRunModeClassless brt
    (mkEntryDict errorMessage $ mkThrowExceptionEntry errorMessage)
    (pure UnitEx)
  throwException' errorMessage

interpret brt@(BackendRuntime rt) (GetDBConn dbName rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (getDBConn' brt dbName)
  pure $ next res

interpret brt@(BackendRuntime rt) (RunDB dbName dbAffF mockedDbActDictF rrItemDict next) = do
  conn' <- getDBConn' brt dbName
  res <- case conn' of
    Sequelize conn -> withRunModeClassless brt rrItemDict
        (lift3 $ rt.affRunner $ dbAffF conn)
    MockedSql mocked -> withRunModeClassless brt rrItemDict
        (getMockedDBValue brt $ mockedDbActDictF mocked)
  pure $ next res

interpret brt@(BackendRuntime rt) (GetKVDBConn dbName rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (getKVDBConn' brt dbName)
  pure $ next res

interpret brt (RunKVDBEither dbName kvDBF mockedKvDbActDictF rrItemDict next) =
  next <$> runKVDB brt dbName kvDBF mockedKvDbActDictF rrItemDict

interpret brt (RunKVDBSimple dbName kvDBF mockedKvDbActDictF rrItemDict next) =
  next <$> runKVDB brt dbName kvDBF mockedKvDbActDictF rrItemDict

runBackend :: forall st rt eff a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT' rt st eff a
runBackend backendRuntime = foldFree (\(BackendFlowWrapper x) -> runExists (interpret backendRuntime) x)
