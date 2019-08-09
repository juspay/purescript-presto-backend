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

import Cache.Types (EntryID(..), Item(..))
import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Except (runExcept)
import Control.Monad.Free (Free, liftF)
import Control.Monad (when, unless)
import Data.Either (Either(..))
import Data.String (null)
import Data.Exists (Exists, mkExists)
import Data.Foreign (Foreign, toForeign)
import Data.Foreign.Class (class Decode, class Encode, encode)
import Data.Foreign.Generic (encodeJSON, decodeJSON)
import Data.Maybe (Maybe(Just, Nothing))
import Data.Newtype (class Newtype)
import Data.Options (Options)
import Data.Options (options) as Opt
import Data.Time.Duration (Milliseconds, Seconds)
import Presto.Backend.APIInteract (apiInteract)
import Presto.Backend.DB.Mock.Actions (mkCreate, mkCreateWithOpts, mkDelete, mkFindAll, mkFindOne, mkQuery, mkUpdate) as SqlDBMock
import Presto.Backend.DB.Mock.Types (DBActionDict, mkDbActionDict) as SqlDBMock
import Presto.Backend.DBImpl (create, createWithOpts, delete, findAll, findOne, query, update, update') as DB
import Presto.Backend.KVDB.Mock.Types as KVDBMock
import Presto.Backend.Language.KVDB (KVDB, delCache, delCacheInMulti, dequeue, dequeueInMulti, enqueue, enqueueInMulti, execMulti, expire, expireInMulti, getCache, getCacheInMulti, getHashKey, getHashKeyInMulti, getQueueIdx, getQueueIdxInMulti, incr, incrInMulti, keyExistsCache, newMulti, publishToChannel, publishToChannelInMulti, setCache, setCacheInMulti, setHash, setHashInMulti, setMessageHandler, subscribe, subscribeToMulti, addInMulti) as KVDB
import Presto.Backend.Language.Types.DB (DBError, KVDBConn, MockedKVDBConn, MockedSqlConn, SqlConn, fromDBMaybeResult, toDBMaybeResult)
import Presto.Backend.Language.Types.EitherEx (EitherEx, fromCustomEitherEx, fromCustomEitherExF, toCustomEitherEx, toCustomEitherExF)
import Presto.Backend.Language.Types.MaybeEx (MaybeEx)
import Presto.Backend.Language.Types.KVDB (Multi)
import Presto.Backend.Language.Types.KVDB (getKVDBName) as KVDB
import Presto.Backend.Language.Types.UnitEx (UnitEx, fromUnitEx, toUnitEx)
import Presto.Backend.Playback.Entries (CallAPIEntry, GenerateGUIDEntry, DoAffEntry, ForkFlowEntry, GetDBConnEntry, GetKVDBConnEntry, LogEntry, GetOptionEntry, RunDBEntry, RunKVDBEitherEntry, RunKVDBSimpleEntry, RunSysCmdEntry, SetOptionEntry, mkCallAPIEntry, mkDoAffEntry, mkForkFlowEntry, mkGetDBConnEntry, mkGetKVDBConnEntry, mkLogEntry, mkGetOptionEntry, mkRunDBEntry, mkRunKVDBEitherEntry, mkRunKVDBSimpleEntry, mkRunSysCmdEntry, mkGenerateGUIDEntry, mkSetOptionEntry) as Playback
import Presto.Backend.Playback.Types (RRItemDict, mkEntryDict) as Playback
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (class RestEndpoint, Headers, ErrorResponse, APIResult, makeRequest)
import Presto.Backend.Types.Options (class OptionEntity)
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Core.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn, SEQUELIZE)

