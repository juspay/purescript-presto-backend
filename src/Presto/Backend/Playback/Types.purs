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

module Presto.Backend.Playback.Types where

import Prelude

import Control.Monad.Aff.AVar (AVar)
import Data.Maybe (Maybe)
import Data.StrMap as StrMap
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Bounded as GBounded
import Data.Generic.Rep.Enum as GEnum
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Ord as GOrd
import Data.Generic.Rep.Show as GShow
import Data.Newtype (class Newtype)
import Data.Enum (class Enum)
import Data.Foreign.Generic (encodeJSON)
import Data.Foreign.Class (class Decode, class Encode)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Type.Proxy (Proxy(..))

type EntryName = String

data RecordingEntry = RecordingEntry Int EntryReplayingMode EntryName String
data GlobalReplayingMode = GlobalNormal | GlobalNoVerify | GlobalNoMocking | GlobalSkip
data EntryReplayingMode = Normal | NoVerify | NoMock -- | Skip

derive instance eqEntryReplayingMode :: Eq EntryReplayingMode
derive instance genericEntryReplayingMode :: Generic EntryReplayingMode _
instance encodeEntryReplayingMode :: Encode EntryReplayingMode where encode = defaultEncode
instance decodeEntryReplayingMode :: Decode EntryReplayingMode where decode = defaultDecode
instance showEntryReplayingMode :: Show EntryReplayingMode where show = GShow.genericShow
instance ordEntryReplayingMode :: Ord EntryReplayingMode where compare = GOrd.genericCompare


type DisableEntries = String

type RecordingEntries = Array RecordingEntry
newtype Recording = Recording RecordingEntries

type RecorderRuntime =
  { flowGUID            :: String
  , recordingVar        :: AVar RecordingEntries
  , forkedRecordingsVar :: AVar (StrMap.StrMap (AVar RecordingEntries))
  , disableEntries      :: Array DisableEntries
  }

type PlayerRuntime =
  { flowGUID               :: String
  , recording              :: RecordingEntries
  , stepVar                :: AVar Int
  , errorVar               :: AVar (Maybe PlaybackError)
  , forkedFlowRecordings   :: StrMap.StrMap RecordingEntries
  , forkedFlowErrorsVar    :: AVar (StrMap.StrMap PlaybackError)
  , disableVerify          :: Array DisableEntries
  , disableMocking         :: Array DisableEntries
  , skipEntries            :: Array DisableEntries
  , entriesFiltered        :: Boolean
  }

data PlaybackErrorType
  = UnexpectedRecordingEnd
  | UnknownRRItem
  | MockDecodingFailed
  | ItemMismatch
  | UnknownPlaybackError
  | ForkedFlowRecordingsMissed

newtype PlaybackError = PlaybackError
  { errorType :: PlaybackErrorType
  , errorMessage :: String
  }


class (Eq rrItem, Decode rrItem, Encode rrItem) <= RRItem rrItem where
  toRecordingEntry   :: rrItem -> Int -> EntryReplayingMode -> RecordingEntry
  fromRecordingEntry :: RecordingEntry -> Maybe rrItem
  getTag             :: Proxy rrItem -> String

-- Class for conversions of RRItem and native results.
-- Native result can be unencodable completely.
-- TODO: error handling
class (RRItem rrItem) <= MockedResult rrItem native | rrItem -> native where
  parseRRItem :: rrItem -> Maybe native


derive instance eqRecording :: Eq Recording
derive instance genericRecording :: Generic Recording _
instance encodeRecording :: Encode Recording where encode = defaultEncode
instance decodeRecording :: Decode Recording where decode = defaultDecode
instance showRecording :: Show Recording where show = GShow.genericShow
instance ordRecording :: Ord Recording where compare = GOrd.genericCompare

derive instance genericRecordingEntry :: Generic RecordingEntry _
instance decodeRecordingEntry         :: Decode  RecordingEntry where decode = defaultDecode
instance encodeRecordingEntry         :: Encode  RecordingEntry where encode = defaultEncode
instance eqRecordingEntry             :: Eq      RecordingEntry where eq = GEq.genericEq
instance showRecordingEntry           :: Show    RecordingEntry where show = GShow.genericShow
instance ordRecordingEntry            :: Ord     RecordingEntry where compare = GOrd.genericCompare

