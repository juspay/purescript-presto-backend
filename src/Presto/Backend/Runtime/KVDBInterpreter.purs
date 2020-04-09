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

module Presto.Backend.Runtime.KVDBInterpreter
  ( runKVDB
  ) where

import Prelude

import Cache (SetOptions(..), SimpleConn, del, exists, expire, get, incr, publish, set, setMessageHandler, subscribe)
import Cache.Hash (hget, hset)
import Cache.Multi as Native
import Cache.List (lindex, lpop, rpush)
import Cache.Multi (execMulti, expireMulti, getMulti, hgetMulti, hsetMulti, incrMulti, lindexMulti, lpopMulti, newMulti, publishMulti, rpushMulti, setMulti, subscribeMulti, xaddMulti)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Aff.AVar (AVAR, putVar, takeVar, readVar)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, message)
import Control.Monad.Free (foldFree)
import Data.Array.NonEmpty (singleton) as NEArray
import Data.Either (Either(..))
import Data.Exists (runExists)
import Data.Maybe (Maybe(Just, Nothing))
import Data.StrMap as StrMap
import Data.UUID (GENUUID, genUUID)
import Presto.Backend.Language.KVDB (KVDB, KVDBMethod(..), KVDBMethodWrapper, KVDBWrapper(..))
import Presto.Backend.Language.Types.DB (KVDBConn(MockedKVDB, Redis), MockedKVDBConn)
import Presto.Backend.Language.Types.KVDB (Multi(..), getMultiGUID)
import Presto.Backend.KVDB.Mock.Types (KVDBActionDict)
import Presto.Backend.Runtime.Common (getKVDBConn', lift3, throwException')
import Presto.Backend.Runtime.Types (BackendRuntime(BackendRuntime), InterpreterMT', KVDBRuntime(KVDBRuntime))
import Presto.Backend.Playback.Types (RRItemDict)
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)


getMockedKVDBValue :: forall st rt eff a. BackendRuntime -> KVDBActionDict -> InterpreterMT' rt st eff a
getMockedKVDBValue brt mockedKvDbActDict = throwException' "Mocking is not yet implemented for KV DB."

getNativeMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Aff (avar :: AVAR | eff) (Maybe Native.Multi)
getNativeMulti (KVDBRuntime rt) multi = do
  let guid = getMultiGUID multi
  catalogue <- readVar rt.multiesVar
  pure $ StrMap.lookup guid catalogue

registerNativeMulti
  :: forall eff
   . KVDBRuntime
  -> String
  -> Native.Multi
  -> Aff (avar :: AVAR | eff) Unit
registerNativeMulti (KVDBRuntime rt) uuidStr nativeMulti = do
  catalogue <- takeVar rt.multiesVar
  putVar (StrMap.insert uuidStr nativeMulti catalogue) rt.multiesVar

registerNewMulti
  :: forall eff
   . KVDBRuntime
  -> String
  -> Native.Multi
  -> Aff (avar :: AVAR, uuid :: GENUUID | eff) Multi
registerNewMulti kvdbRt@(KVDBRuntime rt) kvdbName nativeMulti = do
  uuidStr <- show <$> liftEff genUUID
  registerNativeMulti kvdbRt uuidStr nativeMulti
  pure $ Multi kvdbName uuidStr

unregisterMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Aff (avar :: AVAR | eff) Unit
unregisterMulti (KVDBRuntime rt) multi = do
  let guid = getMultiGUID multi
  catalogue <- takeVar rt.multiesVar
  putVar (StrMap.delete guid catalogue) rt.multiesVar

updateNativeMulti
  :: forall eff
   . KVDBRuntime
  -> Multi
  -> Native.Multi
  -> Aff (avar :: AVAR, uuid :: GENUUID | eff) Unit
updateNativeMulti kvdbRt multi newNativeMulti =
  registerNativeMulti kvdbRt (getMultiGUID multi) newNativeMulti

