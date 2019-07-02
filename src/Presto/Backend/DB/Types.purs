module Presto.Backend.DB.Types where

import Prelude

import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Control.Monad.Eff.Exception (Error, error, message)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep.Ord as GOrd
import Data.Eq (class Eq, eq)
import Data.Either (Either(..), either)
import Presto.Backend.Types.EitherEx (EitherEx(..), class CustomExError, fromCustomExError, toCustomExError)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)


-- TODO: you can use this data type to add more typed errors.
data DBError
  = DBError String

derive instance genericDBError :: Generic DBError _
instance decodeDBError         :: Decode  DBError where decode  = defaultDecode
instance encodeDBError         :: Encode  DBError where encode  = defaultEncode
instance eqDBError             :: Eq      DBError where eq      = GEq.genericEq
instance showDBError           :: Show    DBError where show    = GShow.genericShow
instance ordDBError            :: Ord     DBError where compare = GOrd.genericCompare


instance customExErrorDBError :: CustomExError Error DBError a where
  fromCustomExError (LeftEx (DBError errorMsg)) = Left $ error errorMsg
  fromCustomExError (RightEx a)                 = Right a
  toCustomExError = either (LeftEx <<< DBError <<< message) RightEx
