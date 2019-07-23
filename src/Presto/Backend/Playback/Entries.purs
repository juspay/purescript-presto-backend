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

module Presto.Backend.Playback.Entries where

import Prelude
import Presto.Backend.Playback.Types
import Data.Either (Either(..), note, hush, isLeft)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Foreign (Foreign)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Generic.Types (Options, SumEncoding(..))
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), isJust)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple(..))
import Presto.Backend.Runtime.Common (jsonStringify)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (APIResult(..), ErrorPayload, ErrorResponse, Response)
import Presto.Core.Utils.Encoding (defaultDecode, defaultEncode, defaultEnumDecode, defaultEnumEncode)
import Prelude (class Eq, bind, pure, ($), (<$>), (<<<), (==))

import Control.Monad.Except (runExcept) as E
import Presto.Backend.Language.Types.EitherEx (EitherEx(..))
import Presto.Backend.Language.Types.UnitEx (UnitEx(..))
import Presto.Backend.Language.Types.DB (DBError, KVDBConn(MockedKVDB, Redis), MockedKVDBConn(MockedKVDBConn), MockedSqlConn(MockedSqlConn), SqlConn(MockedSql, Sequelize))



data LogEntry = LogEntry
  { tag     :: String
  , message :: String
  }

data CallAPIEntry = CallAPIEntry
  { jsonRequest :: Foreign
  , jsonResult  :: EitherEx ErrorResponse Foreign
  }

data ForkFlowEntry = ForkFlowEntry
  { description :: String
  }

data ThrowExceptionEntry = ThrowExceptionEntry
  { errorMessage :: String
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
  , options    :: Array Foreign
  , model      :: Foreign
  , jsonResult :: EitherEx DBError Foreign
  }

data GetDBConnEntry = GetDBConnEntry
  { dbName     :: String
  , mockedConn :: MockedSqlConn
  }

data GetKVDBConnEntry = GetKVDBConnEntry
  { dbName     :: String
  , mockedConn :: MockedKVDBConn
  }

data RunKVDBEitherEntry = RunKVDBEitherEntry
  { dbName     :: String
  , dbMethod   :: String
  , params     :: String
  , jsonResult :: EitherEx DBError Foreign
  }

data RunKVDBSimpleEntry = RunKVDBSimpleEntry
  { dbName     :: String
  , dbMethod   :: String
  , params     :: String
  , jsonResult :: Foreign
  }

mkRunSysCmdEntry :: String -> String -> RunSysCmdEntry
mkRunSysCmdEntry cmd result = RunSysCmdEntry { cmd, result }

mkLogEntry :: String -> String -> UnitEx -> LogEntry
mkLogEntry tag message _ = LogEntry { tag, message }

mkThrowExceptionEntry :: String -> UnitEx -> ThrowExceptionEntry
mkThrowExceptionEntry errorMessage _ = ThrowExceptionEntry { errorMessage }

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
  => (Unit -> Foreign)
  -> EitherEx ErrorResponse b
  -> CallAPIEntry
mkCallAPIEntry jReqF aRes = CallAPIEntry
  { jsonRequest : jReqF unit
  , jsonResult  : encode <$> aRes
  }

mkForkFlowEntry :: String -> UnitEx -> ForkFlowEntry
mkForkFlowEntry description _ = ForkFlowEntry { description }

mkRunDBEntry
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> Array Foreign
  -> Foreign
  -> EitherEx DBError b
  -> RunDBEntry
mkRunDBEntry dbName dbMethod options model aRes = RunDBEntry
  { dbName
  , dbMethod
  , options
  , model
  , jsonResult : encode <$> aRes
  }

mkRunKVDBEitherEntry
  :: forall b
   . Encode b
  => Decode b
  => String
  -> String
  -> String
  -> EitherEx DBError b
  -> RunKVDBEitherEntry
mkRunKVDBEitherEntry dbName dbMethod params aRes = RunKVDBEitherEntry
  { dbName
  , dbMethod
  , params
  , jsonResult : encode <$> aRes
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
  , jsonResult : encode aRes
  }

mkGetDBConnEntry :: String -> SqlConn -> GetDBConnEntry
mkGetDBConnEntry dbName (Sequelize _)          = GetDBConnEntry { dbName, mockedConn : MockedSqlConn dbName }
mkGetDBConnEntry dbName (MockedSql mockedConn) = GetDBConnEntry { dbName, mockedConn }

