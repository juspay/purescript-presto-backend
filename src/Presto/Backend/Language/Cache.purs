module Presto.Backend.Cache where

import Prelude

import Cache (CacheConn, delKey, getKey, setKey, setex)
import Cache as Cache
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Free (Free)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.StrMap (lookup)
import Presto.Backend.Flow (BackendFlow, Connection(..), connFlow, doAff, throwException)
import Presto.Core.Flow (class Inject, class Run, inject)

data CacheF next =
      GetCacheConn String (Maybe CacheConn -> next)
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


instance runCacheF :: Run CacheF BackendFlow where
  runAlgebra (GetCacheConn name next) = do
    maybeCache <- connFlow (pure <<< lookup name)
    case maybeCache of
      Just (Redis cache) -> pure $ next $ Just cache
      _ -> throwException "No Cache Found" *> pure (next Nothing)
  runAlgebra (SetCache conn key value next) = doAff (setKey conn key value) >>= (pure <<< next)
  runAlgebra (SetCacheWithExpiry conn key value ttl next) = doAff (setex conn key value ttl) >>= (pure <<< next)
  runAlgebra (GetCache conn key next) = doAff (getKey conn key) >>= (pure <<< next)
  runAlgebra (DelCache conn key next) = doAff (delKey conn key) >>= (pure <<< next)
  runAlgebra (Expire conn key ttl next) = doAff (Cache.expire conn key ttl) >>= (pure <<< next)
  runAlgebra (Incr conn key next) = doAff (Cache.incr conn key) >>= (pure <<< next)
  runAlgebra (SetHash conn key value next) = doAff (Cache.setHash conn key value) >>= (pure <<< next)
  runAlgebra (GetHashKey conn key value next) = doAff (Cache.getHashKey conn key value) >>= (pure <<< next)
  runAlgebra (PublishToChannel conn channel msg next) = doAff (Cache.publishToChannel conn channel msg) >>= (pure <<< next)
  runAlgebra (Subscribe conn channel next) = doAff (Cache.subscribe conn channel) >>= (pure <<< next)
  runAlgebra (SetMessageHandler conn f next) = doAff (Cache.setMessageHandler conn f) >>= (pure <<< next)

getCacheConn :: forall f. Inject CacheF f => String -> Free f (Maybe CacheConn)
getCacheConn dbName = inject $ GetCacheConn dbName id

withConn :: forall f a. (Cache.CacheConn -> Free f (Either Error a)) -> Maybe Cache.CacheConn -> Free f (Either Error a)
withConn f (Just conn) = f conn
withConn _ Nothing     = pure $ Left $ error "No Cache Connection"

setCache :: forall f. Inject CacheF f => String -> String ->  String -> Free f (Either Error String)
setCache cacheName key value = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ SetCache cacheConn key value id)

getCache :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
getCache cacheName key = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ GetCache cacheConn key id)

delCache :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
delCache cacheName key = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ DelCache cacheConn key id)

setCacheWithExpiry :: forall f. Inject CacheF f => String -> String -> String -> String -> Free f (Either Error String)
setCacheWithExpiry cacheName key value ttl = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ SetCacheWithExpiry cacheConn key value ttl id)

expire :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
expire cacheName key ttl = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ Expire cacheConn key ttl id)

incr :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
incr cacheName key = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ Incr cacheConn key id)

setHash :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
setHash cacheName key value = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ SetCache cacheConn key value id)

getHashKey :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
getHashKey cacheName key field = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ GetHashKey cacheConn key field id)

publishToChannel :: forall f. Inject CacheF f => String -> String -> String -> Free f (Either Error String)
publishToChannel cacheName channel message = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ PublishToChannel cacheConn channel message id)

subscribe :: forall f. Inject CacheF f => String -> String -> Free f (Either Error String)
subscribe cacheName channel = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ Subscribe cacheConn channel id)

setMessageHandler :: forall f. Inject CacheF f => String -> (String -> String -> Unit) -> Free f (Either Error String)
setMessageHandler cacheName f = getCacheConn cacheName >>= withConn (\cacheConn -> inject $ SetMessageHandler cacheConn f id)
