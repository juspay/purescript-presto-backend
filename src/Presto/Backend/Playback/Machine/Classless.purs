module Presto.Backend.Playback.Machine.Classless where

import Prelude
import Presto.Backend.Playback.Entries
import Presto.Backend.Playback.Types
import Presto.Backend.Runtime.Types

import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Control.Monad.Except (runExcept) as E
import Control.Monad.Except.Trans (ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Control.MonadZero (guard)
import Data.Array (elem)
import Data.Array as Array
import Data.Either (Either(..), note, hush, isLeft)
import Data.Foreign.Generic (encodeJSON)
import Data.Foreign.Generic as G
import Data.Lazy (Lazy, force)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Tuple (Tuple(..))
import Presto.Backend.APIInteract (apiInteract)
import Presto.Backend.Runtime.Common (jsonStringify, lift3)
import Presto.Backend.Types (BackendAff)
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
  lift3 $ liftEff $ writeRef playerRt.errorRef $ Just err
  R.lift S.get >>= (E.throwError <<< Tuple (error $ show err))

pushRecordingEntry
  :: forall eff
   . RecorderRuntime
  -> RecordingEntry
  -> Eff (ref :: REF | eff) Unit
pushRecordingEntry recorderRt entry = do
  recording <- readRef recorderRt.recordingRef
  writeRef recorderRt.recordingRef { entries : Array.snoc recording.entries entry }

popNextRecordingEntry
  :: forall eff
   . PlayerRuntime
  -> Eff (ref :: REF | eff) (Maybe RecordingEntry)
popNextRecordingEntry playerRt = do
  cur <- readRef playerRt.stepRef
  let mbItem = Array.index playerRt.recording.entries cur
  when (isJust mbItem) $ writeRef playerRt.stepRef $ cur + 1
  pure mbItem

getCurrentEntryReplayMode
  :: forall eff
   . PlayerRuntime
  -> Eff (ref :: REF | eff) (Maybe EntryReplayingMode)
getCurrentEntryReplayMode playerRt = do
  cur <- readRef playerRt.stepRef
  let mbItem = Array.index playerRt.recording.entries cur
  case mbItem of 
    (Just (RecordingEntry mode item)) -> pure $ Just mode 
    Nothing -> pure $ Nothing

popNextRRItem
  :: forall eff rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Proxy rrItem
  -> Eff (ref :: REF | eff) (Either PlaybackError rrItem)
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
  -> Eff (ref :: REF | eff) (Either PlaybackError (Tuple rrItem native))
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
  :: forall eff rt st rrItem native. PlayerRuntime -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
replay playerRt rrItemDict lAct = do
  let proxy = Proxy :: Proxy rrItem
  let tag = getTag' rrItemDict proxy
  mode' <- lift3 $ liftEff $ getCurrentEntryReplayMode playerRt
  let mode = fromMaybe Normal mode'
  case mode of 
    Normal -> do 
      eNextRRItemRes <- lift3 $ liftEff $ popNextRRItemAndResult playerRt rrItemDict proxy
      case eNextRRItemRes of
        Left err -> replayError playerRt err
        Right (Tuple nextRRItem nextRes) -> do
          res <- replayWithMock rrItemDict lAct proxy nextRes
          when (not (elem tag playerRt.disableVerify)) $ compareRRItems playerRt rrItemDict nextRRItem $ mkEntry' rrItemDict res
          pure res
    NoVerify -> do
      eNextRRItemRes <- lift3 $ liftEff $ popNextRRItemAndResult playerRt rrItemDict proxy 
      case eNextRRItemRes of 
        Left err -> replayError playerRt err 
        Right (Tuple nextRRItem nextRes) -> replayWithMock rrItemDict lAct proxy nextRes
    NoMock -> force lAct  
    Skip -> replayError playerRt $ PlaybackError {errorType : UnexpectedRecordingEnd , errorMessage : "not sure what to do with skip"}

record :: forall eff rt st rrItem native. RecorderRuntime  -> RRItemDict rrItem native  ->  Lazy (InterpreterMT' rt st eff native)  -> InterpreterMT' rt st eff native
record recorderRt rrItemDict lAct = do
  native <- force lAct
  let tag = getTag' rrItemDict (Proxy :: Proxy rrItem)
  if not ( elem tag recorderRt.disableEntries ) then do
      lift3 $ liftEff $ pushRecordingEntry recorderRt $ toRecordingEntry' rrItemDict (mkEntry' rrItemDict native) Normal 
      pure native
    else pure native

withRunModeClassless
  :: forall eff rt st rrItem native
   . BackendRuntime
  -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
withRunModeClassless brt@(BackendRuntime rt) rrItemDict lAct =
  case rt.mode of
  RegularMode              -> force lAct
  RecordingMode recorderRt -> record recorderRt rrItemDict lAct
  ReplayingMode playerRt   -> do
                              let proxy = Proxy :: Proxy rrItem
                              let tag = getTag' rrItemDict proxy
                              if elem tag playerRt.disableMocking then do
                                force lAct
                                else replay playerRt   rrItemDict lAct




