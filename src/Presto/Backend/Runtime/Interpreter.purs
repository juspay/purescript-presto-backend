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
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Except.Trans (lift, runExceptT) as E
import Control.Monad.Free (foldFree)
import Control.Monad.Reader.Trans (ask, lift, runReaderT) as R
import Control.Monad.State.Trans (get, lift, modify, put, runStateT) as S
import Data.Exists (runExists)
import Data.Tuple (Tuple)
import Data.Lazy (defer)
import Presto.Backend.Flow (BackendFlow, BackendFlowCommands(..), BackendFlowCommandsWrapper, BackendFlowWrapper(..))
import Presto.Backend.SystemCommands (runSysCmd)
import Presto.Backend.Language.Types.EitherEx (fromEitherEx)
import Presto.Backend.Language.Types.UnitEx (UnitEx(..))
import Presto.Backend.Language.Types.DB (SqlConn(..))
import Presto.Backend.Runtime.Common (lift3, throwException', getDBConn', getKVDBConn')
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', BackendRuntime(..))
import Presto.Backend.Runtime.Types as X
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)
import Presto.Backend.Playback.Entries (mkThrowExceptionEntry)
import Presto.Backend.Playback.Types (mkEntryDict)
import Presto.Backend.Runtime.API (runAPIInteraction)
import Presto.Backend.Runtime.KVDBInterpreter (runKVDB)
import Presto.Backend.DB.Mock.Types (DBActionDict)

forkF :: forall eff rt st a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT rt st (Tuple Error st) eff Unit
forkF runtime flow = do
  st <- R.lift $ S.get
  rt <- R.ask
  let m = E.runExceptT ( S.runStateT ( R.runReaderT ( runBackend runtime flow ) rt) st)
  R.lift $ S.lift $ E.lift $ forkAff m *> pure unit

getMockedDBValue :: forall st rt eff a. BackendRuntime -> DBActionDict -> InterpreterMT' rt st eff a
getMockedDBValue brt mockedDbActDict = throwException' "Mocking is not yet implemented for DB."

interpret :: forall st rt s eff a. BackendRuntime -> BackendFlowCommandsWrapper st rt s a -> InterpreterMT' rt st eff a
interpret _ (Ask next) = R.ask >>= (pure <<< next)

interpret _ (Get next) = R.lift (S.get) >>= (pure <<< next)

interpret _ (Put d next) = R.lift (S.put d) *> (pure <<< next) d

interpret _ (Modify d next) = R.lift (S.modify d) *> S.get >>= (pure <<< next)

interpret brt@(BackendRuntime rt) (CallAPI apiAct rrItemDict next) = do
  resultEx <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> lift3 $ runAPIInteraction rt.apiRunner apiAct)
  pure $ next $ fromEitherEx resultEx

interpret _ (DoAff aff nextF) = (R.lift $ S.lift $ E.lift aff) >>= (pure <<< nextF)

interpret brt@(BackendRuntime rt) (DoAffRR aff rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> lift3 $ rt.affRunner aff)
  pure $ next res

interpret brt@(BackendRuntime rt) (Log tag message rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> lift3 (rt.logRunner tag message) *> pure UnitEx)
  pure $ next res

interpret r (Fork flow next) = forkF r flow >>= (pure <<< next)

interpret brt (RunSysCmd cmd rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> lift3 $ runSysCmd cmd)
  pure $ next res

interpret brt (ThrowException errorMessage) = do
  void $ withRunModeClassless brt
    (mkEntryDict $ mkThrowExceptionEntry errorMessage)
    (defer $ \_ -> pure UnitEx)
  throwException' errorMessage

interpret brt@(BackendRuntime rt) (GetDBConn dbName rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> getDBConn' brt dbName)
  pure $ next res

interpret brt@(BackendRuntime rt) (RunDB dbName dbAffF mockedDbActDictF rrItemDict next) = do
  conn' <- getDBConn' brt dbName
  res <- case conn' of
    Sequelize conn -> withRunModeClassless brt rrItemDict
        (defer $ \_ -> lift3 $ rt.affRunner $ dbAffF conn)
    MockedSql mocked -> withRunModeClassless brt rrItemDict
        (defer $ \_ -> getMockedDBValue brt $ mockedDbActDictF mocked)
  pure $ next res

interpret brt@(BackendRuntime rt) (GetKVDBConn dbName rrItemDict next) = do
  res <- withRunModeClassless brt rrItemDict
    (defer $ \_ -> getKVDBConn' brt dbName)
  pure $ next res

interpret brt (RunKVDBEither dbName kvDBF mockedKvDbActDictF rrItemDict next) =
  next <$> runKVDB brt dbName kvDBF mockedKvDbActDictF rrItemDict

interpret brt (RunKVDBSimple dbName kvDBF mockedKvDbActDictF rrItemDict next) =
  next <$> runKVDB brt dbName kvDBF mockedKvDbActDictF rrItemDict

runBackend :: forall st rt eff a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT' rt st eff a
runBackend backendRuntime = foldFree (\(BackendFlowWrapper x) -> runExists (interpret backendRuntime) x)
