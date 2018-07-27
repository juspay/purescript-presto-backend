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

module Presto.Backend.APIHandler where


import Data.Either (Either)
import Effect (Effect)
import Effect.Aff (Canceler(..))
import Effect.Exception (Error)
import Prelude (Unit, show, (<$>))
import Presto.Backend.Types (ZipkinConfig)
import Presto.Backend.Types.API (Header(..), Headers(..), Request(..), URL)


type NativeHeader = { field :: String , value :: String}
type NativeHeaders = Array NativeHeader

type AffError = (Error -> Effect Unit)
type AffSuccess s = (s -> Effect Unit)

newtype NativeRequest = NativeRequest
  { method :: String
  , url :: URL
  , payload :: String
  , headers :: NativeHeaders
  }

foreign import callAPI' :: (Either Error String -> Effect Unit) -> NativeRequest -> Effect Canceler
foreign import traceCallAPI :: ZipkinConfig -> (AffError) -> (AffSuccess String) -> NativeRequest -> (Effect Unit)
foreign import logString' :: forall a. a -> String

mkNativeRequest :: Request -> NativeRequest
mkNativeRequest (Request request@{headers: Headers hs}) = NativeRequest
                                          { method : show request.method
                                            , url: request.url
                                            , payload: request.payload
                                            , headers: mkNativeHeader <$> hs
                                            }

mkNativeHeader :: Header -> NativeHeader
mkNativeHeader (Header field val) = { field: field, value: val}