data BackendFlowCommands next st rt s
    = Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)

    | GenerateGUID
        (Playback.RRItemDict Playback.GenerateGUIDEntry String)
        (String -> next)

    | CallAPI (Interaction (EitherEx ErrorResponse s))
        (Playback.RRItemDict Playback.CallAPIEntry (EitherEx ErrorResponse s))
        (APIResult s -> next)

    | DoAff (forall eff. BackendAff eff s) (s -> next)

    | DoAffRR (forall eff. BackendAff eff s)
        (Playback.RRItemDict Playback.DoAffEntry s)
        (s -> next)

    | Log String s
        (Playback.RRItemDict Playback.LogEntry UnitEx)
        (UnitEx -> next)

    | Fork (BackendFlow st rt s)
        String
        (Playback.RRItemDict Playback.ForkFlowEntry UnitEx)
        (UnitEx -> next)

    | RunSysCmd String
        (Playback.RRItemDict Playback.RunSysCmdEntry String)
        (String -> next)

    | ThrowException String

    | GetDBConn String
        (Playback.RRItemDict Playback.GetDBConnEntry SqlConn)
        (SqlConn -> next)

    | RunDB String
        (forall eff. Conn -> Aff (sequelize :: SEQUELIZE | eff) (EitherEx DBError s))
        (MockedSqlConn -> SqlDBMock.DBActionDict)
        (Playback.RRItemDict Playback.RunDBEntry (EitherEx DBError s))
        (EitherEx DBError s -> next)

    | GetKVDBConn String
      (Playback.RRItemDict Playback.GetKVDBConnEntry KVDBConn)
        (KVDBConn -> next)

    | RunKVDBEither String
        (KVDB.KVDB (EitherEx DBError s))
        (MockedKVDBConn -> KVDBMock.KVDBActionDict)
        (Playback.RRItemDict Playback.RunKVDBEitherEntry (EitherEx DBError s))
        (EitherEx DBError s -> next)

    | RunKVDBSimple String
        (KVDB.KVDB s)
        (MockedKVDBConn -> KVDBMock.KVDBActionDict)
        (Playback.RRItemDict Playback.RunKVDBSimpleEntry s)
        (s -> next)

    | GetOption  String
        (Playback.RRItemDict Playback.GetOptionEntry (MaybeEx String))
        (Maybe String -> next)

    | SetOption String String
        (Playback.RRItemDict Playback.SetOptionEntry UnitEx)
        (UnitEx -> next)

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

setOption' :: forall st rt. String -> String -> BackendFlow st rt Unit
setOption' key val = void $ wrap $
  SetOption key val
    (Playback.mkEntryDict
      ("setOption key: " <> key <> " value: " <> val)
      $ Playback.mkSetOptionEntry key val)
    id

setOption
  :: forall k v st rt
   . OptionEntity k v
   => Encode k
   => Encode v
   => k -> v -> BackendFlow st rt Unit
setOption k v = do
  let rawKey = encodeJSON k
  let rawVal = encodeJSON v
  setOption' rawKey rawVal

getOption' :: forall st rt. String -> BackendFlow st rt (Maybe String)
getOption' key = wrap $
  GetOption key
    (Playback.mkEntryDict
      ("getOption key: " <> key)
      $ Playback.mkGetOptionEntry key)
    id

getOption
  :: forall k v st rt
   . OptionEntity k v
   => Encode k
   => Decode v
   => k -> BackendFlow st rt (Maybe v)
getOption k = do
  let rawKey = encodeJSON k
  eRawVal <- getOption' rawKey
  case eRawVal of
    Nothing -> pure Nothing
    Just rawV -> case (runExcept $ decodeJSON rawV) of
      Left err -> pure Nothing
      Right val -> pure $ Just val

generateGUID' :: forall st rt. String -> BackendFlow st rt String
generateGUID' description = wrap $ GenerateGUID
    (Playback.mkEntryDict description $ Playback.mkGenerateGUIDEntry description)
    id

generateGUID :: forall st rt. BackendFlow st rt String
generateGUID = generateGUID' ""

callAPI
  :: forall st rt a b
   . Encode a
  => Encode b
  => Decode b
  => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt (APIResult b)
callAPI headers a = wrap $ CallAPI
  (apiInteract a headers)
  (Playback.mkEntryDict
    (encodeJSON $ makeRequest a headers)
    (Playback.mkCallAPIEntry (\_ -> encode $ makeRequest a headers)))
  id

