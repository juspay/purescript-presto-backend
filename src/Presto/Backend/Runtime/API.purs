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

module Presto.Backend.Runtime.API
  ( runAPIInteraction
  ) where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Except (throwError, runExcept)
import Control.Monad.Free (foldFree)
import Data.Either (Either(..))
import Data.Foreign.Class (encode, decode)
import Data.NaturalTransformation (NaturalTransformation)
import Presto.Backend.Types.API (APIRunner) as API
import Presto.Core.Types.Language.Interaction (InteractionF(..), Interaction, ForeignIn(..), ForeignOut(..))

--type APIRunner = forall e. API.Request -> Aff e String

interpretAPI :: forall eff. API.APIRunner -> NaturalTransformation InteractionF (Aff eff)
interpretAPI apiRunner (Request (ForeignIn fgnIn) nextF) = do
  case runExcept $ decode fgnIn of
    -- This error should never happen if the `apiInteract` function is made right.
    Left err -> throwError (error ("apiInteract is broken: " <> show err))
    Right req -> do
      str <- apiRunner req
      pure $ nextF $ ForeignOut $ encode str


runAPIInteraction :: forall eff. API.APIRunner -> NaturalTransformation Interaction (Aff eff)
runAPIInteraction apiRunner = foldFree (interpretAPI apiRunner)