mkGetKVDBConnEntry :: String -> KVDBConn -> GetKVDBConnEntry
mkGetKVDBConnEntry dbName (Redis _)               = GetKVDBConnEntry { dbName, mockedConn : MockedKVDBConn dbName }
mkGetKVDBConnEntry dbName (MockedKVDB mockedConn) = GetKVDBConnEntry { dbName, mockedConn }

deoptions1 :: Options
deoptions1 = defaultOptions { unwrapSingleConstructors = false
                           , unwrapSingleArguments = true }

deoptions2 :: Options
deoptions2 = defaultOptions { unwrapSingleConstructors = false
                           , unwrapSingleArguments = false }


derive instance genericLogEntry :: Generic LogEntry _
derive instance eqLogEntry :: Eq LogEntry
instance showLogEntry  :: Show LogEntry where show = GShow.genericShow
instance decodeLogEntry :: Decode LogEntry where decode = genericDecode deoptions1 --defaultDecode
instance encodeLogEntry :: Encode LogEntry where encode = genericEncode deoptions1 --defaultEncode

instance rrItemLogEntry :: RRItem LogEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "LogEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "LogEntry"


instance mockedResultLogEntry :: MockedResult LogEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericForkFlowEntry :: Generic ForkFlowEntry _
derive instance eqForkFlowEntry :: Eq ForkFlowEntry
instance decodeForkFlowEntry :: Decode ForkFlowEntry where decode = defaultDecode
instance encodeForkFlowEntry :: Encode ForkFlowEntry where encode = defaultEncode
instance showForkFlowEntry  :: Show ForkFlowEntry where show = GShow.genericShow

instance rrItemForkFlowEntry :: RRItem ForkFlowEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "ForkFlowEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "ForkFlowEntry"

instance mockedResultForkFlowEntry :: MockedResult ForkFlowEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericThrowExceptionEntry :: Generic ThrowExceptionEntry _
derive instance eqThrowExceptionEntry :: Eq ThrowExceptionEntry
instance showThrowExceptionEntry  :: Show ThrowExceptionEntry where show = GShow.genericShow
instance decodeThrowExceptionEntry :: Decode ThrowExceptionEntry where decode = defaultDecode
instance encodeThrowExceptionEntry :: Encode ThrowExceptionEntry where encode = defaultEncode

instance rrItemThrowExceptionEntry :: RRItem ThrowExceptionEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "ThrowExceptionEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "ThrowExceptionEntry"

instance mockedResultThrowExceptionEntry :: MockedResult ThrowExceptionEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericCallAPIEntry :: Generic CallAPIEntry _
instance eqCallAPIEntry :: Eq CallAPIEntry where
  eq e1 e2 = encodeJSON e1 == encodeJSON e2
instance decodeCallAPIEntry :: Decode CallAPIEntry where decode = defaultDecode
instance encodeCallAPIEntry :: Encode CallAPIEntry where encode = defaultEncode
instance showCallAPIEntry  :: Show CallAPIEntry where show = encodeJSON
instance rrItemCallAPIEntry :: RRItem CallAPIEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "CallAPIEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "CallAPIEntry"

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
instance showRunSysCmdEntry   :: Show RunSysCmdEntry where show = GShow.genericShow
instance decodeRunSysCmdEntry :: Decode RunSysCmdEntry where decode = defaultDecode
instance encodeRunSysCmdEntry :: Encode RunSysCmdEntry where encode = defaultEncode

instance rrItemRunSysCmdEntry :: RRItem RunSysCmdEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "RunSysCmdEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunSysCmdEntry"

instance mockedResultRunSysCmdEntry :: MockedResult RunSysCmdEntry String where
  parseRRItem (RunSysCmdEntry e) = Just e.result


derive instance genericDoAffEntry :: Generic DoAffEntry _
instance eqDoAffEntry :: Eq DoAffEntry where
  eq e1 e2 = (encodeJSON e1) == (encodeJSON e2)

instance decodeDoAffEntry :: Decode DoAffEntry where decode = defaultDecode
instance encodeDoAffEntry :: Encode DoAffEntry where encode = defaultEncode
instance showDoAffEntry   :: Show DoAffEntry where show = encodeJSON
instance rrItemDoAffEntry :: RRItem DoAffEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "DoAffEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "DoAffEntry"

instance mockedResultDoAffEntry :: Decode b => MockedResult DoAffEntry b where
  parseRRItem (DoAffEntry r) = hush $ E.runExcept $ decode r.jsonResult