doAff :: forall st rt a. (forall eff. BackendAff eff a) -> BackendFlow st rt a
doAff aff = wrap $ DoAff aff id

doAffRR'
  :: forall st rt a
   . Encode a
  => Decode a
  => String
  -> (forall eff. BackendAff eff a)
  -> BackendFlow st rt a
doAffRR' description aff = wrap $ DoAffRR aff (Playback.mkEntryDict ("doAffRR' " <> description) $ Playback.mkDoAffEntry description) id

doAffRR
  :: forall st rt a
   . Encode a
  => Decode a
  => (forall eff. BackendAff eff a)
  -> BackendFlow st rt a
doAffRR = doAffRR' ""

-- TODO: this is not a correct solution, jsonStringify is a strange function
-- that feels hacky.
log :: forall st rt a. String -> a -> BackendFlow st rt Unit
log tag message = void $ wrap $ Log tag message
    (Playback.mkEntryDict
      ("tag: " <> tag <> ", message: " <> jsonStringify message)
      $ Playback.mkLogEntry tag $ jsonStringify message)
    id

forkFlow' :: forall st rt a. String -> BackendFlow st rt a -> BackendFlow st rt Unit
forkFlow' description flow = do
  flowGUID <- generateGUID' description
  unless (null description) $ log "forkFlow" $ "Flow forked. Description: " <> description <> " GUID: " <> flowGUID
  when   (null description) $ log "forkFlow" $ "Flow forked. GUID: " <> flowGUID
  void $ wrap $ Fork flow flowGUID
    (Playback.mkEntryDict
      ("description: " <> description <> " GUID: " <> flowGUID)
      $ Playback.mkForkFlowEntry description flowGUID)
    id

forkFlow :: forall st rt a. BackendFlow st rt a -> BackendFlow st rt Unit
forkFlow = forkFlow' ""

runSysCmd :: forall st rt. String -> BackendFlow st rt String
runSysCmd cmd =
  wrap $ RunSysCmd cmd
    (Playback.mkEntryDict
      ("cmd: " <> cmd)
      $ Playback.mkRunSysCmdEntry cmd)
    id

throwException :: forall st rt a. String -> BackendFlow st rt a
throwException errorMessage = wrap $ ThrowException errorMessage

getDBConn :: forall st rt. String -> BackendFlow st rt SqlConn
getDBConn dbName = wrap $ GetDBConn dbName
  (Playback.mkEntryDict
    ("dbName: " <> dbName <> ", getDBConn")
    $ Playback.mkGetDBConnEntry dbName)
  id

findOne
  :: forall model st rt
   . Model model
  => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOne dbName options = do
  eResEx <- wrap $ RunDB dbName
    (\conn     -> toDBMaybeResult <$> DB.findOne conn options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkFindOne dbName)
    (Playback.mkEntryDict
      (dbName <> ", query: findOne, opts: " <> encodeJSON (Opt.options options) )
      $ Playback.mkRunDBEntry dbName "findOne" [Opt.options options] (encode ""))
    id
  pure $ fromDBMaybeResult eResEx

findAll
  :: forall model st rt
   . Model model
  => String -> Options model -> BackendFlow st rt (Either Error (Array model))
findAll dbName options = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toCustomEitherEx <$> DB.findAll conn options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkFindAll dbName)
    (Playback.mkEntryDict
      (dbName <> ", query: findAll, opts: " <> encodeJSON (Opt.options options) )
      $ Playback.mkRunDBEntry dbName "findAll" [Opt.options options] (encode ""))
    id
  pure $ fromCustomEitherEx eResEx

query
  :: forall r a st rt
   . Encode a
  => Decode a
  => Newtype a {|r}
  => String -> String -> BackendFlow st rt (Either Error (Array a))
