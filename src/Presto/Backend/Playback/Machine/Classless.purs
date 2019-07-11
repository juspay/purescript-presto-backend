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

import Prelude (Unit, bind, discard, pure, show, unit, void, when, ($), (+), (<>))

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVAR, putVar, takeVar)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Except.Trans (throwError) as E
import Control.Monad.Reader.Trans (lift) as R
import Control.Monad.State.Trans (get) as S
import Data.Array as Array
import Data.Either (Either(Right, Left), note)
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.Tuple (Tuple(..))
import Data.Lazy (Lazy, force)
import Presto.Backend.Runtime.Common (lift3)
import Presto.Backend.Runtime.Types (BackendRuntime(..), InterpreterMT', RunningMode(..))
import Presto.Backend.Playback.Types (PlaybackError(..), PlaybackErrorType(..), PlayerRuntime, RRItemDict, RecorderRuntime, RecordingEntry, compare', encodeJSON', fromRecordingEntry', getTag', isMocked', mkEntry', parseRRItem', toRecordingEntry')
import Type.Proxy (Proxy(..))

unexpectedRecordingEnd :: String -> PlaybackError
unexpectedRecordingEnd expected = PlaybackError
  { errorType: UnexpectedRecordingEnd
  , errorMessage: "Expected: " <> expected
  }

unknownRRItem :: String -> PlaybackError
unknownRRItem expected = PlaybackError
  { errorType: UnknownRRItem
  , errorMessage: "Expected: " <> expected
  }

mockDecodingFailed :: String -> PlaybackError
mockDecodingFailed expected = PlaybackError
  { errorType: MockDecodingFailed
  , errorMessage: "Expected: " <> expected
  }

itemMismatch :: String -> String -> PlaybackError
itemMismatch expected actual = PlaybackError
  { errorType: ItemMismatch
  , errorMessage: "Expected: " <> expected <> ", Actual: " <> actual
  }

replayError
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> PlaybackError
  -> InterpreterMT' rt st eff native
replayError playerRt err = do
  void $ lift3 $ takeVar playerRt.errorVar
  lift3 $ putVar (Just err) playerRt.errorVar
  st <- R.lift S.get
  E.throwError $ Tuple (error $ show err) st

pushRecordingEntry
  :: forall eff
   . RecorderRuntime
  -> RecordingEntry
  -> Aff (avar :: AVAR | eff) Unit
pushRecordingEntry recorderRt entry = do
  recording <- takeVar recorderRt.recordingVar
  putVar { entries : Array.snoc recording.entries entry } recorderRt.recordingVar

popNextRecordingEntry
  :: forall eff
   . PlayerRuntime
  -> Aff (avar :: AVAR | eff) (Maybe RecordingEntry)
popNextRecordingEntry playerRt = do
  cur <- takeVar playerRt.stepVar
  let mbItem = Array.index playerRt.recording.entries cur
  when (isJust mbItem)    $ putVar (cur + 1) playerRt.stepVar
  when (isNothing mbItem) $ putVar cur playerRt.stepVar
  pure mbItem

popNextRRItem
  :: forall eff rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Proxy rrItem
  -> Aff (avar :: AVAR | eff) (Either PlaybackError rrItem)
popNextRRItem playerRt rrItemDict proxy = do
  mbRecordingEntry <- popNextRecordingEntry playerRt
  let expected = getTag' rrItemDict proxy
  pure $ do
    -- TODO: do not drop decoding errors
    re <- note (unexpectedRecordingEnd expected) mbRecordingEntry
    note (unknownRRItem expected) $ fromRecordingEntry' rrItemDict re

popNextRRItemAndResult
  :: forall eff rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Proxy rrItem
  -> Aff (avar :: AVAR | eff) (Either PlaybackError (Tuple rrItem native))
popNextRRItemAndResult playerRt rrItemDict proxy = do
  let expected = getTag' rrItemDict proxy
  eNextRRItem <- popNextRRItem playerRt rrItemDict proxy
  pure $ do
    nextRRItem <- eNextRRItem
    let mbNative = parseRRItem' rrItemDict nextRRItem
    nextResult <- note (mockDecodingFailed expected) mbNative
    pure $ Tuple nextRRItem nextResult

replayWithMock
  :: forall eff rt st rrItem native
   . RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> Proxy rrItem
  -> native
  -> InterpreterMT' rt st eff native
replayWithMock rrItemDict _ proxy nextRes
  | isMocked' rrItemDict proxy = pure nextRes
replayWithMock rrItemDict lAct proxy nextRes = force lAct

compareRRItems
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> rrItem
  -> rrItem
  -> InterpreterMT' rt st eff Unit
compareRRItems playerRt rrItemDict nextRRItem rrItem
  | compare' rrItemDict nextRRItem rrItem = pure unit
compareRRItems playerRt rrItemDict nextRRItem rrItem = do
  let expected = encodeJSON' rrItemDict nextRRItem
  let actual   = encodeJSON' rrItemDict rrItem
  replayError playerRt $ itemMismatch expected actual

replay
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
replay playerRt rrItemDict lAct = do
  let proxy = Proxy :: Proxy rrItem
  eNextRRItemRes <- lift3 $ popNextRRItemAndResult playerRt rrItemDict proxy
  case eNextRRItemRes of
    Left err -> replayError playerRt err
    Right (Tuple nextRRItem nextRes) -> do
      res <- replayWithMock rrItemDict lAct proxy nextRes
      compareRRItems playerRt rrItemDict nextRRItem $ mkEntry' rrItemDict res
      pure res

record
  :: forall eff rt st rrItem native
   . RecorderRuntime
  -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
record recorderRt rrItemDict lAct = do
  native <- force lAct
  lift3
    $ pushRecordingEntry recorderRt
    $ toRecordingEntry' rrItemDict
    $ mkEntry' rrItemDict native
  pure native

withRunModeClassless
  :: forall eff rt st rrItem native
   . BackendRuntime
  -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
withRunModeClassless brt@(BackendRuntime rt) rrItemDict lAct = case rt.mode of
  RegularMode              -> force lAct
  RecordingMode recorderRt -> record recorderRt rrItemDict lAct
  ReplayingMode playerRt   -> replay playerRt   rrItemDict lAct
