module Presto.Backend.Playback.Entries where

import Prelude
import Presto.Backend.Playback.Types

import Control.Monad.Except (runExcept) as E
import Data.Either (Either(..), note, hush, isLeft)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Generic.Rep (class Generic)
import Data.Lazy (Lazy, force, defer)
import Data.Maybe (Maybe(..), isJust)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple(..))
import Presto.Backend.DB.Types (DBError)
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (APIResult(..), ErrorPayload, ErrorResponse, Response)
import Presto.Backend.Types.EitherEx (EitherEx(..))
import Presto.Core.Utils.Encoding (defaultDecode, defaultEncode, defaultEnumDecode, defaultEnumEncode)


data Mode = Normal | NoVerify | NoMock | Skip 
derive instance modeEq :: Eq Mode 
derive instance genericMode :: Generic Mode _
instance modeEncode :: Encode Mode where encode = defaultEnumEncode 
instance modeDecode :: Decode Mode where decode = defaultEnumDecode


data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  -- , mode :: Mode 
  }

data CallAPIEntry = CallAPIEntry
  { jsonRequest :: String
  , jsonResult  :: EitherEx ErrorResponse String
  , mode :: Mode 
  }

data RunSysCmdEntry = RunSysCmdEntry
  { cmd :: String
  , result :: String
  -- , mode :: Mode 
  }

data DoAffEntry = DoAffEntry
  { jsonResult :: String
  -- , mode :: Mode 
  }

data RunDBEntry = RunDBEntry
  { dbName     :: String
  , dbMethod   :: String
  , jsonResult :: EitherEx DBError String
  -- , mode :: Mode 
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
mkDoAffEntry result = DoAffEntry { jsonResult: encodeJSON result }

mkCallAPIEntry
  :: forall b
   . Encode b
  => Decode b
  => Lazy String
  -> EitherEx ErrorResponse  b
  -> CallAPIEntry
mkCallAPIEntry jReq aRes = CallAPIEntry
  { jsonRequest : force jReq
  , jsonResult  : encodeJSON <$> aRes
  , mode : Normal
  }

mkRunDBEntry
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> EitherEx DBError b
  -> RunDBEntry
mkRunDBEntry dbName dbMethod aRes = RunDBEntry
  { dbName
  , dbMethod
  , jsonResult : encodeJSON <$> aRes
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
derive instance eqCallAPIEntry :: Eq CallAPIEntry


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
            (resultEx :: b) <- hush $ E.runExcept $ decodeJSON strResp
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
derive instance eqDoAffEntry :: Eq DoAffEntry

instance decodeDoAffEntry :: Decode DoAffEntry where decode = defaultDecode
instance encodeDoAffEntry :: Encode DoAffEntry where encode = defaultEncode

instance rrItemDoAffEntry :: RRItem DoAffEntry where
  toRecordingEntry = RecordingEntry <<< encodeJSON
  fromRecordingEntry (RecordingEntry re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "DoAffEntry"
  isMocked _ = true

instance mockedResultDoAffEntry :: Decode b => MockedResult DoAffEntry b where
  parseRRItem (DoAffEntry r) = hush $ E.runExcept $ decodeJSON r.jsonResult



derive instance genericRunDBEntry :: Generic RunDBEntry _
derive instance eqRunDBEntry :: Eq RunDBEntry
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
            (resultEx :: b) <- hush $ E.runExcept $ decodeJSON strResp
            Just $ RightEx resultEx
      pure eResult
