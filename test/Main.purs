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

module Test.Main where

import Prelude
import Control.Monad.Aff.Console (CONSOLE, log)
import Control.Monad.Eff (Eff)
-- import Control.Monad.Eff.Console (log)
import Control.Monad.Aff (Aff, launchAff)
import Control.Monad.Eff.Class (liftEff)
import Node.Express.App (AppM, listenHttp, use, useExternal, useOnError, get)
import Node.Express.Response (sendJson, setResponseHeader, setStatus, send)
import Presto.Backend.Flow (BackendFlow, BackendException)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Except (runExcept)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Presto.Core.Types.API (Request) as API
import Presto.Backend.Interpreter (BackendRuntime(BackendRuntime), Connection(..), runBackend)
import Data.Options (options, (:=))
import Cache (host, port, db, socketKeepAlive, getConn, CACHE) as C
import Data.StrMap (StrMap, insert, singleton)
import Control.Monad.Eff.Ref (REF, Ref, readRef)
import Data.Either (Either(..))
import Data.Tuple (Tuple(..))
import Node.Express.Handler (HandlerM(HandlerM))

logger :: forall a. String -> a -> Aff _ Unit
logger s a = log s

apirunner :: forall e. API.Request -> Aff e String
apirunner r = pure "response"

class LocalState a where
    getStateObjectInstance :: a

newtype EmptyLocalState = EmptyLocalState Unit

instance emptyLocalStateInstance :: LocalState EmptyLocalState where
  getStateObjectInstance = EmptyLocalState unit

type Config = {
    "purescript-presto-backend" :: Boolean
}

upRoute :: BackendFlow EmptyLocalState Config (BackendException { context :: String }) String
upRoute = pure "UP"

apiWrapper :: forall st rt exception. LocalState st => StrMap Connection -> BackendFlow st Config exception String -> HandlerM _ Unit
apiWrapper state api = do
    let backendRuntime = BackendRuntime apirunner state logger
    response <- liftAff $ runExceptT ( runStateT ( runReaderT ( runBackend backendRuntime (api)) { "purescript-presto-backend" : true }) getStateObjectInstance)
    case response of
        Left (Tuple y x) -> send "DOWN"
        Right (Tuple y x) -> send y
    pure unit

appSetup :: StrMap Connection  -> AppM _ Unit
appSetup state = do
    get "/" (apiWrapper state upRoute)
    pure unit

initApp :: forall e. Aff _ Unit
initApp = do
    let cacheOpts = C.host := "127.0.0.1" <> C.port := 6379 <> C.db := 0 <> C.socketKeepAlive := true
    cacheConn <- C.getConn cacheOpts
    let conn = singleton "ECRRedis" (Redis cacheConn)
    _ <- liftEff $ listenHttp (appSetup conn) 8081 (const (pure unit))
    pure unit

main :: forall t1. Eff _ Unit
main = do
    _ <- launchAff initApp
    pure unit
    