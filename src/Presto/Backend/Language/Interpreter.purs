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

import Cache (CacheConn, delKey, exec, exists, expire, expireMulti, getHashKey, getHashKeyMulti, getKey, getKeyMulti, getMulti, incr, incrMulti, lindex, lindexMulti, lpop, lpopMulti, publishToChannel, publishToChannelMulti, rpush, rpushMulti, set, setHash, setHashMulti, setKey, setKeyMulti, setMessageHandler, setMulti, setex, setexKeyMulti, subscribe, subscribeMulti)
import Control.Monad.Aff (Aff, forkAff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Except.Trans (ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Free (foldFree)
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Data.Either (Either(..))
import Data.Exists (runExists)
import Data.Maybe (Maybe(..))
import Data.StrMap (StrMap, lookup)
import Data.Tuple (Tuple(..))
import Presto.Backend.Flow (BackendFlow, BackendFlowCommands(..), BackendFlowCommandsWrapper, BackendFlowWrapper(..), BackendException(..))
import Presto.Backend.SystemCommands (runSysCmd)
import Presto.Backend.Types (BackendAff)
import Presto.Core.Flow (runAPIInteraction)
import Presto.Core.Language.Runtime.API (APIRunner)
import Sequelize.Types (Conn)

type InterpreterMT rt st exception eff a = R.ReaderT rt (S.StateT st (E.ExceptT exception (BackendAff eff))) a

type Cache = {
    name :: String
  , connection :: CacheConn
}

type DB = {
    name :: String
  , connection :: Conn
}

type LogRunner = forall e a. String -> a -> Aff e Unit

data Connection = Sequelize Conn | Redis CacheConn

data BackendRuntime = BackendRuntime APIRunner (StrMap Connection) LogRunner

forkF :: forall eff rt st exception a. BackendRuntime -> BackendFlow st rt exception a -> InterpreterMT rt st (Tuple (BackendException exception) st) eff Unit
forkF runtime flow = do
  st <- R.lift $ S.get
  rt <- R.ask
  let m = E.runExceptT ( S.runStateT ( R.runReaderT ( runBackend runtime flow ) rt) st)
  R.lift $ S.lift $ E.lift $ forkAff m *> pure unit


interpret :: forall st rt s eff a exception.  BackendRuntime -> BackendFlowCommandsWrapper st rt s exception a -> InterpreterMT rt st (Tuple (BackendException exception) st) eff a
interpret _ (Ask next) = R.ask >>= (pure <<< next)

interpret _ (Get next) = R.lift (S.get) >>= (pure <<< next)

interpret _ (Put d next) = R.lift (S.put d) *> (pure <<< next) d

interpret _ (Modify d next) = R.lift (S.modify d) *> S.get >>= (pure <<< next)

interpret _ (ThrowException errorMessage next) = R.lift S.get >>= (R.lift <<< S.lift <<< E.ExceptT <<<  pure <<< Left <<< Tuple (error errorMessage)) >>= pure <<< next

interpret _ (DoAff aff nextF) = (R.lift $ S.lift $ E.lift aff) >>= (pure <<< nextF)

interpret _ (SetCache cacheConn key value next) = (R.lift $ S.lift $ E.lift $ setKey cacheConn key value) >>= (pure <<< next )

interpret _ (SetCacheWithExpiry cacheConn key value ttl next) = (R.lift $ S.lift $ E.lift $ setex cacheConn key value ttl) >>= (pure <<< next)

interpret _ (GetCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ getKey cacheConn key) >>= (pure <<< next)

interpret _ (KeyExistsCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ exists cacheConn key) >>= (pure <<< next)

interpret _ (DelCache cacheConn key next) = (R.lift $ S.lift $ E.lift $ delKey cacheConn key) >>= (pure <<< next)

interpret _ (Expire cacheConn key ttl next) = (R.lift $ S.lift $ E.lift $ expire cacheConn key ttl) >>= (pure <<< next)
    
interpret _ (Incr cacheConn key next) = (R.lift $ S.lift $ E.lift $ incr cacheConn key) >>= (pure <<< next) 

interpret _ (SetHash cacheConn key field value next) = (R.lift $ S.lift $ E.lift $ setHash cacheConn key field value) >>= (pure <<< next) 

interpret _ (GetHashKey cacheConn key field next) = (R.lift $ S.lift $ E.lift $ getHashKey cacheConn key field) >>= (pure <<< next) 

interpret _ (SetWithOptions cacheConn arr next) = (R.lift $ S.lift $ E.lift $ set cacheConn arr) >>= (pure <<< next) 

interpret _ (PublishToChannel cacheConn channel message next) = (R.lift $ S.lift $ E.lift $ publishToChannel cacheConn channel message) >>= (pure <<< next) 

interpret _ (Subscribe cacheConn channel next) = (R.lift $ S.lift $ E.lift $ subscribe cacheConn channel) >>= (pure <<< next) 

interpret _ (SetMessageHandler cacheConn f next) = (R.lift $ S.lift $ E.lift $ setMessageHandler cacheConn f) >>= (pure <<< next) 

interpret _ (Enqueue cacheConn listName value next) = (R.lift $ S.lift $ E.lift $ void <$> rpush cacheConn listName value) >>= (pure <<< next)

interpret _ (Dequeue cacheConn listName next) = (R.lift $ S.lift $ E.lift $ lpop cacheConn listName) >>= (pure <<< next)

interpret _ (GetQueueIdx cacheConn listName index next) = (R.lift $ S.lift $ E.lift $ lindex cacheConn listName index) >>= (pure <<< next)

interpret _ (GetMulti cacheConn next) = (R.lift $ S.lift $ E.lift $ getMulti cacheConn) >>= (pure <<< next)

interpret _ (SetCacheInMulti key val multi next) = (R.lift <<< S.lift <<< E.lift <<< setKeyMulti key val $ multi ) >>= (pure <<< next)

interpret _ (GetCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)

interpret _ (DelCacheInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< getKeyMulti key$ multi) >>= (pure <<< next )

interpret _ (SetCacheWithExpiryInMulti key val ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< setexKeyMulti key val ttl $ multi )>>= (pure <<< next )

interpret _ (ExpireInMulti key ttl multi next) = (R.lift <<< S.lift <<< E.lift <<< expireMulti key ttl $ multi) >>= (pure <<< next)

interpret _ (IncrInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< incrMulti key $ multi) >>= (pure <<< next)

interpret _ (SetHashInMulti key field value multi next) = (R.lift <<< S.lift <<< E.lift <<< setHashMulti key field value $ multi) >>= (pure <<< next )

interpret _ (GetHashInMulti key value multi next) = (R.lift <<< S.lift <<< E.lift <<< getHashKeyMulti key value $ multi) >>= (pure <<< next )

interpret _ (SetWithOptionsInMulti key multi next) = (R.lift <<< S.lift <<< E.lift <<< setMulti key $ multi) >>= (pure <<< next) 

interpret _ (PublishToChannelInMulti channel message multi next) = (R.lift <<< S.lift <<< E.lift <<< publishToChannelMulti channel message $ multi) >>= (pure <<< next) 

interpret _ (SubscribeInMulti channel multi next) = (R.lift <<< S.lift <<< E.lift <<< subscribeMulti channel $ multi) >>= (pure <<< next)

interpret _ (EnqueueInMulti listName val multi next) = (R.lift <<< S.lift <<< E.lift <<< rpushMulti listName val $ multi) >>= (pure <<< next)

interpret _ (DequeueInMulti listName multi next) = (R.lift <<< S.lift <<< E.lift <<< lpopMulti listName $ multi) >>= (pure <<< next)

interpret _ (GetQueueIdxInMulti listName index multi next) = (R.lift <<< S.lift <<< E.lift <<< lindexMulti listName index $ multi) >>= (pure <<< next)

interpret _ (Exec multi next) = (R.lift <<< S.lift <<< E.lift <<< exec $ multi) >>= (pure <<< next)

interpret (BackendRuntime a connections c) (GetCacheConn cacheName next) = do
  maybeCache <- pure $ lookup cacheName connections
  case maybeCache of
    Just (Redis cache) -> (pure <<< next) cache
    Just _ -> interpret (BackendRuntime a connections c) (ThrowException (Exception "No DB found") next)
    Nothing -> interpret (BackendRuntime a connections c) (ThrowException (Exception "No DB found") next)

interpret _ (FindOne model next) = (pure <<< next) model

interpret _ (FindAll models next) = (pure <<< next) models

interpret _ (Query models next) = (pure <<< next) models

interpret _ (Create model next) = (pure <<< next) model

interpret _ (Update model next) = (pure <<< next) model

interpret _ (Delete model next) = (pure <<< next) model

interpret ((BackendRuntime a connections c)) (GetDBConn dbName next) = do
  maybedb <- pure $ lookup dbName connections
  case maybedb of
    Just (Sequelize db) -> (pure <<< next) db
    Just _ -> interpret (BackendRuntime a connections c) (ThrowException (Exception "No DB found") next)
    Nothing -> interpret (BackendRuntime a connections c) (ThrowException (Exception "No DB found") next)
  

interpret (BackendRuntime apiRunner _ _) (CallAPI apiInteractionF nextF) = do
  R.lift $ S.lift $ E.lift $ runAPIInteraction apiRunner apiInteractionF
    >>= (pure <<< nextF)

interpret (BackendRuntime _ _ logRunner) (Log tag message next) = (R.lift ( S.lift ( E.lift (logRunner tag message)))) *> pure next

interpret r (Fork flow nextF) = forkF r flow >>= (pure <<< nextF)

interpret _ (RunSysCmd cmd next) = R.lift $ S.lift $ E.lift $ runSysCmd cmd >>= (pure <<< next)

interpret _ _ = R.lift S.get >>= (E.throwError <<< Tuple (error "Not implemented yet!") )

runBackend :: forall st rt eff exception a. BackendRuntime -> BackendFlow st rt exception a -> InterpreterMT rt st (Tuple (BackendException exception) st) eff a
runBackend backendRuntime = foldFree (\(BackendFlowWrapper x) -> runExists (interpret backendRuntime) x)
