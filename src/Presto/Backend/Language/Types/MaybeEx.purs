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

module Presto.Backend.Language.Types.MaybeEx
  ( MaybeEx (..)
  , fromMaybeEx
  , toMaybeEx
  , maybeEx
  ) where

import Prelude

import Data.Maybe (Maybe(..), maybe)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data MaybeEx a
  = NothingEx
  | JustEx a

maybeEx :: forall a b. b -> (a -> b) -> MaybeEx a -> b
maybeEx b f NothingEx  = b
maybeEx b f (JustEx a) = f a

fromMaybeEx :: forall a. MaybeEx a -> Maybe a
fromMaybeEx = maybeEx Nothing Just

toMaybeEx :: forall a. Maybe a -> MaybeEx a
toMaybeEx = maybe NothingEx JustEx


derive instance genericMaybeEx :: Generic (MaybeEx a) _
derive instance functorMaybe :: Functor MaybeEx
instance decodeMaybeEx :: (Decode a) => Decode (MaybeEx a) where decode = defaultDecode
instance encodeMaybeEx :: (Encode a) => Encode (MaybeEx a) where encode = defaultEncode
instance eqMaybeEx     :: (Eq a) => Eq (MaybeEx a) where
  eq m1 m2 = fromMaybeEx m1 == fromMaybeEx m2
