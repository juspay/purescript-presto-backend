module Presto.Backend.Types.EitherEx
  ( EitherEx (..)
  , class CustomExError
  , fromEitherEx
  , toEitherEx
  , fromCustomExError
  , toCustomExError
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Eq (class Eq, eq)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Generic.Rep (class Generic)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data EitherEx l r
  = LeftEx l
  | RightEx r

class CustomExError err1 err2 a where
  fromCustomExError :: EitherEx err2 a -> Either   err1 a
  toCustomExError   :: Either   err1 a -> EitherEx err2 a

fromEitherEx :: forall l r. EitherEx l r -> Either l r
fromEitherEx (LeftEx l)   = Left l
fromEitherEx (RightEx r)  = Right r

toEitherEx :: forall l r. Either l r -> EitherEx l r
toEitherEx (Left l)   = LeftEx l
toEitherEx (Right r)  = RightEx r


derive instance genericEitherEx :: Generic (EitherEx l r) _
derive instance functorEither :: Functor (EitherEx l)
instance decodeEitherEx :: (Decode l, Decode r) => Decode (EitherEx l r) where decode = defaultDecode
instance encodeEitherEx :: (Encode l, Encode r) => Encode (EitherEx l r) where encode = defaultEncode
instance eqEitherEx     :: (Eq l, Eq r) => Eq (EitherEx l r) where
  eq e1 e2 = fromEitherEx e1 == fromEitherEx e2
