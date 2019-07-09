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

module Presto.Backend.Runtime.KVDBInterpreter
  ( runKVDB
  ) where

import Prelude

import Cache (SetOptions(..), SimpleConn, del, exists, expire, get, incr, publish, set, setMessageHandler, subscribe)
import Cache.Hash (hget, hset)
import Cache.Multi as Native
import Cache.List (lindex, lpop, rpush)
import Cache.Multi (execMulti, expireMulti, getMulti, hgetMulti, hsetMulti, incrMulti, lindexMulti, lpopMulti, newMulti, publishMulti, rpushMulti, setMulti, subscribeMulti)
import Control.Monad.Aff (Aff, forkAff)
import Control.Monad.Aff.Class (liftAff)
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
import Data.StrMap as StrMap
import Data.Tuple (Tuple(..))
import Data.Foreign.Generic as G
import Data.Lazy (defer)
import Data.UUID (GENUUID, genUUID)
import Presto.Backend.Language.KVDB (KVDB, KVDBMethod(..), KVDBMethodWrapper, KVDBWrapper(..))
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Language.Types.EitherEx
import Presto.Backend.Language.Types.DB (KVDBConn(..), MockedKVDBConn(..), DBError(..))
import Presto.Backend.Language.Types.KVDB (Multi(..), getMultiGUID)
import Presto.Backend.KVDB.Mock.Types (KVDBActionDict)
import Presto.Backend.Runtime.Common (jsonStringify, lift3, throwException', getDBConn', getKVDBConn')
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', LogRunner, RunningMode(..), Connection(..), BackendRuntime(..), KVDBRuntime(..))
import Presto.Backend.Runtime.Types as X
import Presto.Backend.Playback.Types (RRItemDict)
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)
import Type.Proxy (Proxy(..))


getMockedKVDBValue :: forall st rt eff a. BackendRuntime -> KVDBActionDict -> InterpreterMT' rt st eff a
getMockedKVDBValue brt mockedKvDbActDict = throwException' "Mocking is not yet implemented for KV DB."

getNativeMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Eff (ref :: REF | eff) (Maybe Native.Multi)
getNativeMulti (KVDBRuntime rt) multi = do
  let guid = getMultiGUID multi
  catalogue <- readRef rt.multiesRef
  pure $ StrMap.lookup guid catalogue

registerNativeMulti
  :: forall eff
   . KVDBRuntime
  -> String
  -> Native.Multi
  -> Eff (ref :: REF | eff) Unit
registerNativeMulti (KVDBRuntime rt) uuidStr nativeMulti = do
  catalogue <- readRef rt.multiesRef
  writeRef rt.multiesRef $ StrMap.insert uuidStr nativeMulti catalogue

registerNewMulti
  :: forall eff
   . KVDBRuntime
  -> String
  -> Native.Multi
  -> Eff (ref :: REF, uuid :: GENUUID | eff) Multi
registerNewMulti kvdbRt@(KVDBRuntime rt) kvdbName nativeMulti = do
  uuidStr <- show <$> genUUID
  registerNativeMulti kvdbRt uuidStr nativeMulti
  pure $ Multi kvdbName uuidStr

unregisterMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Eff (ref :: REF | eff) Unit
unregisterMulti (KVDBRuntime rt) multi = do
  let guid = getMultiGUID multi
  catalogue <- readRef rt.multiesRef
  writeRef rt.multiesRef $ StrMap.delete guid catalogue

updateNativeMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Native.Multi
  -> Eff (ref :: REF | eff) Unit
updateNativeMulti kvdbRt multi newNativeMulti = do
  let uuidStr = getMultiGUID multi
  registerNativeMulti kvdbRt uuidStr newNativeMulti