query dbName rawq = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toCustomEitherEx <$> DB.query conn rawq)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkQuery dbName)
    (Playback.mkEntryDict
        (dbName <> ", rawq: " <> rawq)
        $ Playback.mkRunDBEntry dbName "query" [toForeign rawq] (encode ""))
    id
  pure $ fromCustomEitherEx eResEx

create :: forall model st rt. Model model => String -> model -> BackendFlow st rt (Either Error (Maybe model))
create dbName model = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toDBMaybeResult <$> DB.create conn model)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkCreate dbName)
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", create " <> encodeJSON model)
      $ Playback.mkRunDBEntry dbName "create" [] (encode model))
    id
  pure $ fromDBMaybeResult eResEx

createWithOpts :: forall model st rt. Model model => String -> model -> Options model -> BackendFlow st rt (Either Error (Maybe model))
createWithOpts dbName model options = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toDBMaybeResult <$> DB.createWithOpts conn model options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkCreateWithOpts dbName)
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", createWithOpts " <> encodeJSON model <> ", opts: " <> encodeJSON (Opt.options options))
      $ Playback.mkRunDBEntry dbName "createWithOpts" [Opt.options options] (encode model))
    id
  pure $ fromDBMaybeResult eResEx

update :: forall model st rt. Model model => String -> Options model -> Options model -> BackendFlow st rt (Either Error (Array model))
update dbName updateValues whereClause = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toCustomEitherEx <$> DB.update conn updateValues whereClause)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkUpdate dbName)
    (Playback.mkEntryDict
      (dbName <> ", update, updVals: " <> encodeJSON [(Opt.options updateValues),(Opt.options whereClause)])
      $ Playback.mkRunDBEntry dbName "update" [(Opt.options updateValues),(Opt.options whereClause)] (encode ""))
    id
  pure $ fromCustomEitherEx eResEx

update' :: forall model st rt. Model model => String -> Options model -> Options model -> BackendFlow st rt (Either Error Int)
update' dbName updateValues whereClause = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toCustomEitherEx <$> DB.update' conn updateValues whereClause)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkUpdate dbName)
    (Playback.mkEntryDict
      (dbName <> ", update', updVals: " <> encodeJSON [(Opt.options updateValues),(Opt.options whereClause)] )
      $ Playback.mkRunDBEntry dbName "update'" [(Opt.options updateValues),(Opt.options whereClause)] (encode ""))
    id
  pure $ fromCustomEitherEx eResEx

delete :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error Int)
delete dbName options = do
  eResEx <- wrap $ RunDB dbName
    (\conn -> toCustomEitherEx <$> DB.delete conn options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkDelete dbName)
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", delete, opts: " <> encodeJSON (Opt.options options))
      $ Playback.mkRunDBEntry dbName "delete" [Opt.options options] (encode ""))
    id
  pure $ fromCustomEitherEx eResEx

getKVDBConn :: forall st rt. String -> BackendFlow st rt KVDBConn
getKVDBConn dbName = wrap $ GetKVDBConn dbName
  (Playback.mkEntryDict
    ("dbName: " <> dbName <> ", getKVDBConn")
    $ Playback.mkGetKVDBConnEntry dbName)
  id

-- Not sure about this method.
-- Should we wrap Unit?
setCache :: forall st rt. String -> String ->  String -> BackendFlow st rt (Either Error Unit)
setCache dbName key value = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherExF toUnitEx <$> KVDB.setCache key value Nothing)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", setCache, key: " <> key <> ", value: " <> value)
        $ Playback.mkRunKVDBEitherEntry dbName "setCache" ("key: " <> key <> ", value: " <> value))
      id
  pure $ fromCustomEitherExF fromUnitEx eRes

-- Not sure about this method.
-- Should we wrap Unit?
setCacheWithExpiry :: forall st rt. String -> String -> String -> Milliseconds -> BackendFlow st rt (Either Error Unit)
setCacheWithExpiry dbName key value ttl = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherExF toUnitEx <$> KVDB.setCache key value (Just ttl))
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", setCacheWithExpiry, key: " <> key <> ", value: " <> value <> ", ttl: " <> show ttl)
        $ Playback.mkRunKVDBEitherEntry dbName "setCacheWithExpiry" ("key: " <> key <> ", value: " <> value <> ", ttl: " <> show ttl))
      id
  pure $ fromCustomEitherExF fromUnitEx eRes

getCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error (Maybe String))
getCache dbName key = do
  eRes <- wrap $ RunKVDBEither dbName
      (toDBMaybeResult <$> KVDB.getCache key)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", getCache, key: " <> key)
        $ Playback.mkRunKVDBEitherEntry dbName "getCache" ("key: " <> key))
      id
  pure $ fromDBMaybeResult eRes

keyExistsCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error Boolean)
keyExistsCache dbName key = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.keyExistsCache key)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", keyExistsCache, key: " <> key)
        $ Playback.mkRunKVDBEitherEntry dbName "keyExistsCache" ("key: " <> key))
      id
  pure $ fromCustomEitherEx eRes

delCache :: forall st rt. String -> String -> BackendFlow st rt (Either Error Int)
delCache dbName key = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.delCache key)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", delCache, key: " <> key)
        $ Playback.mkRunKVDBEitherEntry dbName "delCache" ("key: " <> key))
      id
  pure $ fromCustomEitherEx eRes

expire :: forall st rt. String -> String -> Seconds -> BackendFlow st rt (Either Error Boolean)
expire dbName key ttl = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.expire key ttl)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", delCache, key: " <> key <> ", ttl: " <> show ttl)
        $ Playback.mkRunKVDBEitherEntry dbName "expire" ("key: " <> key <> ", ttl: " <> show ttl))
      id
  pure $ fromCustomEitherEx eRes

incr :: forall st rt. String -> String -> BackendFlow st rt (Either Error Int)
incr dbName key = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.incr key)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", incr, key: " <> key)
        $ Playback.mkRunKVDBEitherEntry dbName "incr" ("key: " <> key))
      id
  pure $ fromCustomEitherEx eRes

setHash :: forall st rt. String -> String -> String -> String -> BackendFlow st rt (Either Error Boolean)
setHash dbName key field value = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.setHash key field value)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", setHash, key: " <> key <> ", field: " <> field <> ", value: " <> value)
        $ Playback.mkRunKVDBEitherEntry dbName "setHash" ("key: " <> key <> ", field: " <> field <> ", value: " <> value))
      id
  pure $ fromCustomEitherEx eRes

getHashKey :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error (Maybe String))
getHashKey dbName key field = do
  eRes <- wrap $ RunKVDBEither dbName
      (toDBMaybeResult <$> KVDB.getHashKey key field)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", getHashKey, key: " <> key <> ", field: " <> field)
        $ Playback.mkRunKVDBEitherEntry dbName "getHashKey" ("key: " <> key <> ", field: " <> field))
      id
  pure $ fromDBMaybeResult eRes

publishToChannel :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error Int)
publishToChannel dbName channel message = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.publishToChannel channel message)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", publishToChannel, channel: " <> channel <> ", message: " <> message)
        $ Playback.mkRunKVDBEitherEntry dbName "publishToChannel" ("channel: " <> channel <> ", message: " <> message))
      id
  pure $ fromCustomEitherEx eRes

-- Not sure about this method.
-- Should we wrap Unit?
subscribe :: forall st rt. String -> String -> BackendFlow st rt (Either Error Unit)
subscribe dbName channel = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherExF toUnitEx <$> KVDB.subscribe channel)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", subscribe, channel: " <> channel)
        $ Playback.mkRunKVDBEitherEntry dbName "subscribe" ("channel: " <> channel))
      id
  pure $ fromCustomEitherExF fromUnitEx eRes

