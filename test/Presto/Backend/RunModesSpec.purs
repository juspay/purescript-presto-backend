module Presto.Backend.RunModesSpec where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Data.Tuple (Tuple(..))
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Map as Map
import Data.Either (Either(..), isLeft, isRight)
import Data.StrMap as StrMap
import Debug.Trace (spy)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, fail)

import Presto.Backend.Flow (BackendFlow, log, callAPI)
import Presto.Backend.Interpreter (BackendRuntime(..), Connection(..), RunningMode (..), runBackend)
import Presto.Backend.APIInteractEx (ErrorResponseEx (..))

import Presto.Core.Types.Language.Flow (APIResult)
import Presto.Core.Types.API (class RestEndpoint, Request(..), Headers(..), ErrorResponse, Response(..), ErrorPayload(..), Method(..), defaultDecodeResponse)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)

data SomeRequest = SomeRequest
  { code   :: Int
  , number :: Number
  }

data SomeResponse = SomeResponse
  { code      :: Int
  , string :: String
  }

derive instance genericSomeRequest :: Generic SomeRequest _
derive instance eqSomeRequest      :: Eq      SomeRequest
instance showSomeRequest           :: Show    SomeRequest where show   = GShow.genericShow
instance decodeSomeRequest         :: Decode  SomeRequest where decode = defaultDecode
instance encodeSomeRequest         :: Encode  SomeRequest where encode = defaultEncode

derive instance genericSomeResponse :: Generic SomeResponse _
derive instance eqSomeResponse      :: Eq      SomeResponse
instance showSomeResponse           :: Show    SomeResponse where show   = GShow.genericShow
instance decodeSomeResponse         :: Decode  SomeResponse where decode = defaultDecode
instance encodeSomeResponse         :: Encode  SomeResponse where encode = defaultEncode

instance someRestEndpoint :: RestEndpoint SomeRequest SomeResponse where
  makeRequest r@(SomeRequest req) h = Request
    { method : GET
    , url : show req.code
    , payload : encodeJSON r
    , headers : h
    }
  -- decodeResponse resp = const (defaultDecodeResponse resp) $ spy resp
  decodeResponse = defaultDecodeResponse

logRunner :: forall a. String -> a -> Aff _ Unit
logRunner tag value = pure (spy tag) *> pure (spy value) *> pure unit

apiRunner :: forall e. Request -> Aff e String
apiRunner r@(Request req)
  | req.url == "1" = pure $ encodeJSON $ SomeResponse { code: 1, string: "Hello there!" }
apiRunner r
  | true = pure $ encodeJSON $ ErrorResponseEx $ Response
    { code: 400
    , status: "Unknown request: " <> encodeJSON r
    , response: ErrorPayload
        { error: true
        , errorMessage: "Unknown request: " <> encodeJSON r
        , userMessage: "Unknown request"
        }
    }

emptyHeaders :: Headers
emptyHeaders = Headers []

logScript :: BackendFlow Unit Unit Unit
logScript = do
  log "logging1" "try1"
  log "logging2" "try2"

callAPIScript :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
callAPIScript = do
  eRes1 <- callAPI emptyHeaders $ SomeRequest { code: 1, number: 1.0 }
  eRes2 <- callAPI emptyHeaders $ SomeRequest { code: 2, number: 2.0 }
  pure $ Tuple eRes1 eRes2


runTests :: Spec _ Unit
runTests = do
  describe "Regular mode tests" do
    it "Log regular mode test" $ do
      let backendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , mode        : RegularMode
            }
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntime logScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> pure unit

    it "CallAPI regular mode test" $ do
      let backendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , mode        : RegularMode
            }
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntime callAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right (Tuple (Tuple eRes1 eRes2) _) -> do
          isRight eRes1 `shouldEqual` true    -- TODO: check particular results
          isRight eRes2 `shouldEqual` false   -- TODO: check particular results
