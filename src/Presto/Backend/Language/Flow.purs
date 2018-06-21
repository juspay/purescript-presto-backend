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

module Presto.Backend.Flow where

import Prelude

import Control.Monad.Aff (Aff, Milliseconds)
import Control.Monad.Free (Free, liftF)
import Control.Monad.Rec.Class (class MonadRec, Step(..), tailRecM)
import Data.StrMap (StrMap)
import Presto.Backend.Types (BackendAff)
import Presto.Core.Flow (Control, APIRunner)
import Presto.Core.Utils.Existing (Existing, mkExisting, unExisting)
import Sequelize.Types (Conn)
import Cache (CacheConn)


type LogRunner = forall e a. String -> a -> Aff e Unit

data Connection = Sequelize Conn | Redis CacheConn

data BackendFlowCommands s next = 
      DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException String (s -> next)
    | Fork (BackendFlow s) (Control s -> next)
    | HandleException s next
    | Await (Control s) (s -> next)
    | Delay Milliseconds next
    -- private commands
    | LogFlow (forall e. LogRunner -> BackendAff e s) (s -> next)
    | APIFlow (forall e. APIRunner -> Aff e s) (s -> next)
    | DBFlow (forall e. StrMap Connection -> BackendAff e s) (s -> next)

instance functorBackendFlowCommands :: Functor (BackendFlowCommands s) where
  map f (DoAff g h) = DoAff g (f <<< h)
  map f (ThrowException g h) = ThrowException g (f <<< h)
  map f (Fork g h) = Fork g (f <<< h)
  map f (HandleException g h) = HandleException g (f h)
  map f (Await g h) = Await g (f <<< h)
  map f (Delay g h) = Delay g (f h)
  map f (LogFlow g h) = LogFlow g (f <<< h)
  map f (APIFlow g h) = APIFlow g (f <<< h)
  map f (DBFlow g h) = DBFlow g (f <<< h)

newtype BackendFlowF next = BackendFlowF (Existing BackendFlowCommands next)

instance functorBackendFlowF :: Functor BackendFlowF where
  map f (BackendFlowF e) = BackendFlowF $ mkExisting $ f <$> unExisting e

newtype BackendFlow a = BackendFlow (Free BackendFlowF a)

unBackendFlow :: forall a. BackendFlow a -> Free BackendFlowF a
unBackendFlow (BackendFlow fl) = fl

instance functorBackendFlow :: Functor BackendFlow where
  map f (BackendFlow fl) = BackendFlow (f <$> fl)

instance applyBackendFlow :: Apply BackendFlow where
  apply (BackendFlow f) (BackendFlow fl) = BackendFlow (apply f fl)

instance applicativeBackendFlow :: Applicative BackendFlow where
  pure = BackendFlow <<< pure

instance bindBackendFlow :: Bind BackendFlow where
  bind (BackendFlow fl) f = BackendFlow $ bind fl (unBackendFlow <<< f)

instance monadBackendFlow :: Monad BackendFlow

instance monadRecBackendFlow :: MonadRec BackendFlow where
  tailRecM k a = k a >>= case _ of
    Loop b -> tailRecM k b
    Done r -> pure r


wrap :: forall next s. BackendFlowCommands s next -> BackendFlow next
wrap = BackendFlow <<< liftF <<< BackendFlowF <<< mkExisting

doAff :: forall a. (forall eff. BackendAff eff a) -> BackendFlow a
doAff aff = wrap $ DoAff aff id

throwException :: forall a. String -> BackendFlow a
throwException errorMessage = wrap $ ThrowException errorMessage id

fork :: forall a. BackendFlow a -> BackendFlow (Control a)
fork f = wrap $ Fork f id

handleException :: forall a. a -> BackendFlow Unit
handleException e = wrap $ HandleException e unit

await :: forall a. Control a -> BackendFlow a
await c = wrap $ Await c id

delay :: Milliseconds -> BackendFlow Unit
delay t = wrap $ Delay t unit

logFlow :: forall a. (forall e. LogRunner -> BackendAff e a) -> BackendFlow a
logFlow f = wrap $ LogFlow f id

apiFlow :: forall a. (forall e. APIRunner -> Aff e a) -> BackendFlow a
apiFlow f = wrap $ APIFlow f id

dbFlow :: forall a. (forall e. StrMap Connection -> BackendAff e a) -> BackendFlow a
dbFlow f = wrap $ DBFlow f id
