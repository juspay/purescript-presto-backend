-- This module is taken from purescript-sequelize.
-- TODO: rewrite it.

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

module Presto.Backend.TestData.DBModel where

import Prelude

import Control.Monad.Aff (Aff)
import Data.Foreign (toForeign)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe(..))
import Data.Monoid (mempty)
import Data.Options ((:=))
import Data.Tuple.Nested ((/\))
import Sequelize.Class (class EncodeModel, class DecodeModel, class Model, class Submodel, genericEncodeModel, genericDecodeModel)
import Sequelize.Connection (Dialect(..), database, dialect, getConn, storage, syncConn)
import Sequelize.Models (belongsTo, hasOne, makeModelOf)
import Sequelize.Models.Columns (columnType, defaultValue)
import Sequelize.Models.Types (DataType(..)) as ModelTypes
import Sequelize.Types (Alias(..), Conn, ModelCols, ModelOf, SEQUELIZE, defaultSyncOpts)

newtype Car = Car { model :: String, make :: String, hp :: Int }
derive instance genericCar :: Generic Car _
derive instance eqCar :: Eq Car
instance showCar :: Show Car where
  show = genericShow
instance decodeCar :: Decode Car where
  decode x = genericDecodeModel x
instance encodeCar :: Encode Car where
  encode x = genericEncodeModel x
instance decodeModelCar :: DecodeModel Car where
  decodeModel x = genericDecodeModel x
instance encodeModelCar :: EncodeModel Car where
  encodeModel x = genericEncodeModel x
instance isModelCar :: Model Car where
  modelCols = getCarCols
  modelName _ = "car"
getCarCols :: ModelCols Car
getCarCols = ["model" /\ modelOpts, "make" /\ makeOpts, "hp" /\ hpOpts]
  where
    modelOpts = columnType := ModelTypes.String {length: Nothing}
    makeOpts = columnType := ModelTypes.String {length: Nothing}
    hpOpts = columnType := ModelTypes.Integer {length: Nothing}

getCarModel :: forall e. Aff (sequelize :: SEQUELIZE | e) (ModelOf Car)
getCarModel = do
  conn <- myConn
  car <- makeModelOf conn mempty
  syncConn conn defaultSyncOpts {force = true}
  pure car

newtype Company = Company { name :: String }
derive instance genericCompany :: Generic Company _
derive instance eqCompany :: Eq Company
instance showCompany :: Show Company where
  show = genericShow
instance decodeCompany :: Decode Company where
  decode x = genericDecodeModel x
instance encodeCompany :: Encode Company where
  encode x = genericEncodeModel x
instance decodeModelCompany :: DecodeModel Company where
  decodeModel x = genericDecodeModel x
instance encodeModelCompany :: EncodeModel Company where
  encodeModel x = genericEncodeModel x
instance isModelCompany :: Model Company where
  modelCols = getCompanyCols
  modelName _ = "company"
getCompanyCols :: ModelCols Company
getCompanyCols = ["name" /\ nameOpts]
  where
  nameOpts =
    columnType := ModelTypes.String {length: Nothing} <>
    defaultValue := toForeign "ACME Co"

newtype User = User { name :: String }
derive instance eqUser :: Eq User
derive instance genericUser :: Generic User _
instance showUser :: Show User where
  show = genericShow
instance decodeUser :: Decode User where
  decode x = genericDecodeModel x
instance encodeUser :: Encode User where
  encode x = genericEncodeModel x
instance encodeModelUser :: EncodeModel User where
  encodeModel x = genericEncodeModel x
instance decodeModelUser :: DecodeModel User where
  decodeModel x = genericDecodeModel x
instance isModelUser :: Model User where
  modelCols = userCols
  modelName _ = "user"
userCols :: ModelCols User
userCols = ["name" /\ nameOpts]
  where
  nameOpts =
    columnType := ModelTypes.String {length: Nothing} <>
    defaultValue := toForeign "me"

newtype SuperUser = SuperUser { name :: String, employerId :: Int }
derive instance eqSuperUser :: Eq SuperUser
derive instance genericSuperUser :: Generic SuperUser _
instance showSuperUser :: Show SuperUser where
  show = genericShow
instance decodeSuperUser :: Decode SuperUser where
  decode x = genericDecodeModel x
instance encodeSuperUser :: Encode SuperUser where
  encode x = genericEncodeModel x
instance encodeModelSuperUser :: EncodeModel SuperUser where
  encodeModel x = genericEncodeModel x
instance decodeModelSuperUser :: DecodeModel SuperUser where
  decodeModel x = genericDecodeModel x
instance isModelSuperUser :: Model SuperUser where
  modelCols = superUserCols
  modelName _ = "superUser"
superUserCols :: ModelCols SuperUser
superUserCols = ["name" /\ nameOpts]
  where
  nameOpts =
    columnType := ModelTypes.String {length: Nothing} <>
    defaultValue := toForeign "me"

instance userSubSuper :: Submodel User SuperUser where
  project (SuperUser {name}) = User {name}

myConn :: forall e. Aff (sequelize :: SEQUELIZE | e) Conn
myConn = getConn opts
  where
    opts = database := "thunder"
        <> dialect := SQLite
        <> storage := "./test.sqlite"

getUserAndCompany
  :: forall e
   .
  Aff ( sequelize :: SEQUELIZE | e )
    { company :: ModelOf Company
    , user :: ModelOf User
    }
getUserAndCompany = do
  conn <- myConn
  company <- makeModelOf conn mempty
  user <- makeModelOf conn mempty
  user `belongsTo` company $ Alias "employer"
  company `hasOne` user $ Alias "employee"
  syncConn conn defaultSyncOpts {force = true}
  pure {company, user}