withNativeMulti
  :: forall rt st eff
   . KVDBRuntime
  -> Multi
  -> (Native.Multi -> InterpreterMT' rt st eff Native.Multi)
  -> InterpreterMT' rt st eff Unit
withNativeMulti kvdbRt multi act = do
  mbNativeMulti <- lift3 $ getNativeMulti kvdbRt multi
  case mbNativeMulti of
    Nothing -> throwException' $ "Multi not found: " <> show multi
    Just nativeMulti -> do
      nativeMulti' <- act nativeMulti
      lift3 $ updateNativeMulti kvdbRt multi nativeMulti'

withNativeMultiEx
  :: forall rt st eff
   . KVDBRuntime
  -> Multi
  -> (Native.Multi -> InterpreterMT' rt st eff (Either Error Native.Multi))
  -> InterpreterMT' rt st eff (Either Error Native.Multi)
withNativeMultiEx kvdbRt multi act = do
  mbNativeMulti <- lift3 $ getNativeMulti kvdbRt multi
  case mbNativeMulti of
    Nothing -> throwException' $ "Multi not found: " <> show multi
    Just nativeMulti -> do
      res <- act nativeMulti
      case res of
        Left err -> lift3 $ pure (Left err)
        Right m -> do
          lift3 $ updateNativeMulti kvdbRt multi m
          lift3 $ pure res

interpretKVDB
  :: forall st rt s eff a
   . KVDBRuntime
  -> String
  -> SimpleConn
  -> KVDBMethodWrapper s a
  -> InterpreterMT' rt st eff a

-- TODO: why ignoring Boolean result here?
interpretKVDB _ _ simpleConn (SetCache key value mbTtl next) =
  (lift3 $ void <$> set simpleConn key value mbTtl NoOptions) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (SetCacheWithOpts key value mbTtl opts next) =
  (lift3 $ set simpleConn key value mbTtl opts) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (GetCache key next) =
  (lift3 $ get simpleConn key) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (KeyExistsCache key next) =
  (lift3 $ exists simpleConn key) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (DelCache key next) =
  (lift3 $ del simpleConn (NEArray.singleton key)) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (Expire key ttl next) =
  (lift3 $ expire simpleConn key ttl) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (Incr key next) =
  (lift3 $ incr simpleConn key) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (SetHash key field value next) =
  (lift3 $ hset simpleConn key field value) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (GetHashKey key field next) =
  (lift3 $ hget simpleConn key field) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (PublishToChannel channel message next) =
  (lift3 $ publish simpleConn channel message) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (Subscribe channel next) =
  (lift3 $ subscribe simpleConn (NEArray.singleton channel)) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (Enqueue listName value next) =
  (lift3 $ void <$> rpush simpleConn listName value) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (Dequeue listName next) =
  (lift3 $ lpop simpleConn listName) >>= (pure <<< next)

interpretKVDB _ _ simpleConn (GetQueueIdx listName index next) =
  (lift3 $ lindex simpleConn listName index) >>= (pure <<< next)

interpretKVDB kvdbRt@(KVDBRuntime rt) dbName simpleConn (NewMulti next) = do
  nativeMulti <- lift3 $ liftEff $ newMulti simpleConn
  multi       <- lift3 $ registerNewMulti kvdbRt dbName nativeMulti
  pure $ next multi

-- Is this a bug? "setMulti"
interpretKVDB kvdbRt _ _ (SetCacheInMulti key val mbTtl multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< setMulti key val mbTtl NoOptions
  pure $ next multi

-- Is this a bug? This method does nothing.
interpretKVDB kvdbRt _ _ (GetCacheInMulti key multi next) =
  -- (R.lift <<< S.lift <<< E.lift <<< pure <<< next $ multi)
  throwException' "GetCacheInMulti not implemented."

-- Is this a bug? "getMulti"
interpretKVDB kvdbRt _ _ (DelCacheInMulti key multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< getMulti key
  pure $ next multi

interpretKVDB kvdbRt _ _ (ExpireInMulti key ttl multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< expireMulti key ttl
  pure $ next multi

interpretKVDB kvdbRt _ _ (IncrInMulti key multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< incrMulti key
  pure $ next multi

interpretKVDB kvdbRt _ _ (SetHashInMulti key field value multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< hsetMulti key field value
  pure $ next multi

interpretKVDB kvdbRt _ _ (GetHashInMulti key value multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< hgetMulti key value
  pure $ next multi

interpretKVDB kvdbRt _ _ (PublishToChannelInMulti channel message multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< publishMulti channel message
  pure $ next multi

interpretKVDB kvdbRt _ _ (SubscribeInMulti channel multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< subscribeMulti channel
  pure $ next multi

interpretKVDB kvdbRt _ _ (EnqueueInMulti listName val multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< rpushMulti listName val
  pure $ next multi

interpretKVDB kvdbRt _ _ (DequeueInMulti listName multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< lpopMulti listName
  pure $ next multi

interpretKVDB kvdbRt _ _ (GetQueueIdxInMulti listName index multi next) = do
  withNativeMulti kvdbRt multi $ lift3 <<< liftEff <<< lindexMulti listName index
  pure $ next multi

interpretKVDB kvdbRt _ _ (Exec multi next) = do
  mbNativeMulti <- lift3 $ getNativeMulti kvdbRt multi
  case mbNativeMulti of
    Nothing          -> throwException' $ "Multi not found: " <> show multi
    Just nativeMulti -> do
      lift3 $ unregisterMulti kvdbRt multi
      next <$> (liftAff $ execMulti nativeMulti)

interpretKVDB _ _ simpleConn (SetMessageHandler f next) =
  (lift3 $ liftEff $ setMessageHandler simpleConn f) >>= (pure <<< next)

interpretKVDB kvdbRt dbName _ (AddInMulti key entryId args multi next) = do
  res <- withNativeMultiEx kvdbRt multi $ lift3 <<< liftEff <<< xaddMulti key entryId args
  case res of
    Left err -> pure $ next (Left err)
    Right m -> do
      resn  <- (lift3 $ registerNewMulti kvdbRt dbName m)
      pure $ next (Right resn)

runKVDB'
  :: forall st rt eff a
   . BackendRuntime
  -> String
  -> SimpleConn
  -> KVDB a
  -> InterpreterMT' rt st eff a
runKVDB' (BackendRuntime rt) dbName simpleConn =
  foldFree (\(KVDBWrapper x) -> runExists (interpretKVDB rt.kvdbRuntime dbName simpleConn) x)

runKVDB
  :: forall st rt eff rrItem a
   . BackendRuntime
  -> String
  -> KVDB a
  -> (MockedKVDBConn -> KVDBActionDict)
  -> RRItemDict rrItem a
  -> InterpreterMT' rt st eff a
runKVDB brt dbName kvDBAct mockedKvDbActDictF rrItemDict = do
  conn' <- getKVDBConn' brt dbName
  case conn' of
    Redis simpleConn -> withRunModeClassless brt rrItemDict
        (runKVDB' brt dbName simpleConn kvDBAct)
    MockedKVDB mocked -> withRunModeClassless brt rrItemDict
        (getMockedKVDBValue brt $ mockedKvDbActDictF mocked)
