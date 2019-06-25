module Presto.Backend.Playback.Machine where

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
import Type.Proxy (Proxy(..))
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)



-- popNextRRItem
--   :: forall eff rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => PlayerRuntime
--   -> Proxy rrItem
--   -> Eff (ref :: REF | eff) (Either PlaybackError rrItem)
-- popNextRRItem playerRt proxy = do
--   mbRecordingEntry <- popNextRecordingEntry playerRt
--   let expected = getTag proxy
--   pure $ do
--     -- TODO: do not drop decoding errors
--     re <- note (unexpectedRecordingEnd expected) mbRecordingEntry
--     note (unknownRRItem expected) $ fromRecordingEntry re
--
-- popNextRRItemAndResult
--   :: forall eff rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => PlayerRuntime
--   -> Proxy rrItem
--   -> Eff (ref :: REF | eff) (Either PlaybackError (Tuple rrItem native))
-- popNextRRItemAndResult playerRt proxy = do
--   let expected = getTag proxy
--   eNextRRItem <- popNextRRItem playerRt proxy
--   pure $ do
--     nextRRItem <- eNextRRItem
--     let mbNative = parseRRItem nextRRItem
--     nextResult <- note (mockDecodingFailed expected) mbNative
--     pure $ Tuple nextRRItem nextResult
--
-- replayWithMock
--   :: forall eff rt st rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => Lazy (InterpreterMT' rt st eff native)
--   -> Proxy rrItem
--   -> native
--   -> InterpreterMT' rt st eff native
-- replayWithMock _ proxy nextRes | isMocked proxy = pure nextRes
-- replayWithMock lAct proxy nextRes = force lAct
--
-- compareRRItems
--   :: forall eff rt st rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => rrItem
--   -> rrItem
--   -> InterpreterMT' rt st eff Unit
-- compareRRItems nextRRItem rrItem | nextRRItem == rrItem = pure unit
-- compareRRItems nextRRItem rrItem
--   = R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message
--
-- replay
--   :: forall eff rt st rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => PlayerRuntime
--   -> Lazy (InterpreterMT' rt st eff native)
--   -> (native -> rrItem)
--   -> InterpreterMT' rt st eff native
-- replay playerRt lAct rrItemF = do
--   let proxy = Proxy :: Proxy rrItem
--   eNextRRItemRes <- lift3 $ liftEff $ popNextRRItemAndResult playerRt proxy
--   case eNextRRItemRes of
--     Left err -> R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message
--     Right (Tuple nextRRItem nextRes) -> do
--       res <- replayWithMock lAct proxy nextRes
--       compareRRItems nextRRItem (rrItemF res)
--       pure res
--
-- record
--   :: forall eff rt st rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => RecorderRuntime
--   -> Lazy (InterpreterMT' rt st eff native)
--   -> (native -> rrItem)
--   -> InterpreterMT' rt st eff native
-- record recorderRt lAct rrItemF = do
--   native <- force lAct
--   lift3 $ liftEff $ pushRecordingEntry recorderRt $ toRecordingEntry $ rrItemF native
--   pure native
--
-- withRunMode
--   :: forall eff rt st rrItem native
--    . RRItem rrItem
--   => MockedResult rrItem native
--   => BackendRuntime
--   -> Lazy (InterpreterMT' rt st eff native)
--   -> (native -> rrItem)
--   -> InterpreterMT' rt st eff native
-- withRunMode brt@(BackendRuntime rt) lAct rrItemF = case rt.mode of
--   RegularMode              -> force lAct
--   RecordingMode recorderRt -> record recorderRt lAct rrItemF
--   ReplayingMode playerRt   -> replay playerRt   lAct rrItemF

withRunMode
  :: forall eff rt st rrItem native
   . RRItem rrItem
  => MockedResult rrItem native
  => BackendRuntime
  -> Lazy (InterpreterMT' rt st eff native)
  -> (native -> rrItem)
  -> InterpreterMT' rt st eff native
withRunMode brt lAct rrItemF = withRunModeClassless brt rrDict lAct
  where
    rrDict :: RRItemDict rrItem native
    rrDict = RRItemDict
        { toRecordingEntry   : toRecordingEntry
        , fromRecordingEntry : fromRecordingEntry
        , getTag             : getTag
        , isMocked           : isMocked
        , parseRRItem        : parseRRItem
        , mkEntry            : rrItemF
        , compare            : (==)
        }
