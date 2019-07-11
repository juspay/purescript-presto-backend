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

module Presto.Backend.Language.Types.EitherEx
  ( EitherEx (..)
  , class CustomEitherEx
  , fromEitherEx
  , toEitherEx
  , eitherEx
  , fromCustomEitherEx
  , toCustomEitherEx
  , fromCustomEitherExF
  , toCustomEitherExF
  ) where

import Prelude

import Data.Either (Either(..), either)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data EitherEx l r
  = LeftEx l
  | RightEx r

eitherEx :: forall l r c. (l -> c) -> (r -> c) -> EitherEx l r -> c
eitherEx lf rf (LeftEx l)  = lf l
eitherEx lf rf (RightEx r) = rf r

class CustomEitherEx err1 err2 a where
  fromCustomEitherEx :: EitherEx err2 a -> Either   err1 a
  toCustomEitherEx   :: Either   err1 a -> EitherEx err2 a

fromEitherEx :: forall l r. EitherEx l r -> Either l r
fromEitherEx = eitherEx Left Right

toEitherEx :: forall l r. Either l r -> EitherEx l r
toEitherEx = either LeftEx RightEx

fromCustomEitherExF
  :: forall a b err1 err2
   . CustomEitherEx err1 err2 a
  => (a -> b)
  -> EitherEx err2 a
  -> Either   err1 b
fromCustomEitherExF f e = f <$> fromCustomEitherEx e

toCustomEitherExF
  :: forall a b err1 err2
   . CustomEitherEx err1 err2 b
  => (b -> a)
  -> Either   err1 b
  -> EitherEx err2 a
toCustomEitherExF f e = f <$> toCustomEitherEx e

derive instance genericEitherEx :: Generic (EitherEx l r) _
derive instance functorEither :: Functor (EitherEx l)
instance decodeEitherEx :: (Decode l, Decode r) => Decode (EitherEx l r) where decode = defaultDecode
instance encodeEitherEx :: (Encode l, Encode r) => Encode (EitherEx l r) where encode = defaultEncode
instance eqEitherEx     :: (Eq l, Eq r) => Eq (EitherEx l r) where
  eq e1 e2 = fromEitherEx e1 == fromEitherEx e2