withNativeMulti
  :: forall rt st eff
   . KVDBRuntime
  -> Multi
  -> (Native.Multi -> InterpreterMT' rt st eff Native.Multi)
  -> InterpreterMT' rt st eff Unit
withNativeMulti kvdbRt multi act = do
  mbNativeMulti <- lift3 $ liftEff $ getNativeMulti kvdbRt multi
  case mbNativeMulti of
    Nothing -> throwException' $ "Multi not found: " <> show multi
    Just nativeMulti -> do
      nativeMulti' <- act nativeMulti
      lift3 $ liftEff $ updateNativeMulti kvdbRt multi nativeMulti'

interpretKVDB
  :: forall st rt s eff a
   . KVDBRuntime
  -> String
  -> SimpleConn
  -> KVDBMethodWrapper s a
  -> InterpreterMT' rt st eff a

-- TODO: why ignoring Boolean result here?
interpretKVDB _ _ simpleConn (SetCache key value next) = do
  (R.lift $ S.lift $ E.lift $ void <$> set simpleConn key value Nothing NoOptions) >>= (pure <<< next)

-- interpretKVDB _ dbName simpleConn (SetCacheWithExpiry key value ttl next) = (lift3 $ void <$> set key value (Just ttl) NoOptions) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (GetCache key next) = (lift3 $ get key) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (KeyExistsCache key next) = (lift3 $ exists key) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (DelCache key next) = (lift3 $ del (NEArray.singleton key)) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (Expire key ttl next) = (lift3 $ expire key ttl) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (Incr key next) = (lift3 $ incr key) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (SetHash key field value next) = (lift3 $ hset key field value) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (GetHashKey key field next) = (lift3 $ hget key field) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (PublishToChannel channel message next) = (lift3 $ publish channel message) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (Subscribe channel next) = (lift3 $ subscribe (NEArray.singleton channel)) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (SetMessageHandler f next) = (lift3 $ liftEff $ setMessageHandler f) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (Enqueue listName value next) = (lift3 $ void <$> rpush listName value) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (Dequeue listName next) = (lift3 $ lpop listName) >>= (pure <<< next)
--
-- interpretKVDB _ dbName simpleConn (GetQueueIdx listName index next) = (lift3 $ lindex listName index) >>= (pure <<< next)
--
interpretKVDB kvdbRt@(KVDBRuntime rt) dbName simpleConn (NewMulti next) = do
  nativeMulti <- lift3 $ liftEff $ newMulti simpleConn
  multi       <- lift3 $ liftEff $ registerNewMulti kvdbRt dbName nativeMulti
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (SetCacheInMulti key val multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< setMulti key val Nothing NoOptions
  pure $ next multi

-- Is this a bug? This method does nothing.
interpretKVDB kvdbRt _ simpleConn (GetCacheInMulti key multi next) =
  -- (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)
  throwException' "GetCacheInMulti not implemented."

-- Is this a bug? "getMulti"
interpretKVDB kvdbRt _ simpleConn (DelCacheInMulti key multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< getMulti key
  pure $ next multi

-- Is this a bug? "setMulti"
interpretKVDB kvdbRt _ simpleConn (SetCacheWithExpiryInMulti key val ttl multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< setMulti key val (Just ttl) NoOptions
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (ExpireInMulti key ttl multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< expireMulti key ttl
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (IncrInMulti key multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< incrMulti key
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (SetHashInMulti key field value multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< hsetMulti key field value
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (GetHashInMulti key value multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< hgetMulti key value
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (PublishToChannelInMulti channel message multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< publishMulti channel message
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (SubscribeInMulti channel multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< subscribeMulti channel
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (EnqueueInMulti listName val multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< rpushMulti listName val
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (DequeueInMulti listName multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< lpopMulti listName
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (GetQueueIdxInMulti listName index multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< lindexMulti listName index
  pure $ next multi

interpretKVDB kvdbRt _ simpleConn (Exec multi next) = do
  mbNativeMulti <- lift3 $ liftEff $ getNativeMulti kvdbRt multi
  case mbNativeMulti of
    Nothing -> throwException' $ "Multi not found: " <> show multi
    Just nativeMulti -> next <$> (liftAff $ execMulti nativeMulti)

interpretKVDB _ _ _ _ = throwException' "KV DB Method is not implemented yet."

runKVDB'
  :: forall st rt eff a
   . BackendRuntime
  -> String
  -> SimpleConn
  -> KVDB a
  -> InterpreterMT' rt st eff a
runKVDB' (BackendRuntime rt) dbName simpleConn =
  foldFree (\(KVDBWrapper x) -> runExists (interpretKVDB rt.kvdbRuntime dbName simpleConn) x)

runKVDB
  :: forall st rt eff rrItem a
   . BackendRuntime
  -> String
  -> KVDB a
  -> (MockedKVDBConn -> KVDBActionDict)
  -> RRItemDict rrItem a
  -> InterpreterMT' rt st eff a
runKVDB brt dbName kvDBAct mockedKvDbActDictF rrItemDict = do
  conn' <- getKVDBConn' brt dbName
  case conn' of
    Redis simpleConn -> withRunModeClassless brt rrItemDict
        (defer $ \_ -> runKVDB' brt dbName simpleConn kvDBAct)
    MockedKVDB mocked -> withRunModeClassless brt rrItemDict
        (defer $ \_ -> getMockedKVDBValue brt $ mockedKvDbActDictF mocked)