derive instance genericRunDBEntry :: Generic RunDBEntry _
instance eqRunDBEntry :: Eq RunDBEntry where
  eq e1 e2 = (encodeJSON e1) == (encodeJSON e2)
instance decodeRunDBEntry :: Decode RunDBEntry where decode = genericDecode deoptions2 --defaultDecode
instance encodeRunDBEntry :: Encode RunDBEntry where encode = genericEncode deoptions2 --defaultEncode
instance showRunDBEntry   :: Show RunDBEntry where show = encodeJSON
instance rrItemRunDBEntry :: RRItem RunDBEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "RunDBEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunDBEntry"

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
instance showGetDBConnEntry   :: Show GetDBConnEntry where show = GShow.genericShow
instance decodeGetDBConnEntry :: Decode GetDBConnEntry where decode = defaultDecode
instance encodeGetDBConnEntry :: Encode GetDBConnEntry where encode = defaultEncode
instance rrItemGetDBConnEntry :: RRItem GetDBConnEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "GetDBConnEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetDBConnEntry"

instance mockedResultGetDBConnEntry :: MockedResult GetDBConnEntry SqlConn where
  parseRRItem (GetDBConnEntry entry) = Just $ MockedSql entry.mockedConn


derive instance genericGetKVDBConnEntry :: Generic GetKVDBConnEntry _
derive instance eqGetKVDBConnEntry :: Eq GetKVDBConnEntry
instance showGetKVDBConnEntry   :: Show GetKVDBConnEntry where show = GShow.genericShow
instance decodeGetKVDBConnEntry :: Decode GetKVDBConnEntry where decode = defaultDecode
instance encodeGetKVDBConnEntry :: Encode GetKVDBConnEntry where encode = defaultEncode
instance rrItemGetKVDBConnEntry :: RRItem GetKVDBConnEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "GetKVDBConnEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetKVDBConnEntry"

instance mockedResultGetKVDBConnEntry :: MockedResult GetKVDBConnEntry KVDBConn where
  parseRRItem (GetKVDBConnEntry entry) = Just $ MockedKVDB entry.mockedConn



derive instance genericRunKVDBEitherEntry :: Generic RunKVDBEitherEntry _
instance eqRunKVDBEitherEntry :: Eq RunKVDBEitherEntry where
  eq e1 e2 = encodeJSON e1 == encodeJSON e2
instance showRunKVDBEitherEntry   :: Show RunKVDBEitherEntry where show = encodeJSON
instance decodeRunKVDBEitherEntry :: Decode RunKVDBEitherEntry where decode = defaultDecode
instance encodeRunKVDBEitherEntry :: Encode RunKVDBEitherEntry where encode = defaultEncode
instance rrItemRunKVDBEitherEntry :: RRItem RunKVDBEitherEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "RunKVDBEitherEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBEitherEntry"

instance mockedResultRunKVDBEitherEntry
  :: Decode b => MockedResult RunKVDBEitherEntry (EitherEx DBError b) where
    parseRRItem (RunKVDBEitherEntry dbe) = do
      eResult <- case dbe.jsonResult of
        LeftEx  errResp -> Just $ LeftEx errResp
        RightEx strResp -> do
            (resultEx :: b) <- hush $ E.runExcept $ decode strResp
            Just $ RightEx resultEx
      pure eResult


derive instance genericRunKVDBSimpleEntry :: Generic RunKVDBSimpleEntry _
instance eqRunKVDBSimpleEntry :: Eq RunKVDBSimpleEntry where
  eq e1 e2 = encodeJSON e1 == encodeJSON e2
instance showRunKVDBSimpleEntry   :: Show RunKVDBSimpleEntry where show = encodeJSON
instance decodeRunKVDBSimpleEntry :: Decode RunKVDBSimpleEntry where decode = defaultDecode
instance encodeRunKVDBSimpleEntry :: Encode RunKVDBSimpleEntry where encode = defaultEncode
instance rrItemRunKVDBSimpleEntry :: RRItem RunKVDBSimpleEntry where
  toRecordingEntry rrItem idx mode = (RecordingEntry idx mode "RunKVDBSimpleEntry") <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry idx mode entryName re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBSimpleEntry"

instance mockedResultRunKVDBSimpleEntry :: Decode b => MockedResult RunKVDBSimpleEntry b where
    parseRRItem (RunKVDBSimpleEntry r) = hush $ E.runExcept $ decode r.jsonResult
