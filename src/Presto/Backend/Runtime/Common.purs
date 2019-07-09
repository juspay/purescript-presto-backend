module Presto.Backend.Runtime.Common where

import Prelude

import Data.Tuple (Tuple(..))
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.StrMap (StrMap, lookup)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Except.Trans (ExceptT(..), lift) as E
import Control.Monad.Reader.Trans (ReaderT, lift) as R
import Control.Monad.State.Trans (StateT, get, lift) as S
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Runtime.Types (InterpreterMT, InterpreterMT', BackendRuntime(..), Connection(..))
import Presto.Backend.Language.Types.DB (KVDBConn(..), SqlConn(..), MockedSqlConn(..), MockedKVDBConn(..))

foreign import jsonStringify :: forall a. a -> String


lift3 :: forall eff err rt st a. BackendAff eff a -> InterpreterMT' rt st eff a
lift3 m = R.lift (S.lift (E.lift m))

throwException' :: forall st rt s eff a. String -> InterpreterMT' rt st eff a
throwException' errorMessage = do
  st <- R.lift S.get
  R.lift $ S.lift $ E.ExceptT $ pure $ Left $ Tuple (error errorMessage) st


getDBConn' :: forall st rt eff. BackendRuntime -> String -> InterpreterMT' rt st eff SqlConn
getDBConn' brt@(BackendRuntime rt) dbName = do
  let mbConn = lookup dbName rt.connections
  case mbConn of
    Just (SqlConn sqlConn) -> pure sqlConn
    Just (KVDBConn _)      -> throwException' "Found KV DB Connection instead SQL DB Connection."
    _                      -> throwException' "No DB found"

getKVDBConn' :: forall st rt eff. BackendRuntime -> String -> InterpreterMT' rt st eff KVDBConn
getKVDBConn' brt@(BackendRuntime rt) dbName = do
  let mbConn = lookup dbName rt.connections
  case mbConn of
    Just (KVDBConn kvDBConn) -> pure kvDBConn
    Just (SqlConn _)         -> throwException' "Found SQL DB Connection instead KV DB Connection."
    _                        -> throwException' "No DB found"
