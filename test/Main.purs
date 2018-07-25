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

module Main where

import Prelude

import Effect.Aff (Aff, launchAff)
import Effect.Aff.Class (liftAff)
import Effect.Aff.Console as A
import Effect (Eff)
import Effect.Console (log)
import Control.Monad.Except (runExceptT)
import Control.Monad.Reader (runReaderT)
import Control.Monad.State (runStateT)
import Data.StrMap (singleton)
import Presto.Backend.Flow (forkFlow)
import Presto.Backend.Interpreter (BackendRuntime(..), Connection, LogRunner, runBackend)
import Presto.Backend.Language.Runtime.API (APIRunner)


main :: Eff _ Unit
main = do
    _ <- launchAff testForkFlow 
    log "I am awesome"

affForFork :: forall e. Aff (console :: CONSOLE | e) Unit
affForFork = A.log "Awesome it works"

-- testFlow :: forall t2 t3 t4. Free (BackendFlowWrapper t4 t3 t2) Unit
testFlow = forkFlow affForFork

foreign import getDummyConnection :: Connection

-- ( avar :: AVAR, exception :: EXCEPTION, network :: NETWORK, console :: CONSOLE, sequelize :: SEQUELIZE, cache :: CACHE, fs :: FS, process :: PROCESS, uuid :: GENUUID | e)
testForkFlow :: Aff _ Unit
testForkFlow = do
  let backendRuntime = BackendRuntime apiRunner (singleton "test" getDummyConnection) logRunner
  someResult <- liftAff $ runExceptT ( runStateT ( runReaderT ( runBackend backendRuntime (testFlow)) "reader") "state")
  pure unit
  where
      apiRunner :: APIRunner
      apiRunner a = pure "unit"
      
      logRunner :: LogRunner
      logRunner tag message = pure unit