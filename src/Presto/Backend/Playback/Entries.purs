module Presto.Backend.Playback.Entries where

import Prelude

import Control.Monad.Except (runExcept) as E
import Data.Either (Either(..), note, hush, isLeft)
import Data.Foreign (Foreign)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), isJust)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple(..))
import Data.Lazy (Lazy, force, defer)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (APIResult(..), ErrorPayload, ErrorResponse, Response)
import Presto.Backend.Language.Types.EitherEx (EitherEx(..))
import Presto.Backend.Language.Types.DB
import Presto.Backend.Language.Types.KVDB (Multi)
import Presto.Backend.Playback.Types


data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  }

data CallAPIEntry = CallAPIEntry
  { jsonRequest :: Foreign
  , jsonResult  :: EitherEx ErrorResponse Foreign
  }

data RunSysCmdEntry = RunSysCmdEntry
  { cmd :: String
  , result :: String
  }

data DoAffEntry = DoAffEntry
  { jsonResult :: Foreign
  }

data RunDBEntry = RunDBEntry
  { dbName     :: String
  , dbMethod   :: String
  , jsonResult :: EitherEx DBError Foreign
  , options :: Array Foreign
  , model :: Foreign
  }

data GetDBConnEntry = GetDBConnEntry
  { dbName     :: String
  , mockedConn :: MockedSqlConn
  }

data GetKVDBConnEntry = GetKVDBConnEntry
  { dbName     :: String
  , mockedConn :: MockedKVDBConn
  }

data RunKVDBEntryEither = RunKVDBEntryEither
  { dbName     :: String
  , dbMethod   :: String
  , params     :: String
  , jsonResult :: EitherEx DBError String
  }

data RunKVDBSimpleEntry = RunKVDBSimpleEntry
  { dbName     :: String
  , dbMethod   :: String
  , params     :: String
  , jsonResult :: String
  }

mkRunSysCmdEntry :: String -> String -> RunSysCmdEntry
mkRunSysCmdEntry cmd result = RunSysCmdEntry { cmd, result }

mkLogEntry :: String -> String -> Unit -> LogEntry
mkLogEntry t m _ = LogEntry {tag: t, message: m}

mkDoAffEntry
  :: forall b
   . Encode b
  => Decode b
  => b -> DoAffEntry
mkDoAffEntry result = DoAffEntry { jsonResult: encode result }

mkCallAPIEntry
  :: forall b
   . Encode b
  => Decode b
  => Lazy Foreign
  -> EitherEx ErrorResponse  b
  -> CallAPIEntry
mkCallAPIEntry jReq aRes = CallAPIEntry
  { jsonRequest : force jReq
  , jsonResult  : encode <$> aRes
  }

mkRunKVDBEntryEither
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> Array Foreign
  -> Foreign
  -> EitherEx DBError b
  -> RunKVDBEntryEither
mkRunKVDBEntryEither dbName dbMethod params aRes = RunKVDBEntryEither
  { dbName
  , dbMethod
  , jsonResult : encode <$> aRes
  , options : options
  , model : model
  }

mkRunKVDBSimpleEntry
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> String
  -> b
  -> RunKVDBSimpleEntry
mkRunKVDBSimpleEntry dbName dbMethod params aRes = RunKVDBSimpleEntry
  { dbName
  , dbMethod
  , params
  , jsonResult : encodeJSON aRes
  }

mkGetDBConnEntry :: String -> SqlConn -> GetDBConnEntry
mkGetDBConnEntry dbName (Sequelize _)          = GetDBConnEntry { dbName, mockedConn : MockedSqlConn dbName }
mkGetDBConnEntry dbName (MockedSql mockedConn) = GetDBConnEntry { dbName, mockedConn }

mkGetKVDBConnEntry :: String -> KVDBConn -> GetKVDBConnEntry
mkGetKVDBConnEntry dbName (Redis _)               = GetKVDBConnEntry { dbName, mockedConn : MockedKVDBConn dbName }
mkGetKVDBConnEntry dbName (MockedKVDB mockedConn) = GetKVDBConnEntry { dbName, mockedConn }

mkRunDBEntry
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> Array Foreign
  -> String
  -> EitherEx DBError b
  -> RunDBEntry
mkRunDBEntry dbName dbMethod options model aRes = RunDBEntry
  { dbName
  , dbMethod
  , jsonResult : encodeJSON <$> aRes
  , options : encodeJSON options
  , model : model
  }
derive instance genericLogEntry :: Generic LogEntry _
derive instance eqLogEntry :: Eq LogEntry

instance decodeLogEntry :: Decode LogEntry where decode = defaultDecode
instance encodeLogEntry :: Encode LogEntry where encode = defaultEncode

instance rrItemLogEntry :: RRItem LogEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "LogEntry"
  isMocked _ = true

instance mockedResultLogEntry :: MockedResult LogEntry Unit where
  parseRRItem _ = Just unit


derive instance genericCallAPIEntry :: Generic CallAPIEntry _
instance eqCallAPIEntry :: Eq CallAPIEntry where
  eq e1 e2 = (encodeJSON e1) == (encodeJSON e2)

instance decodeCallAPIEntry :: Decode CallAPIEntry where decode = defaultDecode
instance encodeCallAPIEntry :: Encode CallAPIEntry where encode = defaultEncode

instance rrItemCallAPIEntry :: RRItem CallAPIEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "CallAPIEntry"
  isMocked _ = true

instance mockedResultCallAPIEntry
  :: Decode b
  => MockedResult CallAPIEntry (EitherEx (Response ErrorPayload) b) where
    parseRRItem (CallAPIEntry ce) = do
      eResult <- case ce.jsonResult of
        LeftEx  errResp -> Just $ LeftEx errResp
        RightEx strResp -> do
            (resultEx :: b) <- hush $ E.runExcept $ decode strResp
            Just $ RightEx resultEx
      pure  eResult

