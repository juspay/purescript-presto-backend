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

import Cache (CacheConn, Multi)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Free (Free, liftF)
import Data.Either (Either(..))
import Data.Exists (Exists, mkExists)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Presto.Backend.DB (findOne, findAll, create, createWithOpts, query, update, delete) as DB
import Presto.Backend.Types (BackendAff)
import Presto.Core.Types.API (class RestEndpoint, Headers)
import Presto.Core.Types.Language.APIInteract (apiInteract)
import Presto.Core.Types.Language.Flow (APIResult, Control)
import Presto.Core.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)

data BackendFlowCommands next st rt s = 
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)
    | CallAPI (Interaction (APIResult s)) (APIResult s -> next)
    | DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException String (s -> next)
    | FindOne (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindAll (Either Error (Array s)) (Either Error (Array s) -> next)
    | Create  (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindOrCreate (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | Query (Either Error s) (Either Error s -> next)
    | Update (Either Error (Array s)) (Either Error (Array s) -> next)
    | Delete (Either Error Int) (Either Error Int -> next)
    | GetDBConn String (Conn -> next)
    | GetCacheConn String (CacheConn -> next)
    | Log String s next
    | SetWithOptions CacheConn (Array String) (Either Error String -> next)
    | SetCache CacheConn String String (Either Error String -> next)
    | SetCacheWithExpiry CacheConn String String String (Either Error String -> next)
    | GetCache CacheConn String (Either Error String -> next)
    | DelCache CacheConn String (Either Error String -> next)
    | Enqueue CacheConn String String (Either Error String -> next)
    | Dequeue CacheConn String (Either Error String -> next)
    | GetQueueIdx CacheConn String Int (Either Error String -> next) 
    | Fork (BackendFlow st rt s) (Unit -> next)
    | Expire CacheConn String String (Either Error String -> next)
    | Incr CacheConn String (Either Error String -> next)
    | SetHash CacheConn String String (Either Error String -> next)
    | GetHashKey CacheConn String String (Either Error String -> next)
    | PublishToChannel CacheConn String String (Either Error String -> next)
    | Subscribe CacheConn String (Either Error String -> next)
    | SetMessageHandler CacheConn (forall eff. (String -> String -> Eff eff Unit)) (Either Error String -> next)
    | GetMulti CacheConn (Multi -> next)
    | SetCacheInMulti Multi String String (Multi -> next)
    | GetCacheInMulti Multi String (Multi -> next)
    | DelCacheInMulti Multi String (Multi -> next)
    | SetCacheWithExpiryInMulti Multi String String String (Multi -> next)
    | ExpireInMulti Multi String String (Multi -> next)
    | IncrInMulti Multi String (Multi -> next)
    | SetHashInMulti Multi String String (Multi -> next)
    | GetHashInMulti Multi String String (Multi -> next)
    | SetWithOptionsInMulti Multi (Array String) (Multi -> next)
    | PublishToChannelInMulti Multi String String (Multi -> next)
    | SubscribeInMulti Multi String (Multi -> next)
    | EnqueueInMulti Multi String String (Multi -> next)
    | DequeueInMulti Multi String (Multi -> next)
    | GetQueueIdxInMulti Multi String Int (Multi -> next) 
    | RunSysCmd String (String -> next)

    -- | HandleException 
    -- | Await (Control s) (s -> next)
    -- | Delay Milliseconds next

type BackendFlowCommandsWrapper st rt s next = BackendFlowCommands next st rt s

newtype BackendFlowWrapper st rt next = BackendFlowWrapper (Exists (BackendFlowCommands next st rt))

type BackendFlow st rt next = Free (BackendFlowWrapper st rt) next

wrap :: forall next st rt s. BackendFlowCommands next st rt s -> BackendFlow st rt next
wrap = liftF <<< BackendFlowWrapper <<< mkExists

ask :: forall st rt. BackendFlow st rt rt
ask = wrap $ Ask id

get :: forall st rt. BackendFlow st rt st
get = wrap $ Get id

put :: forall st rt. st -> BackendFlow st rt st
put st = wrap $ Put st id

modify :: forall st rt. (st -> st) -> BackendFlow st rt st
modify fst = wrap $ Modify fst id

throwException :: forall st rt a. String -> BackendFlow st rt a
throwException errorMessage = wrap $ ThrowException errorMessage id

doAff :: forall st rt a. (forall eff. BackendAff eff a) -> BackendFlow st rt a
doAff aff = wrap $ DoAff aff id

findOne :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model id

findAll :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model id 

query :: forall a st rt. String -> String -> BackendFlow st rt (Either Error (Array a))
query dbName rawq = do
  conn <- getDBConn dbName
  resp <- doAff do
        DB.query conn rawq
  wrap $ Query resp id

create :: forall model st rt. Model model => String -> model -> BackendFlow st rt (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result id

createWithOpts :: forall model st rt. Model model => String -> model -> Options model -> BackendFlow st rt (Either Error (Maybe model))
createWithOpts dbName model options = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.createWithOpts conn model options
  wrap $ Create result id

findOrCreate :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOrCreate dbName options = do
  conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) id

update :: forall model st rt. Model model => String -> Options model -> Options model -> BackendFlow st rt (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model id

delete :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model id

getDBConn :: forall st rt. String -> BackendFlow st rt Conn
getDBConn dbName = do
  wrap $ GetDBConn dbName id

getCacheConn :: forall st rt. String -> BackendFlow st rt CacheConn
getCacheConn dbName = wrap $ GetCacheConn dbName id

getMulti :: forall st rt. String -> BackendFlow st rt Multi
getMulti cacheName = do
    cacheConn <- getCacheConn cacheName
    wrap $ GetMulti cacheConn id

callAPI :: forall st rt a b. Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt (APIResult b)
callAPI headers a = wrap $ CallAPI (apiInteract a headers) id 

setCacheInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
setCacheInMulti multi key value = wrap $ SetCacheInMulti multi key value id

setCache :: forall st rt. String -> String ->  String -> BackendFlow st rt (Either Error String)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value id

getCacheInMulti :: forall st rt. Multi -> String -> BackendFlow st rt Multi
getCacheInMulti multi key = wrap $ GetCacheInMulti multi key id

getCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error String)
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetCache cacheConn key id

delCacheInMulti :: forall st rt. Multi -> String -> BackendFlow st rt Multi
delCacheInMulti multi key = wrap $ DelCacheInMulti multi key id

delCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error String)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ DelCache cacheConn key id

setCacheWithExpireInMulti :: forall st rt. Multi -> String -> String -> String -> BackendFlow st rt Multi
setCacheWithExpireInMulti multi key value ttl = wrap $ SetCacheWithExpiryInMulti multi key value ttl id

setCacheWithExpiry :: forall st rt. String -> String -> String -> String -> BackendFlow st rt (Either Error String)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCacheWithExpiry cacheConn key value ttl id

log :: forall st rt a. String -> a -> BackendFlow st rt Unit
log tag message = wrap $ Log tag message unit

expireInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
expireInMulti multi key ttl = wrap $ ExpireInMulti multi key ttl id

expire :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error String)
expire cacheName key ttl = do 
  cacheConn <- getCacheConn cacheName
  wrap $ Expire cacheConn key ttl id

incrInMulti :: forall st rt. Multi -> String -> BackendFlow st rt Multi
incrInMulti multi key = wrap $ IncrInMulti multi key id

incr :: forall st rt. String -> String -> BackendFlow st rt (Either Error String)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ Incr cacheConn key id

setHashInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
setHashInMulti multi key value = wrap $ SetHashInMulti multi key value id 

setHash :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error String)
setHash cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetHash cacheConn key value id

getHashKeyInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
getHashKeyInMulti multi key field = wrap $ GetHashInMulti multi key field id

getHashKey :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error String)
getHashKey cacheName key field = do 
  cacheConn <- getCacheConn cacheName
  wrap $ GetHashKey cacheConn key field id 

setWithOptionsInMulti :: forall st rt. Multi -> Array String -> BackendFlow st rt Multi
setWithOptionsInMulti multi arr = wrap $ SetWithOptionsInMulti multi arr id

setWithOptions :: forall st rt. String -> Array String -> BackendFlow st rt (Either Error String)
setWithOptions cacheName arr = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetWithOptions cacheConn arr id 
  
publishToChannelInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
publishToChannelInMulti multi channel message = wrap $ PublishToChannelInMulti multi channel message id

publishToChannel :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error String)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  wrap $ PublishToChannel cacheConn channel message id

subscribeToMulti :: forall st rt. Multi -> String -> BackendFlow st rt Multi
subscribeToMulti multi channel = wrap $ SubscribeInMulti multi channel id

subscribe :: forall st rt. String -> String -> BackendFlow st rt (Either Error String)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  wrap $ Subscribe cacheConn channel id

enqueueInMulti :: forall st rt. Multi -> String -> String -> BackendFlow st rt Multi
enqueueInMulti multi listName value = wrap $ EnqueueInMulti multi listName value id

enqueue :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error String)
enqueue cacheName listName value = do
  cacheConn <- getCacheConn cacheName
  wrap $ Enqueue cacheConn listName value id

dequeueInMulti :: forall st rt. Multi -> String -> BackendFlow st rt Multi
dequeueInMulti multi listName = wrap $ DequeueInMulti multi listName id

dequeue :: forall st rt. String -> String -> BackendFlow st rt (Either Error String)
dequeue cacheName listName = do
  cacheConn <- getCacheConn cacheName
  wrap $ Dequeue cacheConn listName id

getQueueIdxInMulti :: forall st rt. Multi -> String -> Int -> BackendFlow st rt Multi
getQueueIdxInMulti multi listName index = wrap $ GetQueueIdxInMulti multi listName index id

getQueueIdx :: forall st rt. String -> String -> Int -> BackendFlow st rt (Either Error String)
getQueueIdx cacheName listName index = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetQueueIdx cacheConn listName index id

setMessageHandler :: forall st rt. String -> (forall eff. (String -> String -> Eff eff Unit)) -> BackendFlow st rt (Either Error String)
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetMessageHandler cacheConn f id

runSysCmd :: forall st rt. String -> BackendFlow st rt String
runSysCmd cmd = wrap $ RunSysCmd cmd id

forkFlow :: forall st rt a. BackendFlow st rt a -> BackendFlow st rt Unit
forkFlow flow = wrap $ Fork flow id
