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

import Cache (SimpleConn)
import Cache.Multi (Multi)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (Error, error, message)
import Control.Monad.Free (Free, liftF)
import Data.Either (Either(..))
import Data.Exists (Exists, mkExists)
import Data.Foreign (Foreign)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Foreign.Generic (encodeJSON)
import Data.Lazy (defer)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Data.Time.Duration (Milliseconds, Seconds)
import Presto.Backend.DB (findOne, findAll, create, createWithOpts, query, update, delete) as DB
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (ErrorResponse, APIResult)
import Presto.Backend.APIInteract (apiInteract)
import Presto.Backend.Types.EitherEx (EitherEx(..), fromCustomExError, toCustomExError)
import Presto.Backend.Playback.Types as Playback
import Presto.Backend.Playback.Entries as Playback
import Presto.Backend.Types.API (class RestEndpoint, Headers, makeRequest)
import Presto.Backend.DB.Types (DBError)
import Presto.Core.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn, Instance, SEQUELIZE)

data BackendFlowCommands next st rt s =
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)

    | CallAPI (Interaction (EitherEx ErrorResponse s))
        (Playback.RRItemDict Playback.CallAPIEntry (EitherEx ErrorResponse s))
        (APIResult s -> next)

    | DoAff (forall eff. BackendAff eff s) (s -> next)

    | DoAffRR (forall eff. BackendAff eff s)
        (Playback.RRItemDict Playback.DoAffEntry s)
        (s -> next)

    | ThrowException String (s -> next)

    | RunDB (forall eff. Aff (sequelize :: SEQUELIZE | eff) (EitherEx DBError s))
        (Playback.RRItemDict Playback.RunDBEntry (EitherEx DBError s))
        (EitherEx DBError s -> next)

    | GetDBConn String (Conn -> next)
    | GetCacheConn String (SimpleConn -> next)
    | Log String s (Unit -> next)

    | SetCache SimpleConn String String (Either Error Unit -> next)
    | SetCacheWithExpiry SimpleConn String String Milliseconds (Either Error Unit -> next)
    | GetCache SimpleConn String (Either Error (Maybe String) -> next)
    | KeyExistsCache SimpleConn String (Either Error Boolean -> next)
    | DelCache SimpleConn String (Either Error Int -> next)
    | Enqueue SimpleConn String String (Either Error Unit -> next)
    | Dequeue SimpleConn String (Either Error (Maybe String) -> next)
    | GetQueueIdx SimpleConn String Int (Either Error (Maybe String) -> next)
    | Fork (BackendFlow st rt s) (Unit -> next)
    | Expire SimpleConn String Seconds (Either Error Boolean -> next)
    | Incr SimpleConn String (Either Error Int -> next)
    | SetHash SimpleConn String String String (Either Error Boolean -> next)
    | GetHashKey SimpleConn String String (Either Error (Maybe String) -> next)
    | PublishToChannel SimpleConn String String (Either Error Int -> next)
    | Subscribe SimpleConn String (Either Error Unit -> next)
    | SetMessageHandler SimpleConn (forall eff. (String -> String -> Eff eff Unit)) (Unit -> next)
    | GetMulti SimpleConn (Multi -> next)
    | SetCacheInMulti String String Multi (Multi -> next)
    | GetCacheInMulti String Multi (Multi -> next)
    | DelCacheInMulti String Multi (Multi -> next)
    | SetCacheWithExpiryInMulti String String Milliseconds Multi (Multi -> next)
    | ExpireInMulti String Seconds Multi (Multi -> next)
    | IncrInMulti String Multi (Multi -> next)
    | SetHashInMulti String String String Multi (Multi -> next)
    | GetHashInMulti String String Multi (Multi -> next)
    | PublishToChannelInMulti String String Multi (Multi -> next)
    | SubscribeInMulti String Multi (Multi -> next)
    | EnqueueInMulti String String Multi (Multi -> next)
    | DequeueInMulti String Multi (Multi -> next)
    | GetQueueIdxInMulti String Int Multi (Multi -> next)
    | Exec Multi (Either Error (Array Foreign) -> next)
    | RunSysCmd String
        (Playback.RRItemDict Playback.RunSysCmdEntry String)
        (String -> next)


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

doAffRR
  :: forall st rt a
   . Encode a
  => Decode a
  => (forall eff. BackendAff eff a)
  -> BackendFlow st rt a
doAffRR aff = wrap $ DoAffRR aff (Playback.mkEntryDict Playback.mkDoAffEntry) id

-- TODO: TASK: add options, model and other input params to recording so it they be compared.
-- TODO: Think what to do with getDBCon.

findOne
  :: forall model st rt
   . Model model
  => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.findOne conn options)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "findOne")
    id
  pure $ fromCustomExError eResEx

findAll
  :: forall model st rt
   . Model model
  => String -> Options model -> BackendFlow st rt (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.findAll conn options)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "findAll")
    id
  pure $ fromCustomExError eResEx

query
  :: forall a st rt
   . Encode a
  => Decode a
  => String -> String -> BackendFlow st rt (Either Error (Array a))
query dbName rawq = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.query conn rawq)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "query")
    id
  pure $ fromCustomExError eResEx

create :: forall model st rt. Model model => String -> model -> BackendFlow st rt (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.create conn model)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "create")
    id
  pure $ fromCustomExError eResEx

createWithOpts :: forall model st rt. Model model => String -> model -> Options model -> BackendFlow st rt (Either Error (Maybe model))
createWithOpts dbName model options = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.createWithOpts conn model options)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "createWithOpts")
    id
  pure $ fromCustomExError eResEx

