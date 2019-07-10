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

import Cache (CACHE, SimpleConn, SimpleConnOpts, newConn, host, port, socketKeepAlive, db)
import Control.Monad.Aff (Aff, launchAff_)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Aff.Console (CONSOLE)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (throwException)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either(..))
import Data.Options ((:=), Options)
import Data.StrMap (StrMap, singleton)
import Debug.Trace (spy)
import Presto.Backend.Flow (BackendFlow, log, ask)
import Presto.Backend.Interpreter (BackendRuntime(..), Connection(..), runBackend)
import Presto.Core.Types.API (Request(..))

type Config = {
    test :: Boolean
}

configs = { test : true}

newtype FooState = FooState { test :: Boolean}

fooState = FooState { test : true}

apiRunner :: ∀ e. Request → Aff e String
apiRunner r = pure "add working api runner!"

redisOptions :: Options SimpleConnOpts
redisOptions = host := "127.0.0.1"
         <> port := 6379
         <> db := 0
         <> socketKeepAlive := true

connections :: Connection -> StrMap Connection
connections conn = singleton "DB" conn

logRunner :: forall e a. String -> a -> Aff _ Unit
logRunner tag value = liftEff $ addToPerf tag value

foo :: BackendFlow FooState Config Unit
foo = ask *> ask *> pure unit

foreign import printPerf :: forall a e. Eff e Unit
foreign import addToPerf :: forall a e. String -> a -> Eff e Unit


tryRedisConn :: forall e. Options SimpleConnOpts -> Aff _ SimpleConn
tryRedisConn opts = do
    eCacheConn <- newConn opts
    case eCacheConn of
         Right c -> pure c
         Left err -> liftEff $ throwException err

main :: forall t1. Eff _ Unit
main = launchAff_ start  *> pure unit

start :: forall t1. Aff _ Unit
start = do
    conn <- tryRedisConn redisOptions
    let backendRuntime = BackendRuntime apiRunner (connections (Redis conn)) logRunner
    response  <- liftAff $ runExceptT ( runStateT ( runReaderT ( runBackend backendRuntime (foo)) configs) fooState)
    _ <- liftEff printPerf
    pure unit