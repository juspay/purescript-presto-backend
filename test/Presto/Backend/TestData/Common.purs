module Presto.Backend.TestData.Common where

import Prelude

import Control.Monad.Aff (Aff)
import Data.Foreign (toForeign)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe(..))
import Data.Monoid (mempty)
import Data.Options (Options(..), (:=))
import Data.StrMap as Map
import Data.String (singleton)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Sequelize.Class (class EncodeModel, class DecodeModel, class Model, class Submodel, genericEncodeModel, genericDecodeModel)
import Sequelize.Connection (Dialect(..), database, dialect, getConn, storage, syncConn)
import Sequelize.Models (belongsTo, hasOne, makeModelOf)
import Sequelize.Models.Columns (columnType, defaultValue)
import Sequelize.Models.Types (DataType(..)) as ModelTypes
import Sequelize.Types (Alias(..), Conn, ModelCols, ModelOf, SEQUELIZE, defaultSyncOpts)

import Presto.Backend.TestData.DBModel

enterprise :: Char -> Car
enterprise c
  = Car
  { make: "Federation of Planets"
  , model: "Enterprise " <> singleton c
  , hp: 1000000
  }

voyager :: Car
voyager
  = Car
  { make: "Federation of Planets"
  , model: "Voyager"
  , hp: 500000
  }
