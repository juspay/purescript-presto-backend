module Presto.Backend.Cache where

import Prelude

import Cache (CacheConn)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Free (Free)
import Data.Either (Either)
import Presto.Core.Flow (class Inject, inject)

data CacheF next =
      GetCacheConn String (CacheConn -> next)
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
    | SetMessageHandler CacheConn (String -> String -> Unit) (Either Error String -> next)

instance functorCacheF :: Functor CacheF where
    map f (GetCacheConn g h) = GetCacheConn g (f <<< h)
    map f (SetCache c d e h) = SetCache c d e (f <<< h)
    map f (SetCacheWithExpiry c d e g h) = SetCacheWithExpiry c d e g (f <<< h)
    map f (GetCache c d h) = GetCache c d (f <<< h)
    map f (DelCache c d h) = DelCache c d (f <<< h)
    map f (Expire c d e h) = Expire c d e (f <<< h)
    map f (Incr c d h) = Incr c d (f <<< h)
    map f (SetHash c d e h) = SetHash c d e (f <<< h)
    map f (GetHashKey c d e h) = GetHashKey c d e (f <<< h)
    map f (PublishToChannel c d e h) = PublishToChannel c d e (f <<< h)
    map f (Subscribe c d h) = Subscribe c d (f <<< h)
    map f (SetMessageHandler c d h) = SetMessageHandler c d (f <<< h)


getCacheConn :: forall f. Inject CacheF f => String -> Free f CacheConn
getCacheConn dbName = inject $ GetCacheConn dbName id

setCache :: forall f. Inject CacheF f => String -> String ->  String -> Free f (Either Error String)
setCache cacheName key value = do
  cacheConn <- getCacheConn cacheName
  inject $ SetCache cacheConn key value id

getCache :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
getCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  inject $ GetCache cacheConn key id

delCache :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
delCache cacheName key = do
  cacheConn <- getCacheConn cacheName
  inject $ DelCache cacheConn key id

setCacheWithExpiry :: forall f. Inject CacheF f => String -> String -> String -> String -> Free f (Either Error String)
setCacheWithExpiry cacheName key value ttl = do
  cacheConn <- getCacheConn cacheName
  inject $ SetCacheWithExpiry cacheConn key value ttl id

expire :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
expire cacheName key ttl = do 
  cacheConn <- getCacheConn cacheName
  inject $ Expire cacheConn key ttl id

incr :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
incr cacheName key = do
  cacheConn <- getCacheConn cacheName
  inject $ Incr cacheConn key id

setHash :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
setHash cacheName key value = do
  cacheConn <- getCacheConn cacheName
  inject $ SetCache cacheConn key value id

getHashKey :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
getHashKey cacheName key field = do 
  cacheConn <- getCacheConn cacheName
  inject $ GetHashKey cacheConn key field id 

publishToChannel :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
publishToChannel cacheName channel message = do
  cacheConn <- getCacheConn cacheName
  inject $ PublishToChannel cacheConn channel message id

subscribe :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
subscribe cacheName channel = do
  cacheConn <- getCacheConn cacheName
  inject $ Subscribe cacheConn channel id

setMessageHandler :: forall f. Inject CacheF f => String -> (String -> String -> Unit) -> Free f (Either Error String)
setMessageHandler cacheName f = do
  cacheConn <- getCacheConn cacheName
  inject $ SetMessageHandler cacheConn f id