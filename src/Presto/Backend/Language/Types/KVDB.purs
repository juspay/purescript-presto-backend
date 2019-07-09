module Presto.Backend.Language.Types.KVDB where

import Prelude

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
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

-- Custom types that represents the native Multi in our system.
type KVDBName = String
type MultiGUID = String
data Multi = Multi KVDBName MultiGUID

getKVDBName :: Multi -> KVDBName
getKVDBName (Multi name _) = name

derive instance genericMulti :: Generic Multi _
instance decodeMulti         :: Decode  Multi where decode  = defaultDecode
instance encodeMulti         :: Encode  Multi where encode  = defaultEncode
instance eqMulti             :: Eq      Multi where eq      = GEq.genericEq
instance showMulti           :: Show    Multi where show    = GShow.genericShow
instance ordMulti            :: Ord     Multi where compare = GOrd.genericCompare
