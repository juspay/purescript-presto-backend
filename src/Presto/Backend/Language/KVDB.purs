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

module Presto.Backend.Language.KVDB where

import Prelude

import Cache.Types (Entry(..), EntryID(..), Item(..), SetOptions, TrimStrategy)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Free (Free, liftF)
import Data.Either (Either)
import Data.Exists (Exists, mkExists)
import Data.Foreign (Foreign)
import Data.Maybe (Maybe)
import Data.StrMap (StrMap)
import Data.Time.Duration (Milliseconds, Seconds)
import Data.Tuple (Tuple)
import Presto.Backend.Language.Types.KVDB (Multi)

data KVDBMethod next s
    = SetCache String String (Maybe Milliseconds) (Either Error Unit -> next)
    | SetCacheWithOpts String String (Maybe Milliseconds) SetOptions (Either Error Boolean -> next)
    | GetCache String (Either Error (Maybe String) -> next)
    | KeyExistsCache String (Either Error Boolean -> next)
    | DelCache String (Either Error Int -> next)
    | Enqueue String String (Either Error Unit -> next)
    | Dequeue String (Either Error (Maybe String) -> next)
    | GetQueueIdx String Int (Either Error (Maybe String) -> next)
    | Expire String Seconds (Either Error Boolean -> next)
    | Incr String (Either Error Int -> next)
    | SetHash String String String (Either Error Boolean -> next)
    | GetHashKey String String (Either Error (Maybe String) -> next)
    | PublishToChannel String String (Either Error Int -> next)
    | Subscribe String (Either Error Unit -> next)

    | NewMulti (Multi -> next)
    | SetCacheInMulti String String (Maybe Milliseconds) Multi (Multi -> next)
    | GetCacheInMulti String Multi (Multi -> next)
    | DelCacheInMulti String Multi (Multi -> next)
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
    | AddInMulti  String EntryID  (Array Item)  Multi (Either Error Multi -> next)

    | SetMessageHandler (forall eff. (String -> String -> Eff eff Unit)) (Unit -> next)

    | AddToStream String EntryID (Array Item) (Either Error EntryID -> next)
    | GetFromStream String String (Maybe Int) Boolean (Array (Tuple String EntryID)) (Either Error (StrMap (Array Entry)) -> next)
    | CreateStreamGroup String String EntryID (Either Error Unit -> next)
    | TrimStream String TrimStrategy Boolean Int (Either Error Int -> next)
    | DeleteFromStream String EntryID (Either Error Int -> next)
    | GetStreamLength String (Either Error Int -> next)

type KVDBMethodWrapper s next = KVDBMethod next s

newtype KVDBWrapper next = KVDBWrapper (Exists (KVDBMethod next))

type KVDB next = Free KVDBWrapper next

addInMulti :: forall st rt. String -> EntryID -> (Array Item) -> Multi -> KVDB (Either Error Multi)
addInMulti key entryId args multi = wrapKVDBMethod $ AddInMulti key entryId args multi id

wrapKVDBMethod :: forall next s. KVDBMethod next s -> KVDB next
wrapKVDBMethod = liftF <<< KVDBWrapper <<< mkExists

newMulti :: forall st rt. KVDB Multi
newMulti = wrapKVDBMethod $ NewMulti id

setCacheInMulti :: forall st rt. String -> String -> Maybe Milliseconds -> Multi -> KVDB Multi
setCacheInMulti key value mbTtl multi = wrapKVDBMethod $ SetCacheInMulti key value mbTtl multi id

setCache :: forall st rt. String -> String -> Maybe Milliseconds -> KVDB (Either Error Unit)
setCache key value mbTtl = wrapKVDBMethod $ SetCache key value mbTtl id

setCacheWithOpts :: String -> String -> Maybe Milliseconds -> SetOptions -> KVDB (Either Error Boolean)
setCacheWithOpts key value mbTtl opts = wrapKVDBMethod $ SetCacheWithOpts key value mbTtl opts id

-- Why this function returns Multi???
getCacheInMulti :: forall st rt. String -> Multi -> KVDB Multi
getCacheInMulti key multi = wrapKVDBMethod $ GetCacheInMulti key multi id

getCache :: forall st rt. String -> KVDB (Either Error (Maybe String))
getCache key = wrapKVDBMethod $ GetCache key id

keyExistsCache :: forall st rt. String -> KVDB (Either Error Boolean)
keyExistsCache key = wrapKVDBMethod $ KeyExistsCache key id

delCacheInMulti :: forall st rt. String -> Multi -> KVDB Multi
delCacheInMulti key multi = wrapKVDBMethod $ DelCacheInMulti key multi id

