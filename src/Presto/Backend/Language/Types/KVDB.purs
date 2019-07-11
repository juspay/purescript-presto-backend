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

module Presto.Backend.Language.Types.KVDB where

import Prelude

import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep.Ord as GOrd
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

-- Custom types that represents the native Multi in our system.
type KVDBName = String
type MultiGUID = String
data Multi = Multi KVDBName MultiGUID

getKVDBName :: Multi -> KVDBName
getKVDBName (Multi name _) = name

getMultiGUID :: Multi -> MultiGUID
getMultiGUID (Multi _ guid) = guid

derive instance genericMulti :: Generic Multi _
instance decodeMulti         :: Decode  Multi where decode  = defaultDecode
instance encodeMulti         :: Encode  Multi where encode  = defaultEncode
instance eqMulti             :: Eq      Multi where eq      = GEq.genericEq
instance showMulti           :: Show    Multi where show    = GShow.genericShow
instance ordMulti            :: Ord     Multi where compare = GOrd.genericCompare
