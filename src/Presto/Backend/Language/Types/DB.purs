module Presto.Backend.Language.Types.DB where

import Prelude

import Cache (SimpleConn)
import Control.Monad.Eff.Exception (Error, error, message)
import Data.Tuple (Tuple)
import Data.StrMap (StrMap)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep.Ord as GOrd
import Data.Eq (class Eq, eq)
import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..), maybe)
import Presto.Backend.Language.Types.EitherEx(EitherEx (..), class CustomEitherEx, fromEitherEx, toEitherEx, eitherEx, fromCustomEitherEx, toCustomEitherEx)
import Presto.Backend.Language.Types.MaybeEx (MaybeEx(..), toMaybeEx, fromMaybeEx, maybeEx)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Sequelize.Types (Conn)

-- TODO: you can use this data type to add more typed errors.
data DBError
  = DBError String

toDBError :: Error -> DBError
toDBError = DBError <<< message

fromDBError :: DBError -> Error
fromDBError (DBError strError) = error strError

toDBMaybeResult :: forall a. Either Error (Maybe a) -> EitherEx DBError (MaybeEx a)
toDBMaybeResult = either (LeftEx <<< toDBError) (RightEx <<< toMaybeEx)

fromDBMaybeResult :: forall a. EitherEx DBError (MaybeEx a) -> Either Error (Maybe a)
fromDBMaybeResult = eitherEx (Left <<< fromDBError) (Right <<< fromMaybeEx)

-- TODO: this should be reworked.
-- DB facilities design is not good enough.
-- For now, mocking approach is suboptimal, fast & dirty.

data MockedSqlConn  = MockedSqlConn String
data MockedKVDBConn = MockedKVDBConn String

data SqlConn
  = MockedSql MockedSqlConn
  | Sequelize Conn

data KVDBConn
  = MockedKVDB MockedKVDBConn
  | Redis SimpleConn

data Connection
  = SqlConn SqlConn
  | KVDBConn KVDBConn

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

derive instance genericMockedSqlConn :: Generic MockedSqlConn _
instance decodeMockedSqlConn         :: Decode  MockedSqlConn where decode  = defaultDecode
instance encodeMockedSqlConn         :: Encode  MockedSqlConn where encode  = defaultEncode
instance eqMockedSqlConn             :: Eq      MockedSqlConn where eq      = GEq.genericEq
instance showMockedSqlConn           :: Show    MockedSqlConn where show    = GShow.genericShow
instance ordMockedSqlConn            :: Ord     MockedSqlConn where compare = GOrd.genericCompare

derive instance genericMockedKVDBConn :: Generic MockedKVDBConn _
instance decodeMockedKVDBConn         :: Decode  MockedKVDBConn where decode  = defaultDecode
instance encodeMockedKVDBConn         :: Encode  MockedKVDBConn where encode  = defaultEncode
instance eqMockedKVDBConn             :: Eq      MockedKVDBConn where eq      = GEq.genericEq
instance showMockedKVDBConn           :: Show    MockedKVDBConn where show    = GShow.genericShow
instance ordMockedKVDBConn            :: Ord     MockedKVDBConn where compare = GOrd.genericCompare
