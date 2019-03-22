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
import Presto.Core.Types.Language.Flow (APIResult)
import Presto.Core.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)



-- type APIResult s = Either ErrorResponse s
-- newtype Control s = Control (AVar s)
data BackendException err = CustomException err | Exception String

data BackendFlowCommands next st rt exception s = 
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)
    | CallAPI (Interaction (APIResult s)) (APIResult s -> next)
    | DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException (BackendException exception) (s -> next)
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
    | KeyExistsCache CacheConn String (Either Error Boolean -> next)
    | DelCache CacheConn String (Either Error String -> next)
    | Enqueue CacheConn String String (Either Error Unit -> next)
    | Dequeue CacheConn String (Either Error (Maybe String) -> next)
    | GetQueueIdx CacheConn String Int (Either Error String -> next) 
    | Fork (BackendFlow st rt exception s) (Unit -> next)
    | Expire CacheConn String String (Either Error String -> next)
    | Incr CacheConn String (Either Error String -> next)
    | SetHash CacheConn String String String (Either Error String -> next)
    | GetHashKey CacheConn String String (Either Error String -> next)
    | PublishToChannel CacheConn String String (Either Error String -> next)
    | Subscribe CacheConn String (Either Error String -> next)
    | SetMessageHandler CacheConn (forall eff. (String -> String -> Eff eff Unit)) (Either Error String -> next)
    | GetMulti CacheConn (Multi -> next)
    | SetCacheInMulti String String Multi (Multi -> next)
    | GetCacheInMulti String Multi (Multi -> next)
    | DelCacheInMulti String Multi (Multi -> next)
    | SetCacheWithExpiryInMulti String String String Multi (Multi -> next)
    | ExpireInMulti String String Multi (Multi -> next)
    | IncrInMulti String Multi (Multi -> next)
    | SetHashInMulti String String String Multi (Multi -> next)
    | GetHashInMulti String String Multi (Multi -> next)
    | SetWithOptionsInMulti (Array String) Multi (Multi -> next)
    | PublishToChannelInMulti String String Multi (Multi -> next)
    | SubscribeInMulti String Multi (Multi -> next)
    | EnqueueInMulti String String Multi (Multi -> next)
    | DequeueInMulti String Multi (Multi -> next)
    | GetQueueIdxInMulti String Int Multi (Multi -> next) 
    | Exec Multi (Either Error (Array String) -> next) 
    | RunSysCmd String (String -> next)
    | ReRoute (BackendException exception) (s -> next)

type BackendFlowCommandsWrapper st rt exception s next = BackendFlowCommands next st rt exception s

newtype BackendFlowWrapper st rt exception next = BackendFlowWrapper (Exists (BackendFlowCommands next st rt exception))

type BackendFlow st rt exception next = Free (BackendFlowWrapper st rt exception) next

instance showBackendException :: Show exception => Show (BackendException exception) where
  show (CustomException exception) = show exception
  show (Exception exception) = show exception

wrap :: forall next st rt exception s. BackendFlowCommands next st rt exception s -> BackendFlow st rt exception next
wrap = liftF <<< BackendFlowWrapper <<< mkExists

ask :: forall st rt exception. BackendFlow st rt exception rt
ask = wrap $ Ask id

get :: forall st rt exception. BackendFlow st rt exception st
get = wrap $ Get id

put :: forall st rt exception. st -> BackendFlow st rt exception st
put st = wrap $ Put st id

modify :: forall st rt exception. (st -> st) -> BackendFlow st rt exception st
modify fst = wrap $ Modify fst id

throwException :: forall st rt exception a. BackendException exception -> BackendFlow st rt exception a
throwException errorMessage = wrap $ ThrowException errorMessage id

doAff :: forall st rt exception a. (forall eff. BackendAff eff a) -> BackendFlow st rt exception a
doAff aff = wrap $ DoAff aff id

