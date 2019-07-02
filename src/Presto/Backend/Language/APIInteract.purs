module Presto.Backend.APIInteract
  (-- ErrorResponseEx (..)
 -- , APIResultEx (..)
 -- , APIResult(..)
 -- , ExtendedAPIResultEx(..)
   apiInteract
 -- , fromErrorResponseEx
 -- , fromAPIResultEx
  ) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Data.Lazy (Lazy, defer)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Generic.Rep (class Generic)
import Data.Foreign.Generic (encodeJSON)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Either (Either(..))
import Presto.Core.Types.Language.Interaction (Interaction, request)
import Presto.Backend.Types.API (class RestEndpoint,  ErrorPayload(..), ErrorResponse, Response(..), Headers, decodeResponse, makeRequest)
import Presto.Backend.Types.EitherEx
import Presto.Core.Utils.Encoding (defaultDecodeJSON, defaultEncode, defaultDecode)

-- This is done because of lack of instances.
-- TODO: update Presto.Core instead (ErrorResponse should be original)
-- But it might be ErrorResponseEx would also work (it's a Newtype)



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


-- fromErrorResponseEx :: ErrorResponseEx -> ErrorResponse
-- fromErrorResponseEx (ErrorResponseEx rex) = rex

-- fromAPIResultEx :: forall a. APIResultEx a -> APIResult a
-- fromAPIResultEx (APILeft eEx) = Left $ fromErrorResponseEx eEx
-- fromAPIResultEx (APIRight a) = Right a



-- derive instance genericErrorResponseEx :: Generic ErrorResponseEx _
-- instance decodeErrorResponseEx :: Decode ErrorResponseEx where decode = defaultDecode
-- instance encodeErrorResponseEx :: Encode ErrorResponseEx where encode = defaultEncode

-- Either ErrorResponse s
-- derive instance genericAPIResultEx :: Generic (Either ErrorResponse s) _
-- instance decodeAPIResultEx :: Decode s => Decode (Either ErrorResponse s) where decode = defaultDecode
-- instance encodeAPIResultEx :: Encode s => Encode (Either ErrorResponse s) where encode = defaultEncode

-- derive instance genericAPIResult :: Generic (APIResult a) _
-- instance decodeAPIResult :: Decode a => Decode (APIResult a) where decode = defaultDecode
-- instance encodeAPIResult :: Encode a => Encode (APIResult a) where encode = defaultEncode

-- derive instance functorEither :: Functor APIResultEx
-- derive instance genericAPIResultEx :: Generic (APIResultEx a) _
-- instance decodeAPIResultEx :: Decode a => Decode (APIResultEx a) where decode = defaultDecode
-- instance encodeAPIResultEx :: Encode a => Encode (APIResultEx a) where encode = defaultEncode

-- instance aPIResultEq :: Eq s => Eq (Either ErrorResponse s) where
--   eq (Right a) (Right b) = a == b
--   eq (Left ((Response ae))) (Left ((Response be))) =
--     ae.code == be.code
--     && ae.status == be.status
--     && errPayloadEq ae.response be.response
--     where
--       errPayloadEq (ErrorPayload aep) (ErrorPayload bep) =
--         aep.error == bep.error
--         && aep.errorMessage == bep.errorMessage
--         && aep.userMessage == bep.userMessage
--   eq _ _ = false

--instance aPIResultEq :: Eq a => Eq (APIResult a) where
--  eq (Right a) (Right b) = a == b
--  eq (Left ((Response ae))) (Left ((Response be))) =
--    ae.code == be.code
--    && ae.status == be.status
--    && errPayloadEq ae.response be.response
--    where
--      errPayloadEq (ErrorPayload aep) (ErrorPayload bep) =
--        aep.error == bep.error
--        && aep.errorMessage == bep.errorMessage
--        && aep.userMessage == bep.userMessage
--  eq _ _ = false
