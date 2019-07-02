module Presto.Backend.APIInteract
  (
   apiInteract
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
