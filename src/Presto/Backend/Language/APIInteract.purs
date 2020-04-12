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

module Presto.Backend.APIInteract
  ( apiInteract
  , apiInteractGeneric
  ) where

import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Data.Foreign (toForeign)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Prelude (bind, pure, show, ($), (<>), (>>=))
import Presto.Backend.Language.Types.EitherEx (EitherEx(..))
import Presto.Backend.Types.API (class RestEndpoint, ErrorPayload(..), ErrorResponse, Response(..), Headers, decodeResponse, makeRequest)
import Presto.Core.Types.Language.Interaction (Interaction, request)
import Presto.Core.Utils.Encoding (defaultDecodeJSON)

apiInteractGeneric
  :: ∀ a b err
   . Encode a
   ⇒ Encode b
   ⇒ Decode b
   ⇒ Decode err
   ⇒ RestEndpoint a b
   ⇒ a
   → Headers → Interaction (EitherEx ErrorResponse (Either (Response err) b))
apiInteractGeneric a headers = do
  fgnOut ← request $ encode $ makeRequest a headers
  pure $ case runExcept $ decode fgnOut >>= decodeResponse of
    Right resp → RightEx $ Right resp
    Left x     →
      case runExcept $ decode fgnOut >>= defaultDecodeJSON of
      -- See if the server sent an error response, else create our own
        Right e@(Response _) →
          case runExcept $ decode $ toForeign e of
            Right (err :: ErrorResponse)  → LeftEx err
            Left _                        → RightEx $ Left e
        Left y →
          LeftEx $
            Response
              { code : 0
              , status : ""
              , response : ErrorPayload
                              { error: true
                              , errorMessage: show x <> "\n" <> show y
                              , userMessage: "Unknown error"
                              }
              } -- Differs from core @apiInteract@ by the only thing - @Encode@ constraint for @b@.

-- Interact function for API.
-- Differs from core @apiInteract@ by the only thing - @Encode@ constraint for @b@.
apiInteract :: forall a b.
  Encode a => Encode b => Decode b => RestEndpoint a b
  => a -> Headers -> Interaction (EitherEx ErrorResponse b)
apiInteract a headers = do
  fgnOut <- request (encode (makeRequest a headers))
  pure $ case runExcept (decode fgnOut >>= decodeResponse) of
    -- Try to decode the server's resopnse into the expected type
    Right resp -> RightEx resp
    Left x -> LeftEx $  case runExcept (decode fgnOut >>= defaultDecodeJSON) of
                       -- See if the server sent an error response, else create our own
                       Right e@(Response _) -> e
                       Left y -> Response
                                    { code : 0
                                    , status : ""
                                    , response : ErrorPayload
                                                    { error: true
                                                    , errorMessage: show x <> "\n" <> show y
                                                    , userMessage: "Unknown error"
                                                    }
                                    }
