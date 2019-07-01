module Presto.Backend.Playback.Entries where

import Prelude

import Control.Monad.Except (runExcept) as E
import Data.Either (Either(..), note, hush, isLeft)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), isJust)
import Data.Tuple (Tuple(..))
import Data.Lazy (Lazy, force, defer)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Playback.Types
import Presto.Backend.APIInteract (ExtendedAPIResultEx (..), APIResultEx (..))



data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  }

data CallAPIEntry = CallAPIEntry
  { jsonRequest :: String
  , jsonResult  :: APIResultEx String
  }

data RunSysCmdEntry = RunSysCmdEntry
  { cmd :: String
  , result :: String
  }

data DoAffEntry = DoAffEntry
  { jsonResult :: String
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
  => ExtendedAPIResultEx b
  -> CallAPIEntry
mkCallAPIEntry (ExtendedAPIResultEx resultEx) = CallAPIEntry
  { jsonRequest : force resultEx.mkJsonRequest
  , jsonResult  : encodeJSON <$> resultEx.resultEx
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
  => MockedResult CallAPIEntry (ExtendedAPIResultEx b) where
    parseRRItem (CallAPIEntry ce) = do
      eResultEx <- case ce.jsonResult of
        APILeft  errResp -> Just $ APILeft errResp
        APIRight strResp -> do
            (resultEx :: b) <- hush $ E.runExcept $ decodeJSON strResp
            Just $ APIRight resultEx
      pure $ ExtendedAPIResultEx
        { mkJsonRequest: defer $ \_ -> ce.jsonRequest
        , resultEx: eResultEx
        }

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
