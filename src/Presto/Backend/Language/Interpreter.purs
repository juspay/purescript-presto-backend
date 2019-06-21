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

module Presto.Backend.Interpreter where

import Prelude

import Cache (SetOptions(..), SimpleConn, del, exists, expire, get, incr, publish, set, setMessageHandler, subscribe)
import Cache.Hash (hget, hset)
import Cache.List (lindex, lpop, rpush)
import Cache.Multi (execMulti, expireMulti, getMulti, hgetMulti, hsetMulti, incrMulti, lindexMulti, lpopMulti, newMulti, publishMulti, rpushMulti, setMulti, subscribeMulti)
import Control.Monad.Aff (Aff, forkAff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Except (runExcept) as E
import Control.Monad.Except.Trans (ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Free (foldFree)
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Data.Array.NonEmpty (singleton) as NEArray
import Data.Array as Array
import Data.Either (Either(..), note, hush, isLeft)
import Data.Exists (runExists)
import Data.Maybe (Maybe(..), isJust)
import Data.StrMap (StrMap, lookup)
import Data.Tuple (Tuple(..))
import Data.Foreign.Generic as G
import Presto.Backend.Flow (BackendFlow, BackendFlowCommands(..), BackendFlowCommandsWrapper, BackendFlowWrapper(..))
import Presto.Backend.SystemCommands (runSysCmd)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Playback.Common (jsonStringify)
import Presto.Core.Flow (runAPIInteraction)
import Presto.Core.Language.Runtime.API (APIRunner)
import Presto.Core.Utils.Encoding as Enc
import Sequelize.Types (Conn)
import Type.Proxy (Proxy(..))

type InterpreterMT rt st err eff a = R.ReaderT rt (S.StateT st (E.ExceptT err (BackendAff eff))) a
type InterpreterMT' rt st eff a = InterpreterMT rt st (Tuple Error st) eff a

type Cache = {
    name :: String
  , connection :: SimpleConn
}

type DB = {
    name :: String
  , connection :: Conn
}

type LogRunner = forall e a. String -> a -> Aff e Unit

data Connection = Sequelize Conn | Redis SimpleConn

newtype RecordingEntry = RecordingEntry
  { tag  :: String
  , body :: String
  }

data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  }


mkLogEntry :: Unit -> String -> String -> LogEntry
mkLogEntry _ t m = LogEntry {tag: t, message: m}

-- TODO: it might be Data.Sequence.Ordered is better
type Recording =
  { entries :: Array RecordingEntry
  }

type RecorderRuntime =
  { recordingRef :: Ref Recording
  }

type PlayerRuntime =
  { recording :: Recording
  , stepRef   :: Ref Int
  }

data PlaybackErrorType
  = UnexpectedRecordingEnd
  | UnknownRRItem
  | MockDecodingFailed

newtype PlaybackError = PlaybackError
  { errorType :: PlaybackErrorType
  , errorMessage :: String
  }

data RunningMode
  = RegularMode
  | RecordingMode RecorderRuntime
  | ReplayingMode PlayerRuntime


newtype BackendRuntime = BackendRuntime
  { apiRunner   :: APIRunner
  , connections :: StrMap Connection
  , logRunner   :: LogRunner
  , mode        :: RunningMode
  }


class Eq a <= RRItem a where
  toRecordingEntry :: a -> RecordingEntry
  getEncodedResult :: a -> String
  getTag           :: Proxy a -> String
  isMocked         :: Proxy a -> Boolean


forkF :: forall eff rt st a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT rt st (Tuple Error st) eff Unit
forkF runtime flow = do
  st <- R.lift $ S.get
  rt <- R.ask
  let m = E.runExceptT ( S.runStateT ( R.runReaderT ( runBackend runtime flow ) rt) st)
  R.lift $ S.lift $ E.lift $ forkAff m *> pure unit

lift3 :: forall eff err rt st a. BackendAff eff a -> InterpreterMT rt st (Tuple Error st) eff a
lift3 m = R.lift (S.lift (E.lift m))

unexpectedRecordingEnd msg = PlaybackError
  { errorType: UnexpectedRecordingEnd
  , errorMessage: msg
  }

unknownRRItem msg = PlaybackError
  { errorType: UnknownRRItem
  , errorMessage: msg
  }


mockDecodingFailed msg = PlaybackError
  { errorType: MockDecodingFailed
  , errorMessage: msg
  }

decodeMockedResult
  :: forall rrItem a
   . RRItem rrItem
  => rrItem
  -> Maybe a
decodeMockedResult = hush <<< E.runExcept <<< G.decodeJSON <<< getEncodedResult

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
  :: forall eff rrItem
   . RRItem rrItem
  => PlayerRuntime
  -> Proxy rrItem
  -> Eff (ref :: REF | eff) (Either PlaybackError rrItem)
popNextRRItem playerRt proxy = do
  mbRecordingEntry <- popNextRecordingEntry playerRt
  let expected = getTag proxy
  pure $ do
    -- TODO: do not drop decoding errors
    (RecordingEntry re) <- note (unexpectedRecordingEnd expected) mbRecordingEntry
    note (unknownRRItem expected) $ hush $ E.runExcept $ G.decodeJSON re.body

popNextRRItemAndResult
  :: forall eff rrItem a
   . RRItem rrItem
  => PlayerRuntime
  -> Proxy rrItem
  -> Eff (ref :: REF | eff) (Either PlaybackError (Tuple rrItem a))
popNextRRItemAndResult playerRt proxy = do
  let expected = getTag proxy
  eNextRRItem <- popNextRRItem playerRt proxy
  pure $ do
    nextRRItem <- eNextRRItem
    nextResult <- note (mockDecodingFailed expected) $ decodeMockedResult nextRRItem
    pure $ Tuple nextRRItem nextResult

replayWithMock
  :: forall eff rt st rrItem a
   . RRItem rrItem
  => InterpreterMT' rt st eff a
  -> Proxy rrItem
  -> a
  -> InterpreterMT' rt st eff a
replayWithMock act proxy nextRes | isMocked proxy = pure nextRes
replayWithMock act proxy nextRes = act

compareRRItems
  :: forall eff rt st rrItem
   . RRItem rrItem
  => rrItem
  -> rrItem
  -> InterpreterMT' rt st eff Unit
compareRRItems nextRRItem rrItem | nextRRItem == rrItem = pure unit
compareRRItems nextRRItem rrItem
  = R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message

replay
  :: forall eff rt st rrItem a
   . RRItem rrItem
  => PlayerRuntime
  -> InterpreterMT' rt st eff a
  -> (a -> rrItem)
  -> InterpreterMT' rt st eff a
replay playerRt act rrItemF = do
  let proxy = Proxy :: Proxy rrItem
  eNextRRItemRes <- lift3 $ liftEff $ popNextRRItemAndResult playerRt proxy
  case eNextRRItemRes of
    Left err -> R.lift S.get >>= (E.throwError <<< Tuple (error "Replaying failed") )   -- TODO: error message
    Right (Tuple nextRRItem nextRes) -> do
      res <- replayWithMock act proxy nextRes
      compareRRItems nextRRItem (rrItemF res)
      pure res

record
  :: forall eff rt st a rrItem
   . RRItem rrItem
  => RecorderRuntime
  -> InterpreterMT' rt st eff a
  -> (a -> rrItem)
  -> InterpreterMT' rt st eff a
record recorderRt act rrItemF = do
  res <- act
  R.lift $ S.lift $ E.lift $ liftEff $ pushRecordingEntry recorderRt $ toRecordingEntry $ rrItemF res
  pure res

withRunMode
  :: forall eff rt st a rrItem
   . RRItem rrItem
  => BackendRuntime
  -> InterpreterMT' rt st eff a
  -> (a -> rrItem)
  -> InterpreterMT' rt st eff a
withRunMode brt@(BackendRuntime rt) act rrItemF = case rt.mode of
  RegularMode              -> act
  RecordingMode recorderRt -> record recorderRt act rrItemF
  ReplayingMode playerRt   -> replay playerRt   act rrItemF


interpret :: forall st rt s eff a.  BackendRuntime -> BackendFlowCommandsWrapper st rt s a -> InterpreterMT' rt st eff a
interpret _ (Ask next) = R.ask >>= (pure <<< next)

interpret _ (Get next) = R.lift (S.get) >>= (pure <<< next)

interpret _ (Put d next) = R.lift (S.put d) *> (pure <<< next) d

interpret _ (Modify d next) = R.lift (S.modify d) *> S.get >>= (pure <<< next)

interpret _ (ThrowException errorMessage next) = R.lift S.get >>= (R.lift <<< S.lift <<< E.ExceptT <<<  pure <<< Left <<< Tuple (error errorMessage)) >>= pure <<< next

interpret _ (DoAff aff nextF) = (R.lift $ S.lift $ E.lift aff) >>= (pure <<< nextF)

interpret _ (SetCache cacheConn key value next) = (R.lift $ S.lift $ E.lift $ void <$> set cacheConn key value Nothing NoOptions) >>= (pure <<< next)

interpret _ (SetCacheWithExpiry cacheConn key value ttl next) = (R.lift $ S.lift $ E.lift $ void <$> set cacheConn key value (Just ttl) NoOptions) >>= (pure <<< next)

interpret _ (GetCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ get cacheConn key) >>= (pure <<< next)

interpret _ (KeyExistsCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ exists cacheConn key) >>= (pure <<< next)

interpret _ (DelCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ del cacheConn (NEArray.singleton key)) >>= (pure <<< next)

interpret _ (Expire cacheConn key ttl next) = (R.lift $ S.lift $ E.lift $ expire cacheConn key ttl) >>= (pure <<< next)

interpret _ (Incr cacheConn key next) = (R.lift $ S.lift $ E.lift $ incr cacheConn key) >>= (pure <<< next)

interpret _ (SetHash cacheConn key field value next) = (R.lift $ S.lift $ E.lift $ hset cacheConn key field value) >>= (pure <<< next)

interpret _ (GetHashKey cacheConn key field next) = (R.lift $ S.lift $ E.lift $ hget cacheConn key field) >>= (pure <<< next)

interpret _ (PublishToChannel cacheConn channel message next) = (R.lift $ S.lift $ E.lift $ publish cacheConn channel message) >>= (pure <<< next)

interpret _ (Subscribe cacheConn channel next) = (R.lift $ S.lift $ E.lift $ subscribe cacheConn (NEArray.singleton channel)) >>= (pure <<< next)

interpret _ (SetMessageHandler cacheConn f next) = (R.lift $ S.lift $ E.lift $ liftEff $ setMessageHandler cacheConn f) >>= (pure <<< next)

interpret _ (Enqueue cacheConn listName value next) = (R.lift $ S.lift $ E.lift $ void <$> rpush cacheConn listName value) >>= (pure <<< next)

interpret _ (Dequeue cacheConn listName next) = (R.lift $ S.lift $ E.lift $ lpop cacheConn listName) >>= (pure <<< next)

interpret _ (GetQueueIdx cacheConn listName index next) = (R.lift $ S.lift $ E.lift $ lindex cacheConn listName index) >>= (pure <<< next)

interpret _ (GetMulti cacheConn next) = (R.lift $ S.lift $ E.lift $ liftEff $ newMulti cacheConn) >>= (pure <<< next)

interpret _ (SetCacheInMulti key val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val Nothing NoOptions $ multi ) >>= (pure <<< next)

interpret _ (GetCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)

interpret _ (DelCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< getMulti key $ multi) >>= (pure <<< next )

interpret _ (SetCacheWithExpiryInMulti key val ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val (Just ttl) NoOptions $ multi )>>= (pure <<< next )

interpret _ (ExpireInMulti key ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< expireMulti key ttl $ multi) >>= (pure <<< next)

interpret _ (IncrInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< incrMulti key $ multi) >>= (pure <<< next)

interpret _ (SetHashInMulti key field value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hsetMulti key field value $ multi) >>= (pure <<< next )

interpret _ (GetHashInMulti key value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hgetMulti key value $ multi) >>= (pure <<< next )

interpret _ (PublishToChannelInMulti channel message multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< publishMulti channel message $ multi) >>= (pure <<< next)

interpret _ (SubscribeInMulti channel multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< subscribeMulti channel $ multi) >>= (pure <<< next)

interpret _ (EnqueueInMulti listName val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< rpushMulti listName val $ multi) >>= (pure <<< next)

interpret _ (DequeueInMulti listName multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lpopMulti listName $ multi) >>= (pure <<< next)

interpret _ (GetQueueIdxInMulti listName index multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lindexMulti listName index $ multi) >>= (pure <<< next)

interpret _ (Exec multi next) = (R.lift <<< S.lift <<< E.lift <<< execMulti $ multi) >>= (pure <<< next)

interpret brt@(BackendRuntime rt) (GetCacheConn cacheName next) = do
  let maybeCache = lookup cacheName rt.connections
  case maybeCache of
    Just (Redis cache) -> (pure <<< next) cache
    Just _  -> interpret brt (ThrowException "No DB found" next)
    Nothing -> interpret brt (ThrowException "No DB found" next)

interpret _ (FindOne model next) = (pure <<< next) model

interpret _ (FindAll models next) = (pure <<< next) models

interpret _ (Query models next) = (pure <<< next) models

interpret _ (Create model next) = (pure <<< next) model

interpret _ (Update model next) = (pure <<< next) model

interpret _ (Delete model next) = (pure <<< next) model

interpret brt@(BackendRuntime rt) (GetDBConn dbName next) = do
  let maybedb = lookup dbName rt.connections
  case maybedb of
    Just (Sequelize db) -> (pure <<< next) db
    Just _  -> interpret brt (ThrowException "No DB found" next)
    Nothing -> interpret brt (ThrowException "No DB found" next)

interpret brt@(BackendRuntime rt) (CallAPI apiInteractionF nextF) = do
  R.lift $ S.lift $ E.lift $ runAPIInteraction rt.apiRunner apiInteractionF
    >>= (pure <<< nextF)

interpret brt@(BackendRuntime rt) (Log tag message next) = do
  res <- withRunMode brt
            (lift3 (rt.logRunner tag message))       -- is lazy evaluation needed?
            (mkLogEntry (jsonStringify tag) message)
  pure $ next res

interpret r (Fork flow nextF) = forkF r flow >>= (pure <<< nextF)

interpret _ (RunSysCmd cmd next) = R.lift $ S.lift $ E.lift $ runSysCmd cmd >>= (pure <<< next)

interpret _ _ = R.lift S.get >>= (E.throwError <<< Tuple (error "Not implemented yet!") )

runBackend :: forall st rt eff a. BackendRuntime -> BackendFlow st rt a -> InterpreterMT' rt st eff a
runBackend backendRuntime = foldFree (\(BackendFlowWrapper x) -> runExists (interpret backendRuntime) x)