findOne :: forall model st rt exception. Model model => String -> Options model -> BackendFlow st rt exception (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model id

findAll :: forall model st rt exception. Model model => String -> Options model -> BackendFlow st rt exception (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model id 

query :: forall a st rt exception. String -> String -> BackendFlow st rt exception (Either Error (Array a))
query dbName rawq = do
  conn <- getDBConn dbName
  resp <- doAff do
        DB.query conn rawq
  wrap $ Query resp id

create :: forall model st rt exception. Model model => String -> model -> BackendFlow st rt exception (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result id

createWithOpts :: forall model st rt exception. Model model => String -> model -> Options model -> BackendFlow st rt exception (Either Error (Maybe model))
createWithOpts dbName model options = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.createWithOpts conn model options
  wrap $ Create result id

findOrCreate :: forall model st rt exception. Model model => String -> Options model -> BackendFlow st rt exception (Either Error (Maybe model))
findOrCreate dbName options = do
  conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) id

update :: forall model st rt exception. Model model => String -> Options model -> Options model -> BackendFlow st rt exception (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model id

delete :: forall model st rt exception. Model model => String -> Options model -> BackendFlow st rt exception (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model id

getDBConn :: forall st rt exception. String -> BackendFlow st rt exception Conn
getDBConn dbName = do
  wrap $ GetDBConn dbName id

getCacheConn :: forall st rt exception. String -> BackendFlow st rt exception CacheConn
getCacheConn dbName = wrap $ GetCacheConn dbName id

getMulti :: forall st rt exception. String -> BackendFlow st rt exception Multi
getMulti cacheName = do
    cacheConn <- getCacheConn cacheName
    wrap $ GetMulti cacheConn id

callAPI :: forall st rt exception a b. Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt exception (APIResult b)
callAPI headers a = wrap $ CallAPI (apiInteract a headers) id 

setCacheInMulti :: forall st rt exception. String -> String -> Multi -> BackendFlow st rt exception Multi
setCacheInMulti key value multi = wrap $ SetCacheInMulti key value multi id

setCache :: forall st rt exception. String -> String ->  String -> BackendFlow st rt exception (Either Error String)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value id

getCacheInMulti :: forall st rt exception. String -> Multi -> BackendFlow st rt exception Multi
getCacheInMulti key multi = wrap $ GetCacheInMulti key multi id

getCache :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error String)
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetCache cacheConn key id

keyExistsCache :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error Boolean)
keyExistsCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ KeyExistsCache cacheConn key id

delCacheInMulti :: forall st rt exception. String -> Multi -> BackendFlow st rt exception Multi
delCacheInMulti key multi = wrap $ DelCacheInMulti key multi id

delCache :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error String)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ DelCache cacheConn key id

setCacheWithExpireInMulti :: forall st rt exception. String -> String -> String -> Multi -> BackendFlow st rt exception Multi
setCacheWithExpireInMulti key value ttl multi = wrap $ SetCacheWithExpiryInMulti key value ttl multi id

setCacheWithExpiry :: forall st rt exception. String -> String -> String -> String -> BackendFlow st rt exception (Either Error String)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCacheWithExpiry cacheConn key value ttl id

log :: forall st rt exception a. String -> a -> BackendFlow st rt exception Unit
log tag message = wrap $ Log tag message unit

expireInMulti :: forall st rt exception. String -> String -> Multi -> BackendFlow st rt exception Multi
expireInMulti key ttl multi = wrap $ ExpireInMulti key ttl multi id

expire :: forall st rt exception. String -> String -> String -> BackendFlow st rt exception (Either Error String)
expire cacheName key ttl = do 
  cacheConn <- getCacheConn cacheName
  wrap $ Expire cacheConn key ttl id

incrInMulti :: forall st rt exception. String -> Multi -> BackendFlow st rt exception Multi
incrInMulti key multi = wrap $ IncrInMulti key multi id

incr :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error String)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ Incr cacheConn key id

