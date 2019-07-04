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
import Data.Maybe (Maybe(..), maybe)
import Presto.Backend.Types.EitherEx(EitherEx (..), class CustomEitherEx, fromEitherEx, toEitherEx, eitherEx, fromCustomEitherEx, toCustomEitherEx)
import Presto.Backend.Types.MaybeEx (MaybeEx(..), toMaybeEx, fromMaybeEx, maybeEx)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

-- TODO: you can use this data type to add more typed errors.
data DBError
  = DBError String

toDBError :: Error -> DBError
toDBError = DBError <<< message

fromDBError :: DBError -> Error
fromDBError (DBError strError) = error strError

derive instance genericDBError :: Generic DBError _
instance decodeDBError         :: Decode  DBError where decode  = defaultDecode
instance encodeDBError         :: Encode  DBError where encode  = defaultEncode
instance eqDBError             :: Eq      DBError where eq      = GEq.genericEq
instance showDBError           :: Show    DBError where show    = GShow.genericShow
instance ordDBError            :: Ord     DBError where compare = GOrd.genericCompare

instance customExErrorDBError :: CustomEitherEx Error DBError a where
  fromCustomEitherEx (LeftEx (DBError errorMsg)) = Left $ error errorMsg
  fromCustomEitherEx (RightEx a)                 = Right a
  toCustomEitherEx = either (LeftEx <<< DBError <<< message) RightEx

toDBMaybeResult :: forall a. Either Error (Maybe a) -> EitherEx DBError (MaybeEx a)
toDBMaybeResult = either (LeftEx <<< toDBError) (RightEx <<< toMaybeEx)

fromDBMaybeResult :: forall a. EitherEx DBError (MaybeEx a) -> Either Error (Maybe a)
fromDBMaybeResult = eitherEx (Left <<< fromDBError) (Right <<< fromMaybeEx)