derive instance genericPlaybackErrorType :: Generic PlaybackErrorType _
instance decodePlaybackErrorType         :: Decode  PlaybackErrorType where decode = defaultDecode
instance encodePlaybackErrorType         :: Encode  PlaybackErrorType where encode = defaultEncode
instance eqPlaybackErrorType             :: Eq      PlaybackErrorType where eq = GEq.genericEq
instance showPlaybackErrorType           :: Show    PlaybackErrorType where show = GShow.genericShow
instance ordPlaybackErrorType            :: Ord     PlaybackErrorType where compare = GOrd.genericCompare
instance enumPlaybackErrorType           :: Enum    PlaybackErrorType where
  succ = GEnum.genericSucc
  pred = GEnum.genericPred
instance boundedPlaybackErrorType        :: Bounded PlaybackErrorType where
  top = GBounded.genericTop
  bottom = GBounded.genericBottom

derive instance genericPlaybackError :: Generic PlaybackError _
derive instance newtypeConfig        :: Newtype PlaybackError _
instance decodePlaybackError         :: Decode  PlaybackError where decode = defaultDecode
instance encodePlaybackError         :: Encode  PlaybackError where encode = defaultEncode
instance eqPlaybackError             :: Eq      PlaybackError where eq = GEq.genericEq
instance showPlaybackError           :: Show    PlaybackError where show = GShow.genericShow
instance ordPlaybackError            :: Ord     PlaybackError where compare = GOrd.genericCompare

-- Classless types
newtype RRItemDict rrItem native = RRItemDict
  { toRecordingEntry   :: rrItem -> Int -> EntryReplayingMode -> RecordingEntry
  , fromRecordingEntry :: RecordingEntry -> Maybe rrItem
  , getInfo            :: String
  , getTag             :: String
  , parseRRItem        :: rrItem -> Maybe native
  , mkEntry            :: native -> rrItem
  , compare            :: rrItem -> rrItem -> Boolean
  , encodeJSON         :: rrItem -> String
  }



toRecordingEntry'
  :: forall rrItem native
   . RRItemDict rrItem native
  -> rrItem
  -> Int
  -> EntryReplayingMode
  -> RecordingEntry
toRecordingEntry' (RRItemDict d) = d.toRecordingEntry

fromRecordingEntry' :: forall rrItem native. RRItemDict rrItem native -> RecordingEntry -> Maybe rrItem
fromRecordingEntry' (RRItemDict d) = d.fromRecordingEntry

getInfo' :: forall rrItem native. RRItemDict rrItem native -> String
getInfo' (RRItemDict d) = d.getInfo

getTag' :: forall rrItem native. RRItemDict rrItem native -> String
getTag' (RRItemDict d) = d.getTag

parseRRItem' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> Maybe native
parseRRItem' (RRItemDict d) = d.parseRRItem

mkEntry' :: forall rrItem native. RRItemDict rrItem native -> native -> rrItem
mkEntry' (RRItemDict d) = d.mkEntry

compare' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> rrItem -> Boolean
compare' (RRItemDict d) = d.compare

encodeJSON' :: forall rrItem native. RRItemDict rrItem native -> rrItem -> String
encodeJSON' (RRItemDict d) = d.encodeJSON


mkEntryDict
  :: forall rrItem native
   . RRItem rrItem
  => MockedResult rrItem native
  => String
  -> (native -> rrItem)
  -> RRItemDict rrItem native
mkEntryDict mkInfo mkEntry = RRItemDict
  { toRecordingEntry   : toRecordingEntry
  , fromRecordingEntry : fromRecordingEntry
  , getInfo            : mkInfo
  , getTag             : getTag (Proxy :: Proxy rrItem)
  , parseRRItem        : parseRRItem
  , mkEntry            : mkEntry
  , compare            : (==)
  , encodeJSON         : encodeJSON
  }