setHashInMulti :: forall st rt exception. String -> String -> String -> Multi -> BackendFlow st rt exception Multi
setHashInMulti key field value multi = wrap $ SetHashInMulti key field value multi id 

setHash :: forall st rt exception. String -> String -> String -> String -> BackendFlow st rt exception (Either Error String)
setHash cacheName key field value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetHash cacheConn key field value id

getHashKeyInMulti :: forall st rt exception. String -> String -> Multi -> BackendFlow st rt exception Multi
getHashKeyInMulti key field multi = wrap $ GetHashInMulti key field multi id

getHashKey :: forall st rt exception. String -> String -> String -> BackendFlow st rt exception (Either Error String)
getHashKey cacheName key field = do 
  cacheConn <- getCacheConn cacheName
  wrap $ GetHashKey cacheConn key field id 

setWithOptionsInMulti :: forall st rt exception. Array String -> Multi -> BackendFlow st rt exception Multi
setWithOptionsInMulti arr multi = wrap $ SetWithOptionsInMulti  arr multi id

setWithOptions :: forall st rt exception. String -> Array String -> BackendFlow st rt exception (Either Error String)
setWithOptions cacheName arr = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetWithOptions cacheConn arr id 
  
publishToChannelInMulti :: forall st rt exception. String -> String -> Multi -> BackendFlow st rt exception Multi
publishToChannelInMulti channel message multi = wrap $ PublishToChannelInMulti channel message multi id

publishToChannel :: forall st rt exception. String -> String -> String -> BackendFlow st rt exception (Either Error String)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  wrap $ PublishToChannel cacheConn channel message id

subscribeToMulti :: forall st rt exception. String -> Multi -> BackendFlow st rt exception Multi
subscribeToMulti channel multi = wrap $ SubscribeInMulti channel multi id

subscribe :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error String)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  wrap $ Subscribe cacheConn channel id

enqueueInMulti :: forall st rt exception. String -> String -> Multi -> BackendFlow st rt exception Multi
enqueueInMulti listName value multi = wrap $ EnqueueInMulti listName value multi id

enqueue :: forall st rt exception. String -> String -> String -> BackendFlow st rt exception (Either Error Unit)
enqueue cacheName listName value = do
  cacheConn <- getCacheConn cacheName
  wrap $ Enqueue cacheConn listName value id

dequeueInMulti :: forall st rt exception. String -> Multi -> BackendFlow st rt exception Multi
dequeueInMulti listName multi = wrap $ DequeueInMulti listName multi id

dequeue :: forall st rt exception. String -> String -> BackendFlow st rt exception (Either Error (Maybe String))
dequeue cacheName listName = do
  cacheConn <- getCacheConn cacheName
  wrap $ Dequeue cacheConn listName id

getQueueIdxInMulti :: forall st rt exception. String -> Int -> Multi -> BackendFlow st rt exception Multi
getQueueIdxInMulti listName index multi = wrap $ GetQueueIdxInMulti listName index multi id

getQueueIdx :: forall st rt exception. String -> String -> Int -> BackendFlow st rt exception (Either Error String)
getQueueIdx cacheName listName index = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetQueueIdx cacheConn listName index id

execMulti :: forall st rt exception. Multi -> BackendFlow st rt exception (Either Error (Array String))
execMulti multi = wrap $ Exec multi id

setMessageHandler :: forall st rt exception. String -> (forall eff. (String -> String -> Eff eff Unit)) -> BackendFlow st rt exception (Either Error String)
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetMessageHandler cacheConn f id

runSysCmd :: forall st rt exception. String -> BackendFlow st rt exception String
runSysCmd cmd = wrap $ RunSysCmd cmd id

forkFlow :: forall st rt exception a. BackendFlow st rt exception a -> BackendFlow st rt exception Unit
forkFlow flow = wrap $ Fork flow id
