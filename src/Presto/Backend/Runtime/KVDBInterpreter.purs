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
import Presto.Backend.Language.Types.KVDB (Multi(..))
import Presto.Backend.KVDB.Mock.Types (KVDBActionDict)
import Presto.Backend.Runtime.Common (jsonStringify, lift3, throwException', getDBConn', getKVDBConn')
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', LogRunner, RunningMode(..), Connection(..), BackendRuntime(..), KVDBRuntime(..))
import Presto.Backend.Runtime.Types as X
import Presto.Backend.Playback.Types (RRItemDict)
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)
import Type.Proxy (Proxy(..))


getMockedKVDBValue :: forall st rt eff a. BackendRuntime -> KVDBActionDict -> InterpreterMT' rt st eff a
getMockedKVDBValue brt mockedKvDbActDict = throwException' "Mocking is not yet implemented for KV DB."

registerNewMulti
  :: forall eff
   . KVDBRuntime
  -> Native.Multi
  -> Eff (ref :: REF, uuid :: GENUUID | eff) Multi
registerNewMulti (KVDBRuntime rt) nativeMulti = do
  uuid <- genUUID
  let uuidStr = show uuid
  catalogue <- readRef rt.multiesRef
  writeRef rt.multiesRef $ StrMap.insert uuidStr nativeMulti catalogue
  pure $ Multi uuidStr

interpretKVDB
  :: forall st rt s eff a
   . KVDBRuntime
  -> SimpleConn
  -> KVDBMethodWrapper s a
  -> InterpreterMT' rt st eff a

-- interpretKVDB _ simpleConn (SetCache key value next) =
--  (R.lift $ S.lift $ E.lift $ void <$> set key value Nothing NoOptions) >>= (pure <<< next)

-- interpretKVDB _ simpleConn (SetCacheWithExpiry key value ttl next) = (R.lift $ S.lift $ E.lift $ void <$> set key value (Just ttl) NoOptions) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (GetCache key next) = (R.lift $ S.lift $ E.lift $ get key) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (KeyExistsCache key next) = (R.lift $ S.lift $ E.lift $ exists key) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (DelCache key next) = (R.lift $ S.lift $ E.lift $ del (NEArray.singleton key)) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Expire key ttl next) = (R.lift $ S.lift $ E.lift $ expire key ttl) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Incr key next) = (R.lift $ S.lift $ E.lift $ incr key) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (SetHash key field value next) = (R.lift $ S.lift $ E.lift $ hset key field value) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (GetHashKey key field next) = (R.lift $ S.lift $ E.lift $ hget key field) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (PublishToChannel channel message next) = (R.lift $ S.lift $ E.lift $ publish channel message) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Subscribe channel next) = (R.lift $ S.lift $ E.lift $ subscribe (NEArray.singleton channel)) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (SetMessageHandler f next) = (R.lift $ S.lift $ E.lift $ liftEff $ setMessageHandler f) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Enqueue listName value next) = (R.lift $ S.lift $ E.lift $ void <$> rpush listName value) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Dequeue listName next) = (R.lift $ S.lift $ E.lift $ lpop listName) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (GetQueueIdx listName index next) = (R.lift $ S.lift $ E.lift $ lindex listName index) >>= (pure <<< next)
--
interpretKVDB kvdbRt@(KVDBRuntime rt) simpleConn (NewMulti next) = do
  nativeMulti <- lift3 $ liftEff $ newMulti simpleConn
  multi <- lift3 $ liftEff $ registerNewMulti kvdbRt nativeMulti
  pure $ next multi

--
-- interpretKVDB _ simpleConn (SetCacheInMulti key val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val Nothing NoOptions $ multi ) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (GetCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)
--
-- -- Is this a bug? "getMulti"
-- interpretKVDB _ simpleConn (DelCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< getMulti key $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ simpleConn (SetCacheWithExpiryInMulti key val ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val (Just ttl) NoOptions $ multi )>>= (pure <<< next )
--
-- interpretKVDB _ simpleConn (ExpireInMulti key ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< expireMulti key ttl $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (IncrInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< incrMulti key $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (SetHashInMulti key field value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hsetMulti key field value $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ simpleConn (GetHashInMulti key value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hgetMulti key value $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ simpleConn (PublishToChannelInMulti channel message multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< publishMulti channel message $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (SubscribeInMulti channel multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< subscribeMulti channel $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (EnqueueInMulti listName val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< rpushMulti listName val $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (DequeueInMulti listName multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lpopMulti listName $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (GetQueueIdxInMulti listName index multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lindexMulti listName index $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ simpleConn (Exec multi next) = (R.lift <<< S.lift <<< E.lift <<< execMulti $ multi) >>= (pure <<< next)

interpretKVDB _ _ _ = throwException' "Not implemented yet!"

runKVDB'
  :: forall st rt eff a
   . BackendRuntime
  -> SimpleConn
  -> KVDB a
  -> InterpreterMT' rt st eff a
runKVDB' (BackendRuntime rt) simpleConn =
  foldFree (\(KVDBWrapper x) -> runExists (interpretKVDB rt.kvdbRuntime simpleConn) x)

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
        (defer $ \_ -> runKVDB' brt simpleConn kvDBAct)
    MockedKVDB mocked -> withRunModeClassless brt rrItemDict
        (defer $ \_ -> getMockedKVDBValue brt $ mockedKvDbActDictF mocked)
