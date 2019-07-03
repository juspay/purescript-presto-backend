module Presto.Backend.Types.MaybeEx
  ( MaybeEx (..)
  , fromMaybeEx
  , toMaybeEx
  , maybeEx
  ) where

import Prelude

import Data.Maybe (Maybe(..), maybe)
import Data.Eq (class Eq, eq)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
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
