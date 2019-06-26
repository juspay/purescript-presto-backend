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
import Presto.Core.Types.API (ErrorResponse)
import Presto.Core.Types.Language.Flow (APIResult)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Playback.Types
import Presto.Backend.APIInteractEx (ExtendedAPIResultEx (..), APIResultEx (..))

import Presto.Core.Language.Runtime.API as API
import Presto.Core.Types.Language.Interaction as API


data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  }

data CallAPIEntry = CallAPIEntry
  { jsonRequest :: String
  , jsonResult  :: APIResultEx String
  }


mkLogEntry :: String -> String -> Unit -> LogEntry
mkLogEntry t m _ = LogEntry {tag: t, message: m}

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