module Presto.Backend.Language.Types.UnitEx
  ( UnitEx (..)
  , toUnitEx
  , fromUnitEx
  ) where

import Prelude

import Data.Eq (class Eq, eq)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Generic.Rep (class Generic)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data UnitEx = UnitEx

toUnitEx :: Unit -> UnitEx
toUnitEx _ = UnitEx

fromUnitEx :: UnitEx -> Unit
fromUnitEx _ = unit

derive instance genericUnitEx :: Generic UnitEx _
instance decodeUnitEx :: Decode UnitEx where decode = defaultDecode
instance encodeUnitEx :: Encode UnitEx where encode = defaultEncode
instance eqUnitEx     :: Eq UnitEx where eq _ _ = true