delCache :: forall st rt. String -> KVDB (Either Error Int)
delCache key = wrapKVDBMethod $ DelCache key id

expireInMulti :: forall st rt. String -> Seconds -> Multi -> KVDB Multi
expireInMulti key ttl multi = wrapKVDBMethod $ ExpireInMulti key ttl multi id

expire :: forall st rt. String -> Seconds -> KVDB (Either Error Boolean)
expire key ttl = wrapKVDBMethod $ Expire key ttl id

incrInMulti :: forall st rt. String -> Multi -> KVDB Multi
incrInMulti key multi = wrapKVDBMethod $ IncrInMulti key multi id

incr :: forall st rt. String -> KVDB (Either Error Int)
incr key = wrapKVDBMethod $ Incr key id

setHashInMulti :: forall st rt. String -> String -> String -> Multi -> KVDB Multi
setHashInMulti key field value multi = wrapKVDBMethod $ SetHashInMulti key field value multi id

setHash :: forall st rt. String -> String -> String -> KVDB (Either Error Boolean)
setHash key field value = wrapKVDBMethod $ SetHash key field value id

getHashKeyInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
getHashKeyInMulti key field multi = wrapKVDBMethod $ GetHashInMulti key field multi id

getHashKey :: forall st rt. String -> String -> KVDB (Either Error (Maybe String))
getHashKey key field = wrapKVDBMethod $ GetHashKey key field id

publishToChannelInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
publishToChannelInMulti channel message multi = wrapKVDBMethod $ PublishToChannelInMulti channel message multi id

publishToChannel :: forall st rt. String -> String -> KVDB (Either Error Int)
publishToChannel channel message = wrapKVDBMethod $ PublishToChannel channel message id

subscribeToMulti :: forall st rt. String -> Multi -> KVDB Multi
subscribeToMulti channel multi = wrapKVDBMethod $ SubscribeInMulti channel multi id

subscribe :: forall st rt. String -> KVDB (Either Error Unit)
subscribe channel = wrapKVDBMethod $ Subscribe channel id

enqueueInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
enqueueInMulti listName value multi = wrapKVDBMethod $ EnqueueInMulti listName value multi id

enqueue :: forall st rt. String -> String -> KVDB (Either Error Unit)
enqueue listName value = wrapKVDBMethod $ Enqueue listName value id

dequeueInMulti :: forall st rt. String -> Multi -> KVDB Multi
dequeueInMulti listName multi = wrapKVDBMethod $ DequeueInMulti listName multi id

dequeue :: forall st rt. String -> KVDB (Either Error (Maybe String))
dequeue listName = wrapKVDBMethod $ Dequeue listName id

getQueueIdxInMulti :: forall st rt. String -> Int -> Multi -> KVDB Multi
getQueueIdxInMulti listName index multi = wrapKVDBMethod $ GetQueueIdxInMulti listName index multi id

getQueueIdx :: forall st rt. String -> Int -> KVDB (Either Error (Maybe String))
getQueueIdx listName index = wrapKVDBMethod $ GetQueueIdx listName index id

execMulti :: forall st rt. Multi -> KVDB (Either Error (Array Foreign))
execMulti multi = wrapKVDBMethod $ Exec multi id

setMessageHandler :: forall st rt. (forall eff. (String -> String -> Eff eff Unit)) -> KVDB Unit
setMessageHandler f = wrapKVDBMethod $ SetMessageHandler f id

addToStream :: forall st rt. String -> EntryID -> Array Item -> KVDB (Either Error EntryID)
addToStream key entryID args = wrapKVDBMethod $ AddToStream key entryID args id

getFromStream :: forall st rt. String -> String -> Maybe Int -> Boolean -> Array (Tuple String EntryID) -> KVDB (Either Error (StrMap (Array Entry)))
getFromStream groupName consumerName mCount noAck streamIds = wrapKVDBMethod $ GetFromStream groupName consumerName mCount noAck streamIds id

createStreamGroup :: forall st rt. String -> String -> EntryID -> KVDB (Either Error Unit)
createStreamGroup key groupName entryId = wrapKVDBMethod $ CreateStreamGroup key groupName entryId id

trimStream :: forall st rt. String -> TrimStrategy -> Boolean -> Int -> KVDB (Either Error Int)
trimStream key strategy approx len = wrapKVDBMethod $ TrimStream key strategy approx len id

deleteFromStream :: forall st rt. String -> EntryID -> KVDB (Either Error Int)
deleteFromStream key entryId = wrapKVDBMethod $ DeleteFromStream key entryId id

getStreamLength :: forall st rt. String -> KVDB (Either Error Int)
getStreamLength key = wrapKVDBMethod $ GetStreamLength key id