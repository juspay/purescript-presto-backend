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
import Data.Lazy (defer)
import Presto.Backend.Language.KVDB (KVDB, KVDBMethod(..), KVDBMethodWrapper, KVDBWrapper(..))
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Language.Types.EitherEx
import Presto.Backend.Language.Types.DB (KVDBConn(..), SqlConn(..), MockedSqlConn(..), MockedKVDBConn(..))
import Presto.Backend.Runtime.Common (jsonStringify, lift3, throwException', getDBConn', getKVDBConn')
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', LogRunner, RunningMode(..), Connection(..), BackendRuntime(..))
import Presto.Backend.Runtime.Types as X
import Type.Proxy (Proxy(..))

interpretKVDB :: forall st rt s eff a. BackendRuntime -> KVDBMethodWrapper s a -> InterpreterMT' rt st eff a
--
-- interpretKVDB _ (SetCache cacheConn key value next) = (R.lift $ S.lift $ E.lift $ void <$> set cacheConn key value Nothing NoOptions) >>= (pure <<< next)
--
-- interpretKVDB _ (SetCacheWithExpiry cacheConn key value ttl next) = (R.lift $ S.lift $ E.lift $ void <$> set cacheConn key value (Just ttl) NoOptions) >>= (pure <<< next)
--
-- interpretKVDB _ (GetCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ get cacheConn key) >>= (pure <<< next)
--
-- interpretKVDB _ (KeyExistsCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ exists cacheConn key) >>= (pure <<< next)
--
-- interpretKVDB _ (DelCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ del cacheConn (NEArray.singleton key)) >>= (pure <<< next)
--
-- interpretKVDB _ (Expire cacheConn key ttl next) = (R.lift $ S.lift $ E.lift $ expire cacheConn key ttl) >>= (pure <<< next)
--
-- interpretKVDB _ (Incr cacheConn key next) = (R.lift $ S.lift $ E.lift $ incr cacheConn key) >>= (pure <<< next)
--
-- interpretKVDB _ (SetHash cacheConn key field value next) = (R.lift $ S.lift $ E.lift $ hset cacheConn key field value) >>= (pure <<< next)
--
-- interpretKVDB _ (GetHashKey cacheConn key field next) = (R.lift $ S.lift $ E.lift $ hget cacheConn key field) >>= (pure <<< next)
--
-- interpretKVDB _ (PublishToChannel cacheConn channel message next) = (R.lift $ S.lift $ E.lift $ publish cacheConn channel message) >>= (pure <<< next)
--
-- interpretKVDB _ (Subscribe cacheConn channel next) = (R.lift $ S.lift $ E.lift $ subscribe cacheConn (NEArray.singleton channel)) >>= (pure <<< next)
--
-- interpretKVDB _ (SetMessageHandler cacheConn f next) = (R.lift $ S.lift $ E.lift $ liftEff $ setMessageHandler cacheConn f) >>= (pure <<< next)
--
-- interpretKVDB _ (Enqueue cacheConn listName value next) = (R.lift $ S.lift $ E.lift $ void <$> rpush cacheConn listName value) >>= (pure <<< next)
--
-- interpretKVDB _ (Dequeue cacheConn listName next) = (R.lift $ S.lift $ E.lift $ lpop cacheConn listName) >>= (pure <<< next)
--
-- interpretKVDB _ (GetQueueIdx cacheConn listName index next) = (R.lift $ S.lift $ E.lift $ lindex cacheConn listName index) >>= (pure <<< next)
--
-- interpretKVDB _ (GetMulti cacheConn next) = (R.lift $ S.lift $ E.lift $ liftEff $ newMulti cacheConn) >>= (pure <<< next)
--
-- interpretKVDB _ (SetCacheInMulti key val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val Nothing NoOptions $ multi ) >>= (pure <<< next)
--
-- interpretKVDB _ (GetCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)
--
-- -- Is this a bug? "getMulti"
-- interpretKVDB _ (DelCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< getMulti key $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ (SetCacheWithExpiryInMulti key val ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< setMulti key val (Just ttl) NoOptions $ multi )>>= (pure <<< next )
--
-- interpretKVDB _ (ExpireInMulti key ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< expireMulti key ttl $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (IncrInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< incrMulti key $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (SetHashInMulti key field value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hsetMulti key field value $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ (GetHashInMulti key value multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< hgetMulti key value $ multi) >>= (pure <<< next )
--
-- interpretKVDB _ (PublishToChannelInMulti channel message multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< publishMulti channel message $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (SubscribeInMulti channel multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< subscribeMulti channel $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (EnqueueInMulti listName val multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< rpushMulti listName val $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (DequeueInMulti listName multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lpopMulti listName $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (GetQueueIdxInMulti listName index multi next) = (R.lift <<< S.lift <<< E.lift <<< liftEff <<< lindexMulti listName index $ multi) >>= (pure <<< next)
--
-- interpretKVDB _ (Exec multi next) = (R.lift <<< S.lift <<< E.lift <<< execMulti $ multi) >>= (pure <<< next)

interpretKVDB _ _ = throwException' "Not implemented yet!"

runKVDB :: forall st rt eff a. BackendRuntime -> KVDB a -> InterpreterMT' rt st eff a
runKVDB backendRuntime = foldFree (\(KVDBWrapper x) -> runExists (interpretKVDB backendRuntime) x)
