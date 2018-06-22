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

module Presto.Backend.Interpreter where

import Prelude

import Cache (CacheConn, delKey, expire, getHashKey, getKey, incr, publishToChannel, setHash, setKey, setMessageHandler, setex, subscribe)
import Control.Monad.Aff (Aff, Canceler(..), delay, forkAff)
import Control.Monad.Aff.AVar (AVAR, makeEmptyVar, makeVar, putVar, readVar)
import Control.Monad.Eff.Exception (EXCEPTION, Error, error, message)
import Control.Monad.Except.Trans (ExceptT, ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Free (foldFree)
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Data.Array (filter, (!!))
import Data.Either (Either(..))
import Data.Exists (runExists)
import Data.Maybe (Maybe(..))
import Data.StrMap (StrMap, lookup)
import Presto.Backend.Flow (BackendFlow, BackendFlowCommands(..), BackendFlowF(..), Connection, LogRunner, doAff, unBackendFlow)
import Presto.Backend.SystemCommands (runSysCmd)
import Presto.Backend.Types (BackendAff)
import Presto.Core.Flow (APIRunner)
import Presto.Core.Types.Language.Flow (Control(..))
import Presto.Core.Utils.Existing (runExisting)
import Sequelize.Types (Conn)

type InterpreterMT err eff a = E.ExceptT err (BackendAff eff) a

type Cache = {
    name :: String
  , connection :: CacheConn
}

type DB = {
    name :: String
  , connection :: Conn
}

data BackendRuntime = BackendRuntime APIRunner (StrMap Connection) LogRunner

-- Need to be looked at later point of time.
forkFlow :: forall eff a. BackendRuntime -> BackendFlow a -> InterpreterMT Error eff (Control a)
forkFlow runtime flow = do
  resultVar <- E.lift makeEmptyVar
  _ <- E.lift $ forkAff (do
                            res <- E.runExceptT (runBackend runtime flow)
                            case res of
                              Right val -> putVar val resultVar
                              Left err -> pure unit
                        )
  pure $ Control resultVar


interpret :: forall s eff a. BackendRuntime -> BackendFlowCommands s a -> InterpreterMT Error eff a
interpret _ (DoAff aff nextF) = E.lift aff >>= (pure <<< nextF)
interpret _ (ThrowException errorMessage next) = E.ExceptT (Left <$> (pure $ error errorMessage)) *> pure next
interpret r (Fork flow nextF) = forkFlow r flow >>= (pure <<< nextF)
interpret _ (Await (Control var) nextF) = E.lift (readVar var) >>= (pure <<< nextF)
interpret _ (Delay t next) = E.lift (delay t) *> pure next
interpret (BackendRuntime _ _ logRunner) (LogFlow f nextF) = E.lift (f logRunner) >>= (pure <<< nextF)
interpret (BackendRuntime apiRunner _ _) (APIFlow f nextF) = E.lift (f apiRunner) >>= (pure <<< nextF)
interpret (BackendRuntime _ connMap _) (ConnFlow f nextF) = E.lift (f connMap) >>= (pure <<< nextF)

runBackend :: forall eff a. BackendRuntime -> BackendFlow a -> InterpreterMT Error eff a
runBackend backendRuntime = foldFree (\(BackendFlowF x) -> runExisting (interpret backendRuntime) x) <<< unBackendFlow
