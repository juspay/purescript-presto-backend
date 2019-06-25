module Presto.Backend.Playback.Types where

import Prelude

import Control.Monad.Eff.Ref (Ref)
import Data.Array as Array
import Data.Maybe (Maybe)
import Data.Tuple (Tuple(..))
import Data.Generic.Rep (class Generic)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Type.Proxy (Proxy)

data RecordingEntry = RecordingEntry String

-- TODO: it might be Data.Sequence.Ordered is better
type Recording =
  { entries :: Array RecordingEntry
  }

-- N.B. Async and parallel computations are not properly supported.
-- For now, Ref is used, but it's not thread safe.
-- So having a sequential flow is preferred.
type RecorderRuntime =
  { recordingRef :: Ref Recording
  }

type PlayerRuntime =
  { recording :: Recording
  , stepRef   :: Ref Int
  }

data PlaybackErrorType
  = UnexpectedRecordingEnd
  | UnknownRRItem
  | MockDecodingFailed

newtype PlaybackError = PlaybackError
  { errorType :: PlaybackErrorType
  , errorMessage :: String
  }

class (Eq rrItem, Decode rrItem, Encode rrItem) <= RRItem rrItem where
  toRecordingEntry   :: rrItem -> RecordingEntry
  fromRecordingEntry :: RecordingEntry -> Maybe rrItem
  getTag             :: Proxy rrItem -> String
  isMocked           :: Proxy rrItem -> Boolean

-- Class for conversions of RRItem and native results.
-- Native result can be unencodable completely.
-- TODO: error handling
class (RRItem rrItem) <= MockedResult rrItem native | rrItem -> native where
  parseRRItem :: rrItem -> Maybe native

data UnitP = UnitP

derive instance genericRecordingEntry :: Generic RecordingEntry _
instance decodeRecordingEntry :: Decode RecordingEntry where
  decode = defaultDecode
instance encodeRecordingEntry :: Encode RecordingEntry where
  encode = defaultEncode

derive instance genericUnitP :: Generic UnitP _
instance decodeUnitP :: Decode UnitP where
  decode = defaultDecode
instance encodeUnitP :: Encode UnitP where
  encode = defaultEncode

-- Classless types

newtype RRItemDict rrItem native = RRItemDict
  { toRecordingEntry   :: rrItem -> RecordingEntry
  , fromRecordingEntry :: RecordingEntry -> Maybe rrItem
  , getTag             :: Proxy rrItem -> String
  , isMocked           :: Proxy rrItem -> Boolean
  , parseRRItem        :: rrItem -> Maybe native
  , mkEntry            :: native -> rrItem
  , compare            :: rrItem -> rrItem -> Boolean
  }

toRecordingEntry' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> RecordingEntry
toRecordingEntry' (RRItemDict d) = d.toRecordingEntry

fromRecordingEntry' :: forall rrItem native. RRItemDict rrItem native -> RecordingEntry -> Maybe rrItem
fromRecordingEntry' (RRItemDict d) = d.fromRecordingEntry

getTag' :: forall rrItem native. RRItemDict rrItem native -> Proxy rrItem -> String
getTag' (RRItemDict d) = d.getTag

isMocked' :: forall rrItem native. RRItemDict rrItem native -> Proxy rrItem -> Boolean
isMocked' (RRItemDict d) = d.isMocked

parseRRItem' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> Maybe native
parseRRItem' (RRItemDict d) = d.parseRRItem

mkEntry' :: forall rrItem native. RRItemDict rrItem native -> native -> rrItem
mkEntry' (RRItemDict d) = d.mkEntry

compare' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> rrItem -> Boolean
compare' (RRItemDict d) = d.compare
