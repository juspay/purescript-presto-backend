{-
 Copyright (c) 2012-2017 "JUSPAY Technologies"
 JUSPAY Technologies Pvt. Ltd. [https://www.juspay.in]
 This file is part of JUSPAY Platform.
 JUSPAY Platform is free software: you can redistribute it and/or modify
 it for only educational purposes under the terms of the GNU Affero General
 Public License (GNU AGPL) as published by the Free Software Foundation,
 either version 3 of the License, or (at your option) any later version.
 For Enterprise/Commerical licenses, contact <info@juspay.in>.
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  The end user will
 be liable for all damages without limitation, which is caused by the
 ABUSE of the LICENSED SOFTWARE and shall INDEMNIFY JUSPAY for such
 damages, claims, cost, including reasonable attorney fee claimed on Juspay.
 The end user has NO right to claim any indemnification based on its use
 of Licensed Software. See the GNU Affero General Public License for more details.
 You should have received a copy of the GNU Affero General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/agpl.html>.
-}

module Presto.Backend.Runtime.Common where

import Prelude

import Data.Tuple (Tuple(..))
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.StrMap (lookup)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Except.Trans (ExceptT(..), lift) as E
import Control.Monad.Reader.Trans (lift) as R
import Control.Monad.State.Trans (get, lift) as S
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Runtime.Types (BackendRuntime(BackendRuntime), Connection(SqlConn, KVDBConn), InterpreterMT')
import Presto.Backend.Language.Types.DB (KVDBConn, SqlConn)

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

getKVDBConnection :: forall st rt eff. BackendRuntime -> String -> InterpreterMT' rt st eff (Either String KVDBConn)
getKVDBConnection brt@(BackendRuntime rt) dbName = do
  let mbConn = lookup dbName rt.connections
  case mbConn of
    Just (KVDBConn kvDBConn) -> pure $ Right kvDBConn
    Just (SqlConn _)         -> pure $ Left "Found SQL DB Connection instead KV DB Connection."
    _                        -> pure $ Left "No DB Connection found"