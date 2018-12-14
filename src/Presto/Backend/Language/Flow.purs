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

module Presto.Backend.Flow where

import Prelude

import Cache (CacheConn)
import Control.Monad.Free (Free, liftF)
import Data.Either (Either(..))
import Data.Exists (Exists, mkExists)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Aff.AVar (AVar)
import Effect.Exception (Error, error)
import Foreign.Class (class Decode, class Encode)
import Presto.Backend.DB (findOne, findAll, findAndCountAll, create, update, delete, bCreate') as DB
import Presto.Backend.Language.APIInteract (apiInteract)
import Presto.Backend.Types.API (class RestEndpoint, Headers, ErrorResponse)
import Presto.Backend.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Transaction as Seq
import Sequelize.Types (Conn, Transaction)

type APIResult s = Either ErrorResponse s
newtype Control s = Control (AVar s)
data BackendException err = CustomException err | StringException Error

data BackendFlowCommands next st rt error s =
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)
    | CallAPI (Interaction (APIResult s)) (APIResult s -> next)
    | DoAff (Aff s) (s -> next)
    | ThrowException (BackendException error) (s -> next)
    | FindOne (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindAll (Either Error (Array s)) (Either Error (Array s) -> next)
    | FindAndCountAll (Either Error {count :: Int, rows :: Array s})
        (Either Error {count :: Int, rows :: Array s} -> next)
    | Create  (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | BulkCreate (Either Error Unit) (Either Error Unit -> next)
    | FindOrCreate (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | Update (Either Error (Array s)) (Either Error (Array s) -> next)
    | Delete (Either Error Int) (Either Error Int -> next)
    | GetDBConn String (Conn -> next)
    | StartDBTxn  Transaction (Transaction -> next)
    | CommitDBTxn  Transaction (Transaction -> next)
    | RollBackDBTxn  Transaction (Transaction -> next)
    | GetCacheConn String (CacheConn -> next)
    | Log String s next
    | SetWithOptions CacheConn (Array String) (Either Error String -> next)
    | SetCache CacheConn String String (Either Error String -> next)
    | SetCacheWithExpiry CacheConn String String String (Either Error String -> next)
    | GetCache CacheConn String (Either Error String -> next)
    | DelCache CacheConn String (Either Error String -> next)
    | Expire CacheConn String String (Either Error String -> next)
    | Incr CacheConn String (Either Error String -> next)
    | SetHash CacheConn String String (Either Error String -> next)
    | GetHashKey CacheConn String String (Either Error String -> next)
    | PublishToChannel CacheConn String String (Either Error String -> next)
    | Subscribe CacheConn String (Either Error String -> next)
    | SetMessageHandler CacheConn (String -> String -> Effect Unit) (Either Error String -> next)
    | RunSysCmd String (String -> next)
    | Fork (BackendFlow st rt error s) (Unit -> next)
    | Attempt (BackendFlow st rt error s) ((Either (BackendException error) s) -> next)

type BackendFlowCommandsWrapper st rt error s next = BackendFlowCommands next st rt error s

newtype BackendFlowWrapper st rt error next = BackendFlowWrapper (Exists (BackendFlowCommands next st rt error))

type BackendFlow st rt error next = Free (BackendFlowWrapper st rt error) next

instance showBackendException :: Show a => Show (BackendException a) where
  show (CustomException err) = show err
  show (StringException err) = show err

wrap :: forall next st rt error s. BackendFlowCommands next st rt error s -> BackendFlow st rt error next
wrap = liftF <<< BackendFlowWrapper <<< mkExists

ask :: forall st rt error. BackendFlow st rt error rt
ask = wrap $ Ask identity

get :: forall st rt error. BackendFlow st rt error st
get = wrap $ Get identity

put :: forall st rt error. st -> BackendFlow st rt error st
put st = wrap $ Put st identity

modify :: forall st rt error. (st -> st) -> BackendFlow st rt error st
modify fst = wrap $ Modify fst identity

throwException :: forall st rt error a. String -> BackendFlow st rt error a
throwException err = wrap $ ThrowException (StringException (error err)) identity

throwCustomException :: forall st rt error a. error -> BackendFlow st rt error a
throwCustomException err = wrap $ ThrowException (CustomException err) identity

doAff :: forall st rt error a. Aff a -> BackendFlow st rt error a
doAff aff = wrap $ DoAff aff identity

startTransaction :: forall st rt error. String ->  BackendFlow st rt error Transaction
startTransaction dbName = do
  conn <- getDBConn dbName
  txn <- doAff $ Seq.startTransaction conn
  wrap $ StartDBTxn txn identity

commitTransaction :: forall st rt error. Transaction ->  BackendFlow st rt error Transaction
commitTransaction txn = do
  doAff $ Seq.commitTransaction txn
  wrap $ CommitDBTxn txn identity

rollbackTransaction :: forall st rt error. Transaction ->  BackendFlow st rt error Transaction
rollbackTransaction txn = do
  doAff $ Seq.rollbackTransaction txn
  wrap $ RollBackDBTxn txn identity

findOne :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model identity

findAll :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model identity

findAndCountAll :: forall model st rt error. Model model => String -> Options model
  -> BackendFlow st rt error (Either Error {count :: Int, rows :: Array model})
findAndCountAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAndCountAll conn options
  wrap $ FindAndCountAll model identity

create :: forall model st rt error. Model model => String -> model -> BackendFlow st rt error (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result identity

bulkCreate :: forall model st rt error. Model model => String -> Array model -> BackendFlow st rt error (Either Error Unit)
bulkCreate dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.bCreate' conn model
  wrap $ BulkCreate result identity

findOrCreate :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Maybe model))
findOrCreate dbName options = do
  conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) identity

update :: forall model st rt error. Model model => String -> Options model -> Options model -> BackendFlow st rt error (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model identity

delete :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model identity

getDBConn :: forall st rt error. String -> BackendFlow st rt error Conn
getDBConn dbName = do
  wrap $ GetDBConn dbName identity

getCacheConn :: forall st rt error. String -> BackendFlow st rt error CacheConn
getCacheConn dbName = wrap $ GetCacheConn dbName identity

callAPI :: forall st rt error a b. Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt error (APIResult b)
callAPI headers a = wrap $ CallAPI (apiInteract a headers) identity

setCache :: forall st rt error. String -> String ->  String -> BackendFlow st rt error (Either Error String)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value identity

getCache :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetCache cacheConn key identity

delCache :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ DelCache cacheConn key identity

setCacheWithExpiry :: forall st rt error. String -> String -> String -> String -> BackendFlow st rt error (Either Error String)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCacheWithExpiry cacheConn key value ttl identity

log :: forall st rt error a. String -> a -> BackendFlow st rt error Unit
log tag message = wrap $ Log tag message unit

expire :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
expire cacheName key ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ Expire cacheConn key ttl identity

incr :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ Incr cacheConn key identity

setHash :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
setHash cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value identity

getHashKey :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
getHashKey cacheName key field = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetHashKey cacheConn key field identity

setWithOptions :: forall st rt error. String -> Array String -> BackendFlow st rt error (Either Error String)
setWithOptions cacheName arr = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetWithOptions cacheConn arr identity

publishToChannel :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  wrap $ PublishToChannel cacheConn channel message identity

subscribe :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  wrap $ Subscribe cacheConn channel identity

setMessageHandler :: forall st rt error. String -> (String -> String -> Effect Unit) -> BackendFlow st rt error (Either Error String)
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetMessageHandler cacheConn f identity

forkFlow :: forall s st rt error. BackendFlow st rt error s -> BackendFlow st rt error Unit
forkFlow flow = wrap $ Fork flow identity

attemptFlow :: forall s st rt error. BackendFlow st rt error s -> BackendFlow st rt error (Either (BackendException error) s)
attemptFlow flow = wrap $ Attempt flow identity

runSysCmd :: forall st rt error. String -> BackendFlow st rt error String
runSysCmd cmd = wrap $ RunSysCmd cmd identity