derive instance genericRunSysCmdEntry :: Generic RunSysCmdEntry _
derive instance eqRunSysCmdEntry :: Eq RunSysCmdEntry

instance decodeRunSysCmdEntry :: Decode RunSysCmdEntry where decode = defaultDecode
instance encodeRunSysCmdEntry :: Encode RunSysCmdEntry where encode = defaultEncode

instance rrItemRunSysCmdEntry :: RRItem RunSysCmdEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunSysCmdEntry"
  isMocked _ = true

instance mockedResultRunSysCmdEntry :: MockedResult RunSysCmdEntry String where
  parseRRItem (RunSysCmdEntry e) = Just e.result


derive instance genericDoAffEntry :: Generic DoAffEntry _
instance eqDoAffEntry :: Eq DoAffEntry where
  eq e1 e2 = (encodeJSON e1) == (encodeJSON e2)

instance decodeDoAffEntry :: Decode DoAffEntry where decode = defaultDecode
instance encodeDoAffEntry :: Encode DoAffEntry where encode = defaultEncode

instance rrItemDoAffEntry :: RRItem DoAffEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "DoAffEntry"
  isMocked _ = true

instance mockedResultDoAffEntry :: Decode b => MockedResult DoAffEntry b where
  parseRRItem (DoAffEntry r) = hush $ E.runExcept $ decode r.jsonResult



derive instance genericRunDBEntry :: Generic RunDBEntry _
instance eqRunDBEntry :: Eq RunDBEntry where
  eq e1 e2 = (encodeJSON e1) == (encodeJSON e2)
instance decodeRunDBEntry :: Decode RunDBEntry where decode = defaultDecode
instance encodeRunDBEntry :: Encode RunDBEntry where encode = defaultEncode
instance rrItemRunDBEntry :: RRItem RunDBEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunDBEntry"
  isMocked _ = true

instance mockedResultRunDBEntry
  :: Decode b => MockedResult RunDBEntry (EitherEx DBError b) where
    parseRRItem (RunDBEntry dbe) = do
      eResult <- case dbe.jsonResult of
        LeftEx  errResp -> Just $ LeftEx errResp
        RightEx strResp -> do
            (resultEx :: b) <- hush $ E.runExcept $ decode strResp
            Just $ RightEx resultEx
      pure eResult


derive instance genericGetDBConnEntry :: Generic GetDBConnEntry _
derive instance eqGetDBConnEntry :: Eq GetDBConnEntry
instance decodeGetDBConnEntry :: Decode GetDBConnEntry where decode = defaultDecode
instance encodeGetDBConnEntry :: Encode GetDBConnEntry where encode = defaultEncode
instance rrItemGetDBConnEntry :: RRItem GetDBConnEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetDBConnEntry"
  isMocked _ = true

instance mockedResultGetDBConnEntry :: MockedResult GetDBConnEntry SqlConn where
  parseRRItem (GetDBConnEntry entry) = Just $ MockedSql entry.mockedConn


derive instance genericGetKVDBConnEntry :: Generic GetKVDBConnEntry _
derive instance eqGetKVDBConnEntry :: Eq GetKVDBConnEntry
instance decodeGetKVDBConnEntry :: Decode GetKVDBConnEntry where decode = defaultDecode
instance encodeGetKVDBConnEntry :: Encode GetKVDBConnEntry where encode = defaultEncode
instance rrItemGetKVDBConnEntry :: RRItem GetKVDBConnEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetKVDBConnEntry"
  isMocked _ = true

instance mockedResultGetKVDBConnEntry :: MockedResult GetKVDBConnEntry KVDBConn where
  parseRRItem (GetKVDBConnEntry entry) = Just $ MockedKVDB entry.mockedConn





derive instance genericRunKVDBEntryEither :: Generic RunKVDBEntryEither _
derive instance eqRunKVDBEntryEither :: Eq RunKVDBEntryEither
instance decodeRunKVDBEntryEither :: Decode RunKVDBEntryEither where decode = defaultDecode
instance encodeRunKVDBEntryEither :: Encode RunKVDBEntryEither where encode = defaultEncode
instance rrItemRunKVDBEntryEither :: RRItem RunKVDBEntryEither where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBEntryEither"
  isMocked _ = true

instance mockedResultRunKVDBEntryEither
  :: Decode b => MockedResult RunKVDBEntryEither (EitherEx DBError b) where
    parseRRItem (RunKVDBEntryEither dbe) = do
      eResult <- case dbe.jsonResult of
        LeftEx  errResp -> Just $ LeftEx errResp
        RightEx strResp -> do
            (resultEx :: b) <- hush $ E.runExcept $ decodeJSON strResp
            Just $ RightEx resultEx
      pure eResult


derive instance genericRunKVDBSimpleEntry :: Generic RunKVDBSimpleEntry _
derive instance eqRunKVDBSimpleEntry      :: Eq RunKVDBSimpleEntry
instance decodeRunKVDBSimpleEntry         :: Decode RunKVDBSimpleEntry where decode = defaultDecode
instance encodeRunKVDBSimpleEntry         :: Encode RunKVDBSimpleEntry where encode = defaultEncode
instance rrItemRunKVDBSimpleEntry         :: RRItem RunKVDBSimpleEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBSimpleEntry"
  isMocked _ = true

instance mockedResultRunKVDBSimpleEntry :: Decode b => MockedResult RunKVDBSimpleEntry b where
    parseRRItem (RunKVDBSimpleEntry r) = hush $ E.runExcept $ decodeJSON r.jsonResult
