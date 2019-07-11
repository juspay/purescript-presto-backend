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

module Presto.Backend.Types.API
  ( class RestEndpoint
  , APIResult(..)
  , APIRunner(..)
  , ErrorPayload(..)
  , ErrorResponse
  , Method(..)
  , Header(..)
  , HeaderField
  , HeaderValue
  , Headers(..)
  , RegTokens(..)
  , Request(..)
  , Response(..)
  , URL
  , defaultMakeRequest
  , defaultMakeRequest_
  , defaultDecodeResponse
  , makeRequest
  , decodeResponse
  , responsePayload
  ) where

import Prelude

import Control.Monad.Aff (Aff)
import Data.Either (Either)
import Data.Foreign (F)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Presto.Core.Utils.Encoding (defaultDecode, defaultDecodeJSON, defaultEncode, defaultEncodeJSON)

type APIRunner = forall e. Request -> Aff e String

type APIResult s = Either ErrorResponse s

class RestEndpoint a b | a -> b, b -> a where
  makeRequest :: a -> Headers -> Request
  decodeResponse :: String -> F b

defaultMakeRequest :: forall a x. Generic a x => GenericEncode x
                   => Method -> URL -> Headers -> a -> Request
defaultMakeRequest method url headers req = Request { method:  method
                                                    , url: url
                                                    , headers: headers
                                                    , payload: defaultEncodeJSON req
                                                    }

defaultMakeRequest_ :: Method -> URL -> Headers -> Request
defaultMakeRequest_ method url headers = Request { method:  method
                                                 , url: url
                                                 , headers: headers
                                                 , payload: ""
                                                 }

defaultDecodeResponse :: forall a x. Generic a x => GenericDecode x
                      => String -> F a
defaultDecodeResponse = defaultDecodeJSON

type RegTokens =
  { regToken :: String
  , tokenId :: String
  , loginToken :: String
  }

type HeaderField = String
type HeaderValue = String
data Header = Header HeaderField HeaderValue
newtype Headers = Headers (Array Header)

type URL = String

data Method = POST | GET | PUT | DELETE
data GetReqBody = GetReqBody

newtype Request = Request
  { method :: Method
  , url :: URL
  , payload :: String
  , headers :: Headers
  }

newtype Response a = Response
  { code :: Int
  , status :: String
  , response :: a
  }

responsePayload :: forall a. Response a -> a
responsePayload (Response r) = r.response

newtype ErrorPayload = ErrorPayload
  { error :: Boolean
  , errorMessage :: String
  , userMessage :: String
  }

type ErrorResponse = Response ErrorPayload

derive instance genericMethod :: Generic Method _
instance encodeMethod :: Encode Method where
  encode = defaultEncode
instance decodeMethod :: Decode Method where
  decode = defaultDecode
instance showMethod :: Show Method where
  show = genericShow

derive instance genericHeader :: Generic Header _
instance encodeHeaderG :: Encode Header where
  encode = defaultEncode
instance decodeHeaderG :: Decode Header where
  decode = defaultDecode

derive instance genericHeaders :: Generic Headers _
instance encodeHeadersG :: Encode Headers where
  encode = defaultEncode
instance decodeHeadersG :: Decode Headers where
  decode = defaultDecode

derive instance genericRequest :: Generic Request _
instance encodeRequestG :: Encode Request where
  encode = defaultEncode
instance decodeRequestG :: Decode Request where
  decode = defaultDecode

derive instance genericErrorPayload :: Generic ErrorPayload _
derive instance eqErrorPayload :: Eq ErrorPayload
instance encodeErrorPayload :: Encode ErrorPayload where
  encode = defaultEncode
instance decodeErrorPayload :: Decode ErrorPayload where
  decode = defaultDecode
instance showErrorPayload :: Show ErrorPayload where
  show (ErrorPayload payload) = payload.userMessage

derive instance genericResponse :: Generic (Response a) _
derive instance eqResponse :: Eq a => Eq (Response a)
instance decodeResponseG :: Decode a => Decode (Response a) where
  decode = defaultDecode
instance encodeResponseG :: Encode a => Encode (Response a) where
  encode = defaultEncode
instance showResponse :: Show a => Show (Response a) where
  show (Response r) = show r.code <> "_" <> r.status <> "_" <> (show r.response)

derive instance genericGetReqBody :: Generic GetReqBody _
instance decodeGetReqBody :: Decode GetReqBody where decode = defaultDecode
instance encodeGetReqBody :: Encode GetReqBody where encode = defaultEncode
