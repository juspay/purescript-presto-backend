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

module Presto.Backend.Playback.Machine.Classless where

import Prelude (Unit, bind, discard, pure, show, unit, void, when, ($), (+), (<$>), (<>),not,otherwise)

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVAR, putVar, takeVar, readVar)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Except.Trans (throwError) as E
import Control.Monad.Reader.Trans (lift) as R
import Control.Monad.State.Trans (get) as S
import Data.Array as Array
import Data.Either (Either(Right, Left), note)
import Data.Maybe (Maybe(..), isJust, isNothing, fromMaybe)
import Data.Tuple (Tuple(..))
import Presto.Backend.Runtime.Common (lift3)
import Presto.Backend.Runtime.Types (BackendRuntime(..), InterpreterMT', RunningMode(..))
import Presto.Backend.Playback.Types (Recording (..), RecordingEntry(..), PlaybackError(..),
  PlaybackErrorType(..), PlayerRuntime, RRItemDict, RecorderRuntime, RecordingEntry,
  EntryReplayingMode(..),GlobalReplayingMode(..),
  compare', encodeJSON', fromRecordingEntry', getTag', getInfo', mkEntry', parseRRItem', toRecordingEntry')
import Type.Proxy (Proxy(..))

showInfo :: String -> String -> String
showInfo flowStep recordingEntry =
  "\n    Flow step: " <> flowStep <> "\n    Recording entry: " <> recordingEntry

unexpectedRecordingEnd :: String -> PlaybackError
unexpectedRecordingEnd flowStep = PlaybackError
  { errorType: UnexpectedRecordingEnd
  , errorMessage: "\n    Flow step: " <> flowStep
  }

unknownRRItem :: String -> String -> PlaybackError
unknownRRItem flowStep recordingEntry = PlaybackError
  { errorType: UnknownRRItem
  , errorMessage: showInfo flowStep recordingEntry
  }

mockDecodingFailed :: String -> String -> PlaybackError
mockDecodingFailed flowStep recordingEntry = PlaybackError
  { errorType: MockDecodingFailed
  , errorMessage: showInfo flowStep recordingEntry
  }

itemMismatch :: String -> String -> PlaybackError
itemMismatch flowStep recordingEntry = PlaybackError
  { errorType: ItemMismatch
  , errorMessage: showInfo flowStep recordingEntry
  }

setReplayingError
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> PlaybackError
  -> InterpreterMT' rt st eff native
setReplayingError playerRt err = do
  void $ lift3 $ takeVar playerRt.errorVar
  lift3 $ putVar (Just err) playerRt.errorVar
  st <- R.lift S.get
  E.throwError $ Tuple (error $ show err) st

pushRecordingEntry
  :: forall eff
   . RecorderRuntime
  -> RecordingEntry
  -> Aff (avar :: AVAR | eff) Unit
pushRecordingEntry recorderRt (RecordingEntry _ mode entryName encoded) = do
  entries <- takeVar recorderRt.recordingVar
  let re = RecordingEntry (Array.length entries) mode entryName encoded
  putVar (Array.snoc entries re) recorderRt.recordingVar

popNextRecordingEntry
  :: forall eff
   . PlayerRuntime
  -> Aff (avar :: AVAR | eff) (Maybe { recordingEntry :: RecordingEntry })
popNextRecordingEntry playerRt = do
  cur <- takeVar playerRt.stepVar
  let mbItem = Array.index playerRt.recording cur
  when (isJust mbItem)    $ putVar (cur + 1) playerRt.stepVar
  when (isNothing mbItem) $ putVar cur playerRt.stepVar
  pure $ {recordingEntry : _} <$> mbItem

getCurrentEntryReplayMode
  :: forall eff
   . PlayerRuntime
  -> Aff (avar :: AVAR | eff) EntryReplayingMode
getCurrentEntryReplayMode playerRt = do
  cur <- readVar playerRt.stepVar
  pure $ fromMaybe Normal $ do
    (RecordingEntry idx mode entryName item) <- Array.index playerRt.recording cur
    pure mode

popNextRRItem
  :: forall eff rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Aff (avar :: AVAR | eff) (Either PlaybackError
        { recordingEntry :: RecordingEntry
        , rrItem :: rrItem
        })
popNextRRItem playerRt rrItemDict = do
  mbRecordingEntry <- popNextRecordingEntry playerRt
  let flowStep = getTag' rrItemDict
  let flowStepInfo = getInfo' rrItemDict
  pure $ do
    -- TODO: do not drop decoding errors
    { recordingEntry } <- note (unexpectedRecordingEnd flowStepInfo) mbRecordingEntry
    let unknownErr = unknownRRItem flowStepInfo (show recordingEntry)
    rrItem <- note unknownErr $ fromRecordingEntry' rrItemDict recordingEntry
    pure { recordingEntry, rrItem }

popNextRRItemAndResult
  :: forall eff rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Aff (avar :: AVAR | eff) (Either PlaybackError
        { recordingEntry :: RecordingEntry
        , rrItem :: rrItem
        , mockedResult :: native
        })
popNextRRItemAndResult playerRt rrItemDict = do
  let flowStep = getTag' rrItemDict
  eNextRRItem <- popNextRRItem playerRt rrItemDict
  pure $ do
    { recordingEntry, rrItem } <- eNextRRItem
    let mbNative = parseRRItem' rrItemDict rrItem
    nextResult <- note (mockDecodingFailed flowStep (show recordingEntry)) mbNative
    pure { recordingEntry, rrItem, mockedResult : nextResult }

replayWithMock
  :: forall eff rt st a native
   . { recordingEntry :: RecordingEntry, rrItem :: a, mockedResult :: native }
  -> InterpreterMT' rt st eff native
replayWithMock re = pure $ re.mockedResult

compareRRItems
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> { recordingEntry :: RecordingEntry, rrItem :: rrItem, mockedResult :: native }
  -> rrItem
  -> InterpreterMT' rt st eff Unit
compareRRItems playerRt rrItemDict { recordingEntry, rrItem, mockedResult } flowRRItem =
  if compare' rrItemDict rrItem flowRRItem
    then pure unit
    else do
      let flowStep = encodeJSON' rrItemDict flowRRItem
      setReplayingError playerRt $ itemMismatch flowStep (show recordingEntry)

replayWithGlobalConfig
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> InterpreterMT' rt st eff native
  -> Either PlaybackError { recordingEntry :: RecordingEntry, rrItem :: rrItem, mockedResult :: native }
  -> InterpreterMT' rt st eff native
replayWithGlobalConfig playerRt rrItemDict lAct eNextRRItemRes  = do
  let tag    = getTag' rrItemDict
  let config = checkForReplayConfig playerRt tag
  case config of
    GlobalNoVerify -> case eNextRRItemRes of
        Left err -> setReplayingError playerRt err
        Right stepInfo -> replayWithMock stepInfo
    GlobalNormal    -> case eNextRRItemRes of
        Left err -> setReplayingError playerRt err
        Right stepInfo -> do
          res <- replayWithMock stepInfo
          compareRRItems playerRt rrItemDict stepInfo $ mkEntry' rrItemDict res
          pure res
    GlobalNoMocking -> lAct
    GlobalSkip -> lAct -- this case can't be reachable

checkForReplayConfig :: PlayerRuntime -> String -> GlobalReplayingMode
checkForReplayConfig  playerRt tag | Array.elem tag playerRt.disableMocking  = GlobalNoMocking
                                   | Array.elem tag playerRt.disableVerify   = GlobalNoVerify
                                   | otherwise                               = GlobalNormal

replay
  :: forall eff rt st rrItem native. PlayerRuntime
  -> RRItemDict rrItem native
  -> InterpreterMT' rt st eff native
  -> InterpreterMT' rt st eff native
replay playerRt rrItemDict lAct
  | (Array.elem (getTag' rrItemDict) playerRt.skipEntries ) = lAct
  | otherwise = do
      entryReplayMode <- lift3 $ getCurrentEntryReplayMode playerRt
      eNextRRItemRes  <- lift3 $ popNextRRItemAndResult playerRt rrItemDict
      case entryReplayMode of
        Normal -> replayWithGlobalConfig playerRt rrItemDict lAct eNextRRItemRes
        NoVerify -> case eNextRRItemRes of
          Left err -> setReplayingError playerRt err
          Right stepInfo -> replayWithMock stepInfo
        NoMock -> lAct


record
  :: forall eff rt st rrItem native. RecorderRuntime
  -> RRItemDict rrItem native
  -> InterpreterMT' rt st eff native
  -> InterpreterMT' rt st eff native
record recorderRt rrItemDict lAct = do
  native <- lAct
  let tag = getTag' rrItemDict
  when (not $ Array.elem tag recorderRt.disableEntries)
    $ lift3
    $ pushRecordingEntry recorderRt
    $ toRecordingEntry' rrItemDict (mkEntry' rrItemDict native) 0 Normal
  pure native

filterSkippingEntries playerRt
  | playerRt.entriesFiltered = playerRt
  | otherwise = newPlayerRt
  where
    newRecording = Array.filter pred playerRt.recording
    pred (RecordingEntry _ _ entryName _) = Array.notElem entryName playerRt.skipEntries
    newPlayerRt = playerRt { recording       = newRecording
                           , entriesFiltered = true
                           }

withRunModeClassless
  :: forall eff rt st rrItem native
   . BackendRuntime
  -> RRItemDict rrItem native
  -> InterpreterMT' rt st eff native
  -> InterpreterMT' rt st eff native
withRunModeClassless brt@(BackendRuntime rt) rrItemDict lAct = case rt.mode of
  RegularMode              -> lAct
  RecordingMode recorderRt -> record recorderRt rrItemDict lAct
  ReplayingMode playerRt   -> replay (filterSkippingEntries playerRt)   rrItemDict lAct
