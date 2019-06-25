module Presto.Backend.Playback.Machine.Classless where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Except (runExcept) as E
import Control.Monad.Except.Trans (ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Data.Array as Array
import Data.Either (Either(..), note, hush, isLeft)
import Data.Maybe (Maybe(..), isJust)
import Data.Tuple (Tuple(..))
import Data.Foreign.Generic as G
import Data.Lazy (Lazy, force)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Runtime.Common (jsonStringify, lift3)
import Presto.Backend.Runtime.Types
import Presto.Backend.Playback.Types
import Presto.Backend.Playback.Entries
import Presto.Core.Utils.Encoding as Enc
import Presto.Backend.APIInteractEx (ExtendedAPIResultEx, apiInteractEx)
import Type.Proxy (Proxy(..))

unexpectedRecordingEnd :: String -> PlaybackError
unexpectedRecordingEnd msg = PlaybackError
  { errorType: UnexpectedRecordingEnd
  , errorMessage: msg
  }

unknownRRItem :: String -> PlaybackError
unknownRRItem msg = PlaybackError
  { errorType: UnknownRRItem
  , errorMessage: msg
  }

mockDecodingFailed :: String -> PlaybackError
mockDecodingFailed msg = PlaybackError
  { errorType: MockDecodingFailed
  , errorMessage: msg
  }

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
   . RRItemDict rrItem native
  -> rrItem
  -> rrItem
  -> InterpreterMT' rt st eff Unit
compareRRItems rrItemDict nextRRItem rrItem
  | compare' rrItemDict nextRRItem rrItem = pure unit
compareRRItems rrItemDict nextRRItem rrItem
  = R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message

replay
  :: forall eff rt st rrItem native
   . PlayerRuntime
  -> RRItemDict rrItem native
  -> Lazy (InterpreterMT' rt st eff native)
  -> InterpreterMT' rt st eff native
replay playerRt rrItemDict lAct = do
  let proxy = Proxy :: Proxy rrItem
  eNextRRItemRes <- lift3 $ liftEff $ popNextRRItemAndResult playerRt rrItemDict proxy
  case eNextRRItemRes of
    Left err -> R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message
    Right (Tuple nextRRItem nextRes) -> do
      res <- replayWithMock rrItemDict lAct proxy nextRes
      compareRRItems rrItemDict nextRRItem $ mkEntry' rrItemDict res
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
    $ liftEff
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
