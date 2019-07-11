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

module Presto.Backend.Language.Types.DB where

import Prelude

import Cache (SimpleConn)
import Control.Monad.Eff.Exception (Error, error, message)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep.Ord as GOrd
import Data.Either (Either(..), either)
import Data.Maybe (Maybe)
import Presto.Backend.Language.Types.EitherEx (class CustomEitherEx, EitherEx(RightEx, LeftEx), eitherEx)
import Presto.Backend.Language.Types.MaybeEx (MaybeEx, fromMaybeEx, toMaybeEx)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Sequelize.Types (Conn)

-- TODO: you can use this data type to add more typed errors.
data DBError
  = DBError String

toDBError :: Error -> DBError
toDBError = DBError <<< message

fromDBError :: DBError -> Error
fromDBError (DBError strError) = error strError

toDBMaybeResult :: forall a. Either Error (Maybe a) -> EitherEx DBError (MaybeEx a)
toDBMaybeResult = either (LeftEx <<< toDBError) (RightEx <<< toMaybeEx)

fromDBMaybeResult :: forall a. EitherEx DBError (MaybeEx a) -> Either Error (Maybe a)
fromDBMaybeResult = eitherEx (Left <<< fromDBError) (Right <<< fromMaybeEx)

-- TODO: this should be reworked.
-- DB facilities design is not good enough.
-- For now, mocking approach is suboptimal, fast & dirty.

data MockedSqlConn  = MockedSqlConn String
data MockedKVDBConn = MockedKVDBConn String

data SqlConn
  = MockedSql MockedSqlConn
  | Sequelize Conn

data KVDBConn
  = MockedKVDB MockedKVDBConn
  | Redis SimpleConn

data Connection
  = SqlConn SqlConn
  | KVDBConn KVDBConn

derive instance genericDBError :: Generic DBError _
instance decodeDBError         :: Decode  DBError where decode  = defaultDecode
instance encodeDBError         :: Encode  DBError where encode  = defaultEncode
instance eqDBError             :: Eq      DBError where eq      = GEq.genericEq
instance showDBError           :: Show    DBError where show    = GShow.genericShow
instance ordDBError            :: Ord     DBError where compare = GOrd.genericCompare

instance customExErrorDBError :: CustomEitherEx Error DBError a where
  fromCustomEitherEx (LeftEx (DBError errorMsg)) = Left $ error errorMsg
  fromCustomEitherEx (RightEx a)                 = Right a
  toCustomEitherEx = either (LeftEx <<< DBError <<< message) RightEx

derive instance genericMockedSqlConn :: Generic MockedSqlConn _
instance decodeMockedSqlConn         :: Decode  MockedSqlConn where decode  = defaultDecode
instance encodeMockedSqlConn         :: Encode  MockedSqlConn where encode  = defaultEncode
instance eqMockedSqlConn             :: Eq      MockedSqlConn where eq      = GEq.genericEq
instance showMockedSqlConn           :: Show    MockedSqlConn where show    = GShow.genericShow
instance ordMockedSqlConn            :: Ord     MockedSqlConn where compare = GOrd.genericCompare

derive instance genericMockedKVDBConn :: Generic MockedKVDBConn _
instance decodeMockedKVDBConn         :: Decode  MockedKVDBConn where decode  = defaultDecode
instance encodeMockedKVDBConn         :: Encode  MockedKVDBConn where encode  = defaultEncode
instance eqMockedKVDBConn             :: Eq      MockedKVDBConn where eq      = GEq.genericEq
instance showMockedKVDBConn           :: Show    MockedKVDBConn where show    = GShow.genericShow
instance ordMockedKVDBConn            :: Ord     MockedKVDBConn where compare = GOrd.genericCompare