-- Not sure about this method.
-- Should we wrap Unit?
enqueue :: forall st rt. String -> String -> String -> BackendFlow st rt (Either Error Unit)
enqueue dbName listName value = do
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherExF toUnitEx <$> KVDB.enqueue listName value)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", enqueue, listName: " <> listName <> ", value: " <> value)
        $ Playback.mkRunKVDBEitherEntry dbName "enqueue" ("listName: " <> listName <> ", value: " <> value))
      id
  pure $ fromCustomEitherExF fromUnitEx eRes

dequeue :: forall st rt. String -> String -> BackendFlow st rt (Either Error (Maybe String))
dequeue dbName listName = do
  eRes <- wrap $ RunKVDBEither dbName
      (toDBMaybeResult <$> KVDB.dequeue listName)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", dequeue, listName: " <> listName)
        $ Playback.mkRunKVDBEitherEntry dbName "dequeue" ("listName: " <> listName))
      id
  pure $ fromDBMaybeResult eRes

getQueueIdx :: forall st rt. String -> String -> Int -> BackendFlow st rt (Either Error (Maybe String))
getQueueIdx dbName listName index = do
  eRes <- wrap $ RunKVDBEither dbName
      (toDBMaybeResult <$> KVDB.getQueueIdx listName index)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", getQueueIdx, listName: " <> listName <> ", idx: " <> show index)
        $ Playback.mkRunKVDBEitherEntry dbName "getQueueIdx" ("listName: " <> listName <> ", idx: " <> show index))
      id
  pure $ fromDBMaybeResult eRes

-- Multi methods

newMulti :: forall st rt. String -> BackendFlow st rt Multi
newMulti dbName =
  wrap $ RunKVDBSimple dbName
    KVDB.newMulti
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", newMulti")
      $ Playback.mkRunKVDBSimpleEntry dbName "newMulti" "")
    id

setCacheInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
setCacheInMulti key value multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.setCacheInMulti key value Nothing multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", setCacheInMulti, key: " <> key <> ", value: " <> value <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "setCacheInMulti" ("key: " <> key <> ", value: " <> value <> ", multi: " <> show multi))
    id

-- Why this function returns Multi???
getCacheInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
getCacheInMulti key multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.getCacheInMulti key multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", getCacheInMulti, key: " <> key <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "getCacheInMulti" ("key: " <> key <> ", multi: " <> show multi))
    id

delCacheInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
delCacheInMulti key multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.delCacheInMulti key multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", delCacheInMulti, key: " <> key)
      $ Playback.mkRunKVDBSimpleEntry dbName "delCacheInMulti" ("key: " <> key))
    id

setCacheWithExpireInMulti :: forall st rt. String -> String -> Milliseconds -> Multi -> BackendFlow st rt Multi
setCacheWithExpireInMulti key value ttl multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.setCacheInMulti key value (Just ttl) multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", setCacheWithExpireInMulti, key: " <> key <> ", value: " <> value <> ", ttl: " <> show ttl <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "setCacheWithExpireInMulti" ("key: " <> key <> ", value: " <> value <> ", ttl: " <> show ttl <> ", multi: " <> show multi))
    id

expireInMulti :: forall st rt. String -> Seconds -> Multi -> BackendFlow st rt Multi
expireInMulti key ttl multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.expireInMulti key ttl multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", expireInMulti, key: " <> key <> ", ttl: " <> show ttl <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "expireInMulti" ("key: " <> key <> ", ttl: " <> show ttl <> ", multi: " <> show multi))
    id

incrInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
incrInMulti key multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.incrInMulti key multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", incrInMulti, key: " <> key <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "incrInMulti" ("key: " <> key <> ", multi: " <> show multi))
    id

setHashInMulti :: forall st rt. String -> String -> String -> Multi -> BackendFlow st rt Multi
setHashInMulti key field value multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.setHashInMulti key field value multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", setHashInMulti, key: " <> key <> ", field: " <> field <> ", value: " <> value <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "setHashInMulti" ("key: " <> key <> ", field: " <> field <> ", value: " <> value <> ", multi: " <> show multi))
    id

