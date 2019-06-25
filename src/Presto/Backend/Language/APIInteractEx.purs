module Presto.Backend.APIInteractEx
  ( ErrorResponseEx (..)
  , APIResultEx (..)
  , ExtendedAPIResultEx(..)
  , APIResultEx(..)
  , apiInteractEx
  , fromErrorResponseEx
  , fromAPIResultEx
  ) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Data.Lazy (Lazy, defer)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Generic.Rep (class Generic)
import Data.Foreign.Generic (encodeJSON)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Presto.Core.Types.Language.Flow (APIResult)
import Data.Either (Either(..))
import Presto.Core.Types.Language.Interaction (Interaction, request)
import Presto.Core.Types.API (class RestEndpoint, ErrorPayload(..), ErrorResponse, Response(..), Headers, decodeResponse, makeRequest)
import Presto.Core.Utils.Encoding (defaultDecodeJSON)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

-- This is done because of lack of instances.

newtype ErrorResponseEx = ErrorResponseEx (Response ErrorPayload)

data APIResultEx a
  = APILeft ErrorResponseEx
  | APIRight a

newtype ExtendedAPIResultEx b = ExtendedAPIResultEx
  { mkJsonRequest :: Lazy String
  , resultEx      :: APIResultEx b
  }

apiInteractEx :: forall a b.
  Encode a => Encode b => Decode b => RestEndpoint a b
  => a -> Headers -> Interaction (ExtendedAPIResultEx b)
apiInteractEx a headers = do
  (resultEx :: APIResultEx b) <- apiInteract' a headers
  let mkJsonRequest = defer $ \_ -> encodeJSON $ makeRequest a headers
  pure $ ExtendedAPIResultEx { mkJsonRequest, resultEx }

-- Interact function for API.
-- Differs from @apiInteract@ by the only thing - @Encode@ constraint for @b@.
apiInteract' :: forall a b.
  Encode a => Encode b => Decode b => RestEndpoint a b
  => a -> Headers -> Interaction (APIResultEx b)
apiInteract' a headers = do
  fgnOut <- request (encode (makeRequest a headers))
  pure $ case runExcept (decode fgnOut >>= decodeResponse) of
    -- Try to decode the server's resopnse into the expected type
    Right resp -> APIRight resp
    Left x -> APILeft $ ErrorResponseEx $ case runExcept (decode fgnOut >>= defaultDecodeJSON) of
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


fromErrorResponseEx :: ErrorResponseEx -> ErrorResponse
fromErrorResponseEx (ErrorResponseEx rex) = rex

fromAPIResultEx :: forall a. APIResultEx a -> APIResult a
fromAPIResultEx (APILeft eEx) = Left $ fromErrorResponseEx eEx
fromAPIResultEx (APIRight a) = Right a



derive instance genericErrorResponseEx :: Generic ErrorResponseEx _
instance decodeErrorResponseEx :: Decode ErrorResponseEx where decode = defaultDecode
instance encodeErrorResponseEx :: Encode ErrorResponseEx where encode = defaultEncode

derive instance functorEither :: Functor APIResultEx
derive instance genericAPIResultEx :: Generic (APIResultEx a) _
instance decodeAPIResultEx :: Decode a => Decode (APIResultEx a) where decode = defaultDecode
instance encodeAPIResultEx :: Encode a => Encode (APIResultEx a) where encode = defaultEncode

instance aPIResultExEq :: Eq a => Eq (APIResultEx a) where
  eq (APIRight a) (APIRight b) = a == b
  eq (APILeft (ErrorResponseEx (Response ae))) (APILeft (ErrorResponseEx (Response be))) =
    ae.code == be.code
    && ae.status == be.status
    && errPayloadEq ae.response be.response
    where
      errPayloadEq (ErrorPayload aep) (ErrorPayload bep) =
        aep.error == bep.error
        && aep.errorMessage == bep.errorMessage
        && aep.userMessage == bep.userMessage
  eq _ _ = false
