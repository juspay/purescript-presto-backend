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
import Control.Monad.Aff.AVar (AVar)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Free (Free, liftF)
import Data.Either (Either(..))
import Data.Exists (Exists, mkExists)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Presto.Backend.DB (findOne, findAll, create, update, delete) as DB
import Presto.Backend.Language.APIInteract (apiInteract)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (class RestEndpoint, Headers, ErrorResponse)
import Presto.Backend.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)

type APIResult s = Either ErrorResponse s
newtype Control s = Control (AVar s)
data BackendException err = CustomException err | StringException Error

data BackendFlowCommands next st rt error s = 
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)
    | CallAPI (Interaction (APIResult s)) (APIResult s -> next)
    | DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException (BackendException error) (s -> next)
    | FindOne (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindAll (Either Error (Array s)) (Either Error (Array s) -> next)
    | Create  (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindOrCreate (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | Update (Either Error (Array s)) (Either Error (Array s) -> next)
    | Delete (Either Error Int) (Either Error Int -> next)
    | GetDBConn String (Conn -> next)
    | GetCacheConn String (CacheConn -> next)
    | Log String s next
    | SetCache CacheConn String String (Either Error String -> next)
    | SetCacheWithExpiry CacheConn String String String (Either Error String -> next)
    | GetCache CacheConn String (Either Error String -> next)
    | DelCache CacheConn String (Either Error String -> next)
    | Fork (BackendFlow st rt error s) (Control s -> next)
    | Expire CacheConn String String (Either Error String -> next)
    | Incr CacheConn String (Either Error String -> next)
    | SetHash CacheConn String String (Either Error String -> next)
    | GetHashKey CacheConn String String (Either Error String -> next)
    | PublishToChannel CacheConn String String (Either Error String -> next)
    | Subscribe CacheConn String (Either Error String -> next)
    | SetMessageHandler CacheConn (String -> String -> Unit) (Either Error String -> next)
    | RunSysCmd String (String -> next)

    -- | HandleException 
    -- | Await (Control s) (s -> next)
    -- | Delay Milliseconds next

type BackendFlowCommandsWrapper st rt error s next = BackendFlowCommands next st rt error s

newtype BackendFlowWrapper st rt error next = BackendFlowWrapper (Exists (BackendFlowCommands next st rt error))

type BackendFlow st rt error next = Free (BackendFlowWrapper st rt error) next

wrap :: forall next st rt error s. BackendFlowCommands next st rt error s -> BackendFlow st rt error next
wrap = liftF <<< BackendFlowWrapper <<< mkExists

ask :: forall st rt error. BackendFlow st rt error rt
ask = wrap $ Ask id

get :: forall st rt error. BackendFlow st rt error st
get = wrap $ Get id

put :: forall st rt error. st -> BackendFlow st rt error st
put st = wrap $ Put st id

modify :: forall st rt error. (st -> st) -> BackendFlow st rt error st
modify fst = wrap $ Modify fst id

throwException :: forall st rt error a. String -> BackendFlow st rt error a
throwException err = wrap $ ThrowException (StringException (error err)) id

throwCustomException :: forall st rt error a. error -> BackendFlow st rt error a
throwCustomException err = wrap $ ThrowException (CustomException err) id

doAff :: forall st rt error a. (forall eff. BackendAff eff a) -> BackendFlow st rt error a
doAff aff = wrap $ DoAff aff id

findOne :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model id

findAll :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model id 

create :: forall model st rt error. Model model => String -> model -> BackendFlow st rt error (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result id

findOrCreate :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error (Maybe model))
findOrCreate dbName options = do
  conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) id

update :: forall model st rt error. Model model => String -> Options model -> Options model -> BackendFlow st rt error (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model id

delete :: forall model st rt error. Model model => String -> Options model -> BackendFlow st rt error (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model id

getDBConn :: forall st rt error. String -> BackendFlow st rt error Conn
getDBConn dbName = do
  wrap $ GetDBConn dbName id

getCacheConn :: forall st rt error. String -> BackendFlow st rt error CacheConn
getCacheConn dbName = wrap $ GetCacheConn dbName id

callAPI :: forall st rt error a b. Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt error (APIResult b)
callAPI headers a = wrap $ CallAPI (apiInteract a headers) id 

setCache :: forall st rt error. String -> String ->  String -> BackendFlow st rt error (Either Error String)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName 
  wrap $ SetCache cacheConn key value id

getCache :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetCache cacheConn key id

delCache :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ DelCache cacheConn key id

setCacheWithExpiry :: forall st rt error. String -> String -> String -> String -> BackendFlow st rt error (Either Error String)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCacheWithExpiry cacheConn key value ttl id

log :: forall st rt error a. String -> a -> BackendFlow st rt error Unit
log tag message = wrap $ Log tag message unit

expire :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
expire cacheName key ttl = do 
  cacheConn <- getCacheConn cacheName
  wrap $ Expire cacheConn key ttl id

incr :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ Incr cacheConn key id

setHash :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
setHash cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value id

getHashKey :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
getHashKey cacheName key field = do 
  cacheConn <- getCacheConn cacheName
  wrap $ GetHashKey cacheConn key field id 

publishToChannel :: forall st rt error. String -> String -> String -> BackendFlow st rt error (Either Error String)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  wrap $ PublishToChannel cacheConn channel message id

subscribe :: forall st rt error. String -> String -> BackendFlow st rt error (Either Error String)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  wrap $ Subscribe cacheConn channel id

setMessageHandler :: forall st rt error. String -> (String -> String -> Unit) -> BackendFlow st rt error (Either Error String)
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetMessageHandler cacheConn f id

runSysCmd :: forall st rt error. String -> BackendFlow st rt error String
runSysCmd cmd = wrap $ RunSysCmd cmd id