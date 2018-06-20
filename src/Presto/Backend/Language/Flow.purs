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

import Control.Monad.Aff (Milliseconds)
import Control.Monad.Free (Free, liftF)
import Presto.Backend.Types (BackendAff)
import Presto.Core.Flow (Control)
import Presto.Core.Utils.Existing (Existing, mkExisting)

data BackendFlowCommands s next = 
      DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException String (s -> next)
    | Fork (BackendFlow s) (Control s -> next)
    | HandleException s next
    | Await (Control s) (s -> next)
    | Delay Milliseconds next


newtype BackendFlowF next = BackendFlowF (Existing BackendFlowCommands next)

type BackendFlow = Free BackendFlowF

wrap :: forall next s. BackendFlowCommands s next -> BackendFlow next
wrap = liftF <<< BackendFlowF <<< mkExisting

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