update :: forall model st rt. Model model => String -> Options model -> Options model -> BackendFlow st rt (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.update conn updateValues whereClause)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "update")
    id
  pure $ fromCustomExError eResEx

delete :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  eResEx <- wrap $ RunDB
    (toCustomExError <$> DB.delete conn options)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "delete")
    id
  pure $ fromCustomExError eResEx

getDBConn :: forall st rt. String -> BackendFlow st rt Conn
getDBConn dbName = wrap $ GetDBConn dbName id

getCacheConn :: forall st rt. String -> BackendFlow st rt SimpleConn
getCacheConn dbName = wrap $ GetCacheConn dbName id

newMulti :: forall st rt. String -> BackendFlow st rt Multi
newMulti cacheName = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetMulti cacheConn id

callAPI
  :: forall st rt a b
   . Encode a
  => Encode b
  => Decode b
  => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt (APIResult b)
callAPI headers a = wrap $ CallAPI
  (apiInteract a headers)
  (Playback.mkEntryDict (Playback.mkCallAPIEntry (defer $ \_ -> encodeJSON $ makeRequest a headers) ))
  id

setCacheInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
setCacheInMulti key value multi = wrap $ SetCacheInMulti key value multi id

setCache :: forall st rt. String -> String ->  String -> BackendFlow st rt (Either Error Unit)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCache cacheConn key value id

getCacheInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
getCacheInMulti key multi = wrap $ GetCacheInMulti key multi id

getCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error (Maybe String))
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetCache cacheConn key id

keyExistsCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error Boolean)
keyExistsCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ KeyExistsCache cacheConn key id

delCacheInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
delCacheInMulti key multi = wrap $ DelCacheInMulti key multi id

delCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error Int)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ DelCache cacheConn key id

setCacheWithExpireInMulti :: forall st rt. String -> String -> Milliseconds -> Multi -> BackendFlow st rt Multi
setCacheWithExpireInMulti key value ttl multi = wrap $ SetCacheWithExpiryInMulti key value ttl multi id

setCacheWithExpiry :: forall st rt. String -> String -> String -> Milliseconds -> BackendFlow st rt (Either Error Unit)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetCacheWithExpiry cacheConn key value ttl id

log :: forall st rt a. String -> a -> BackendFlow st rt Unit
log tag message = wrap $ Log tag message id

expireInMulti :: forall st rt. String -> Seconds -> Multi -> BackendFlow st rt Multi
expireInMulti key ttl multi = wrap $ ExpireInMulti key ttl multi id

expire :: forall st rt. String -> String -> Seconds -> BackendFlow st rt (Either Error Boolean)
expire cacheName key ttl = do
  cacheConn <- getCacheConn cacheName
  wrap $ Expire cacheConn key ttl id

incrInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
incrInMulti key multi = wrap $ IncrInMulti key multi id

incr :: forall st rt. String -> String -> BackendFlow st rt (Either Error Int)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  wrap $ Incr cacheConn key id

setHashInMulti :: forall st rt. String -> String -> String -> Multi -> BackendFlow st rt Multi
setHashInMulti key field value multi = wrap $ SetHashInMulti key field value multi id

setHash :: forall st rt. String -> String -> String -> String -> BackendFlow st rt (Either Error Boolean)
setHash cacheName key field value = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetHash cacheConn key field value id

getHashKeyInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
getHashKeyInMulti key field multi = wrap $ GetHashInMulti key field multi id

getHashKey :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error (Maybe String))
getHashKey cacheName key field = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetHashKey cacheConn key field id

publishToChannelInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
publishToChannelInMulti channel message multi = wrap $ PublishToChannelInMulti channel message multi id

publishToChannel :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error Int)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  wrap $ PublishToChannel cacheConn channel message id

subscribeToMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
subscribeToMulti channel multi = wrap $ SubscribeInMulti channel multi id

subscribe :: forall st rt. String -> String -> BackendFlow st rt (Either Error Unit)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  wrap $ Subscribe cacheConn channel id

enqueueInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
enqueueInMulti listName value multi = wrap $ EnqueueInMulti listName value multi id

enqueue :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error Unit)
enqueue cacheName listName value = do
  cacheConn <- getCacheConn cacheName
  wrap $ Enqueue cacheConn listName value id

dequeueInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
dequeueInMulti listName multi = wrap $ DequeueInMulti listName multi id

dequeue :: forall st rt. String -> String -> BackendFlow st rt (Either Error (Maybe String))
dequeue cacheName listName = do
  cacheConn <- getCacheConn cacheName
  wrap $ Dequeue cacheConn listName id

getQueueIdxInMulti :: forall st rt. String -> Int -> Multi -> BackendFlow st rt Multi
getQueueIdxInMulti listName index multi = wrap $ GetQueueIdxInMulti listName index multi id

getQueueIdx :: forall st rt. String -> String -> Int -> BackendFlow st rt (Either Error (Maybe String))
getQueueIdx cacheName listName index = do
  cacheConn <- getCacheConn cacheName
  wrap $ GetQueueIdx cacheConn listName index id

execMulti :: forall st rt. Multi -> BackendFlow st rt (Either Error (Array Foreign))
execMulti multi = wrap $ Exec multi id

setMessageHandler :: forall st rt. String -> (forall eff. (String -> String -> Eff eff Unit)) -> BackendFlow st rt Unit
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  wrap $ SetMessageHandler cacheConn f id

runSysCmd :: forall st rt. String -> BackendFlow st rt String
runSysCmd cmd = wrap $ RunSysCmd cmd (Playback.mkEntryDict $ Playback.mkRunSysCmdEntry cmd) id

forkFlow :: forall st rt a. BackendFlow st rt a -> BackendFlow st rt Unit
forkFlow flow = wrap $ Fork flow id
