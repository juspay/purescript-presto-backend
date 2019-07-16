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


derive instance genericLogEntry :: Generic LogEntry _
derive instance eqLogEntry :: Eq LogEntry

instance decodeLogEntry :: Decode LogEntry where decode = defaultDecode
instance encodeLogEntry :: Encode LogEntry where encode = defaultEncode

instance rrItemLogEntry :: RRItem LogEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "LogEntry"
  isMocked _ = true


instance mockedResultLogEntry :: MockedResult LogEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericForkFlowEntry :: Generic ForkFlowEntry _
derive instance eqForkFlowEntry :: Eq ForkFlowEntry

instance decodeForkFlowEntry :: Decode ForkFlowEntry where decode = defaultDecode
instance encodeForkFlowEntry :: Encode ForkFlowEntry where encode = defaultEncode

instance rrItemForkFlowEntry :: RRItem ForkFlowEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "ForkFlowEntry"
  isMocked _ = true

instance mockedResultForkFlowEntry :: MockedResult ForkFlowEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericThrowExceptionEntry :: Generic ThrowExceptionEntry _
derive instance eqThrowExceptionEntry :: Eq ThrowExceptionEntry

instance decodeThrowExceptionEntry :: Decode ThrowExceptionEntry where decode = defaultDecode
instance encodeThrowExceptionEntry :: Encode ThrowExceptionEntry where encode = defaultEncode

instance rrItemThrowExceptionEntry :: RRItem ThrowExceptionEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "ThrowExceptionEntry"
  isMocked _ = true

instance mockedResultThrowExceptionEntry :: MockedResult ThrowExceptionEntry UnitEx where
  parseRRItem _ = Just UnitEx


derive instance genericCallAPIEntry :: Generic CallAPIEntry _
instance eqCallAPIEntry :: Eq CallAPIEntry where
  eq e1 e2 = encodeJSON e1 == encodeJSON e2

instance decodeCallAPIEntry :: Decode CallAPIEntry where decode = defaultDecode
instance encodeCallAPIEntry :: Encode CallAPIEntry where encode = defaultEncode

instance rrItemCallAPIEntry :: RRItem CallAPIEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
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
  toRecordingEntry rrItem mode = (RecordingEntry mode) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
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
  toRecordingEntry rrItem mode = (RecordingEntry mode) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
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
  toRecordingEntry rrItem mode = (RecordingEntry mode) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
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
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetDBConnEntry"
  isMocked _ = true

instance mockedResultGetDBConnEntry :: MockedResult GetDBConnEntry SqlConn where
  parseRRItem (GetDBConnEntry entry) = Just $ MockedSql entry.mockedConn


derive instance genericGetKVDBConnEntry :: Generic GetKVDBConnEntry _
derive instance eqGetKVDBConnEntry :: Eq GetKVDBConnEntry
instance decodeGetKVDBConnEntry :: Decode GetKVDBConnEntry where decode = defaultDecode
instance encodeGetKVDBConnEntry :: Encode GetKVDBConnEntry where encode = defaultEncode
instance rrItemGetKVDBConnEntry :: RRItem GetKVDBConnEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "GetKVDBConnEntry"
  isMocked _ = true

instance mockedResultGetKVDBConnEntry :: MockedResult GetKVDBConnEntry KVDBConn where
  parseRRItem (GetKVDBConnEntry entry) = Just $ MockedKVDB entry.mockedConn



derive instance genericRunKVDBEitherEntry :: Generic RunKVDBEitherEntry _
instance eqRunKVDBEitherEntry :: Eq RunKVDBEitherEntry where
  eq e1 e2 = encodeJSON e1 == encodeJSON e2
instance decodeRunKVDBEitherEntry :: Decode RunKVDBEitherEntry where decode = defaultDecode
instance encodeRunKVDBEitherEntry :: Encode RunKVDBEitherEntry where encode = defaultEncode
instance rrItemRunKVDBEitherEntry :: RRItem RunKVDBEitherEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBEitherEntry"
  isMocked _ = true

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
instance decodeRunKVDBSimpleEntry         :: Decode RunKVDBSimpleEntry where decode = defaultDecode
instance encodeRunKVDBSimpleEntry         :: Encode RunKVDBSimpleEntry where encode = defaultEncode
instance rrItemRunKVDBSimpleEntry         :: RRItem RunKVDBSimpleEntry where
  toRecordingEntry rrItem mode = (RecordingEntry mode ) <<< encodeJSON $ rrItem
  fromRecordingEntry (RecordingEntry mode re) = hush $ E.runExcept $ decodeJSON re
  getTag   _ = "RunKVDBSimpleEntry"
  isMocked _ = true

instance mockedResultRunKVDBSimpleEntry :: Decode b => MockedResult RunKVDBSimpleEntry b where
    parseRRItem (RunKVDBSimpleEntry r) = hush $ E.runExcept $ decode r.jsonResult
