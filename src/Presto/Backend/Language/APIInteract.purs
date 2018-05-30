module Presto.Backend.Language.APIInteract
  ( apiInteract
  ) where

import Prelude
import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Data.Foreign (ForeignError(..))
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.List.Lazy.NonEmpty (NonEmptyList(..))
import Presto.Backend.Types.API (class RestEndpoint, ErrorPayload(..), ErrorResponse, Response(..), Headers, decodeResponse, makeRequest)
import Presto.Backend.Types.Language.Interaction (Interaction, request)
import Presto.Backend.Utils.Encoding (defaultDecodeJSON)


apiInteract :: forall a b.
  Encode a => Decode b => RestEndpoint a b
  => a -> Headers -> Interaction (Either (NonEmptyList ForeignError) b)
apiInteract a headers = do
  fgnOut <- request (encode (makeRequest a headers))
  pure $ runExcept (decodeResponse fgnOut)
    -- -- Try to decode the server's resopnse into the expected type
    -- Right resp -> Right resp
    -- Left x -> Left $ case runExcept (decode fgnOut >>= defaultDecodeJSON) of
    --                    -- See if the server sent an error response, else create our own
    --                    Right e@(Response _) -> e
    --                    Left y -> Response { code: 0
    --                                       , status: ""
    --                                       , response: ErrorPayload { error: true
    --                                                                , errorMessage: show x <> "\n" <> show y
    --                                                                , userMessage: "Unknown error"
    --                                                                }
    --                                       }
