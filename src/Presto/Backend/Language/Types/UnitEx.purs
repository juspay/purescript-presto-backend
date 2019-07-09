module Presto.Backend.Language.Types.UnitEx
  ( UnitEx (..)
  ) where

import Prelude

import Data.Eq (class Eq, eq)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Generic.Rep (class Generic)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data UnitEx = UnitEx

derive instance genericUnitEx :: Generic UnitEx _
instance decodeUnitEx :: Decode UnitEx where decode = defaultDecode
instance encodeUnitEx :: Encode UnitEx where encode = defaultEncode
instance eqUnitEx     :: Eq UnitEx where eq _ _ = true
