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
import Data.Eq (class Eq, eq)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
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