-- Why this function returns Multi???
getHashKeyInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
getHashKeyInMulti key field multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.getHashKeyInMulti key field multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", getHashKeyInMulti, key: " <> key <> ", field: " <> field <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "getHashKeyInMulti" ("key: " <> key <> ", field: " <> field <> ", multi: " <> show multi))
    id

publishToChannelInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
publishToChannelInMulti channel message multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.publishToChannelInMulti channel message multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", publishToChannelInMulti, channel: " <> channel <> ", message: " <> message <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "publishToChannelInMulti" ("channel: " <> channel <> ", message: " <> message <> ", multi: " <> show multi))
    id

enqueueInMulti :: forall st rt. String -> String -> Multi -> BackendFlow st rt Multi
enqueueInMulti listName value multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.enqueueInMulti listName value multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", enqueueInMulti, value: " <> value <> ", listName: " <> listName <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "enqueueInMulti" ("value: " <> value <> ", listName: " <> listName <> ", multi: " <> show multi))
    id

-- Why this function returns Multi???
dequeueInMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
dequeueInMulti listName multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.dequeueInMulti listName multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", dequeueInMulti, listName: " <> listName <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "dequeueInMulti" ("listName: " <> listName <> ", multi: " <> show multi))
    id

-- Why this function returns Multi???
getQueueIdxInMulti :: forall st rt. String -> Int -> Multi -> BackendFlow st rt Multi
getQueueIdxInMulti listName index multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.getQueueIdxInMulti listName index multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", getQueueIdxInMulti, listName: " <> listName <> ", index: " <> show index <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "getQueueIdxInMulti" ("listName: " <> listName <> ", index: " <> show index <> ", multi: " <> show multi))
    id

subscribeToMulti :: forall st rt. String -> Multi -> BackendFlow st rt Multi
subscribeToMulti channel multi = let
  dbName = KVDB.getKVDBName multi
  in wrap $ RunKVDBSimple dbName
    (KVDB.subscribeToMulti channel multi)
    KVDBMock.mkKVDBActionDict
    (Playback.mkEntryDict
      ("dbName: " <> dbName <> ", subscribeToMulti, channel: " <> channel <> ", multi: " <> show multi)
      $ Playback.mkRunKVDBSimpleEntry dbName "subscribeToMulti" ("channel: " <> channel <> ", multi: " <> show multi))
    id

execMulti :: forall st rt. Multi -> BackendFlow st rt (Either Error (Array Foreign))
execMulti multi = do
  let dbName = KVDB.getKVDBName multi
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.execMulti multi)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", execMulti, multi: " <> show multi)
        $ Playback.mkRunKVDBEitherEntry dbName "execMulti" ("multi: " <> show multi))
      id
  pure $ fromCustomEitherEx eRes

addInMulti :: forall st rt. String -> EntryID -> (Array Item) -> Multi -> BackendFlow st rt (Either Error Multi)
addInMulti key entryId args multi = do
  let dbName = KVDB.getKVDBName multi
  eRes <- wrap $ RunKVDBEither dbName
      (toCustomEitherEx <$> KVDB.addInMulti key entryId args multi)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", addInMulti, key: " <> key <> ", entryId: " <> show entryId <> ", multi: " <> show multi)
        $ Playback.mkRunKVDBEitherEntry dbName "addInMulti" ("key: " <> key <> ", entryId: " <> show entryId <> ", multi: " <> show multi))
      id
  pure $ fromCustomEitherEx eRes

setMessageHandler
  :: forall st rt
   . String
  -> (forall eff. (String -> String -> Eff eff Unit))
  -> BackendFlow st rt Unit
setMessageHandler dbName f = do
  void $ wrap $ RunKVDBSimple dbName
      (toUnitEx <$> KVDB.setMessageHandler f)
      KVDBMock.mkKVDBActionDict
      (Playback.mkEntryDict
        ("dbName: " <> dbName <> ", setMessageHandler")
        $ Playback.mkRunKVDBSimpleEntry dbName "setMessageHandler" "")
      id
