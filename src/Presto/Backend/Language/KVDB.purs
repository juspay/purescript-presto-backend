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

import Cache.Multi (Multi)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (Error, error, message)
import Control.Monad.Except (runExcept) as E
import Control.Monad.Free (Free, liftF)
import Data.Either (Either(..), note, hush, isLeft)
import Data.Exists (Exists, mkExists)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Foreign (Foreign, toForeign)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Foreign.Generic (encodeJSON)
import Data.Lazy (defer)
import Data.Options (Options)
import Data.Options (options) as Opt
import Data.Time.Duration (Milliseconds, Seconds)
import Presto.Backend.Language.Types.DB (DBError(..), toDBMaybeResult, fromDBMaybeResult)
import Presto.Core.Types.Language.Interaction (Interaction)

data KVDBMethod next s
    = SetCache String String String (Either Error Unit -> next)
    | SetCacheWithExpiry String String String Milliseconds (Either Error Unit -> next)
    | GetCache String String (Either Error (Maybe String) -> next)
    | KeyExistsCache String String (Either Error Boolean -> next)
    | DelCache String String (Either Error Int -> next)
    | Enqueue String String String (Either Error Unit -> next)
    | Dequeue String String (Either Error (Maybe String) -> next)
    | GetQueueIdx String String Int (Either Error (Maybe String) -> next)
    | Expire String String Seconds (Either Error Boolean -> next)
    | Incr String String (Either Error Int -> next)
    | SetHash String String String String (Either Error Boolean -> next)
    | GetHashKey String String String (Either Error (Maybe String) -> next)
    | PublishToChannel String String String (Either Error Int -> next)
    | Subscribe String String (Either Error Unit -> next)

    | GetMulti String (Multi -> next)
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

    | SetMessageHandler String (forall eff. (String -> String -> Eff eff Unit)) (Unit -> next)

type KVDBMethodWrapper s next = KVDBMethod next s

newtype KVDBWrapper next = KVDBWrapper (Exists (KVDBMethod next))

type KVDB next = Free KVDBWrapper next

wrapKVDBMethod :: forall next s. KVDBMethod next s -> KVDB next
wrapKVDBMethod = liftF <<< KVDBWrapper <<< mkExists

newMulti :: forall st rt. String -> KVDB Multi
newMulti cacheName = wrapKVDBMethod $ GetMulti cacheName id

setCacheInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
setCacheInMulti key value multi = wrapKVDBMethod $ SetCacheInMulti key value multi id

setCache :: forall st rt. String -> String ->  String -> KVDB (Either Error Unit)
setCache cacheName key value = wrapKVDBMethod $ SetCache cacheName key value id

getCacheInMulti :: forall st rt. String -> Multi -> KVDB Multi
getCacheInMulti key multi = wrapKVDBMethod $ GetCacheInMulti key multi id

getCache :: forall st rt. String -> String -> KVDB (Either Error (Maybe String))
getCache cacheName key = wrapKVDBMethod $ GetCache cacheName key id

keyExistsCache :: forall st rt. String -> String -> KVDB (Either Error Boolean)
keyExistsCache cacheName key = wrapKVDBMethod $ KeyExistsCache cacheName key id

delCacheInMulti :: forall st rt. String -> Multi -> KVDB Multi
delCacheInMulti key multi = wrapKVDBMethod $ DelCacheInMulti key multi id

delCache :: forall st rt. String -> String -> KVDB (Either Error Int)
delCache cacheName key = wrapKVDBMethod $ DelCache cacheName key id

setCacheWithExpireInMulti :: forall st rt. String -> String -> Milliseconds -> Multi -> KVDB Multi
setCacheWithExpireInMulti key value ttl multi = wrapKVDBMethod $ SetCacheWithExpiryInMulti key value ttl multi id

setCacheWithExpiry :: forall st rt. String -> String -> String -> Milliseconds -> KVDB (Either Error Unit)
setCacheWithExpiry cacheName key value ttl = wrapKVDBMethod $ SetCacheWithExpiry cacheName key value ttl id

expireInMulti :: forall st rt. String -> Seconds -> Multi -> KVDB Multi
expireInMulti key ttl multi = wrapKVDBMethod $ ExpireInMulti key ttl multi id

expire :: forall st rt. String -> String -> Seconds -> KVDB (Either Error Boolean)
expire cacheName key ttl = wrapKVDBMethod $ Expire cacheName key ttl id

incrInMulti :: forall st rt. String -> Multi -> KVDB Multi
incrInMulti key multi = wrapKVDBMethod $ IncrInMulti key multi id

incr :: forall st rt. String -> String -> KVDB (Either Error Int)
incr cacheName key = wrapKVDBMethod $ Incr cacheName key id

setHashInMulti :: forall st rt. String -> String -> String -> Multi -> KVDB Multi
setHashInMulti key field value multi = wrapKVDBMethod $ SetHashInMulti key field value multi id

setHash :: forall st rt. String -> String -> String -> String -> KVDB (Either Error Boolean)
setHash cacheName key field value = wrapKVDBMethod $ SetHash cacheName key field value id

getHashKeyInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
getHashKeyInMulti key field multi = wrapKVDBMethod $ GetHashInMulti key field multi id

getHashKey :: forall st rt. String -> String -> String -> KVDB (Either Error (Maybe String))
getHashKey cacheName key field = wrapKVDBMethod $ GetHashKey cacheName key field id

publishToChannelInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
publishToChannelInMulti channel message multi = wrapKVDBMethod $ PublishToChannelInMulti channel message multi id

publishToChannel :: forall st rt. String -> String -> String -> KVDB (Either Error Int)
publishToChannel cacheName channel message = wrapKVDBMethod $ PublishToChannel cacheName channel message id

subscribeToMulti :: forall st rt. String -> Multi -> KVDB Multi
subscribeToMulti channel multi = wrapKVDBMethod $ SubscribeInMulti channel multi id

subscribe :: forall st rt. String -> String -> KVDB (Either Error Unit)
subscribe cacheName channel = wrapKVDBMethod $ Subscribe cacheName channel id

enqueueInMulti :: forall st rt. String -> String -> Multi -> KVDB Multi
enqueueInMulti listName value multi = wrapKVDBMethod $ EnqueueInMulti listName value multi id

enqueue :: forall st rt. String -> String -> String -> KVDB (Either Error Unit)
enqueue cacheName listName value = wrapKVDBMethod $ Enqueue cacheName listName value id

dequeueInMulti :: forall st rt. String -> Multi -> KVDB Multi
dequeueInMulti listName multi = wrapKVDBMethod $ DequeueInMulti listName multi id

dequeue :: forall st rt. String -> String -> KVDB (Either Error (Maybe String))
dequeue cacheName listName = wrapKVDBMethod $ Dequeue cacheName listName id

getQueueIdxInMulti :: forall st rt. String -> Int -> Multi -> KVDB Multi
getQueueIdxInMulti listName index multi = wrapKVDBMethod $ GetQueueIdxInMulti listName index multi id

getQueueIdx :: forall st rt. String -> String -> Int -> KVDB (Either Error (Maybe String))
getQueueIdx cacheName listName index = wrapKVDBMethod $ GetQueueIdx cacheName listName index id

execMulti :: forall st rt. Multi -> KVDB (Either Error (Array Foreign))
execMulti multi = wrapKVDBMethod $ Exec multi id

setMessageHandler :: forall st rt. String -> (forall eff. (String -> String -> Eff eff Unit)) -> KVDB Unit
setMessageHandler cacheName f = wrapKVDBMethod $ SetMessageHandler cacheName f id
