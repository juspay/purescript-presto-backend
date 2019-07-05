module Presto.Backend.RunModesSpec where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Eff.Exception (error)
import Data.Array (length, index)
import Data.Tuple (Tuple(..))
import Data.Maybe (Maybe(..), isJust)
import Data.Either (Either(..), isLeft, isRight)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericDecodeJSON, genericEncode, genericEncodeJSON, encodeJSON, decodeJSON)
import Data.Foreign.Generic.Class (class GenericDecode, class GenericEncode)
import Data.Foreign.Class (class Encode, class Decode, encode, decode)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq as GEq
import Data.Generic.Rep.Show as GShow
import Data.Generic.Rep.Ord as GOrd
import Data.Map as Map
import Data.StrMap as StrMap
import Debug.Trace (spy)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, fail)

import Presto.Backend.Flow (BackendFlow, log, callAPI, runSysCmd, doAffRR)
import Presto.Backend.Interpreter (BackendRuntime(..), Connection(..), RunningMode(..), runBackend)
import Presto.Backend.Playback.Types (RecordingEntry(..), PlaybackError(..), PlaybackErrorType(..))
import Presto.Backend.Types.API (class RestEndpoint, APIResult, Request(..), Headers(..), Response(..), ErrorPayload(..), Method(..), defaultDecodeResponse)
import Presto.Backend.Types.EitherEx
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

failingLogRunner :: forall a. String -> a -> Aff _ Unit
failingLogRunner tag value = throwError $ error "Logger should not be called."

failingApiRunner :: forall e. Request -> Aff e String
failingApiRunner _ = throwError $ error "API Runner should not be called."

-- TODO: lazy?
failingAffRunner :: forall a. Aff _ a -> Aff _ a
failingAffRunner _ = throwError $ error "Aff Runner should not be called."

apiRunner :: forall e. Request -> Aff e String
apiRunner r@(Request req)
  | req.url == "1" = pure $ encodeJSON $ SomeResponse { code: 1, string: "Hello there!" }
apiRunner r
  | true = pure $ encodeJSON $  Response
    { code: 400
    , status: "Unknown request: " <> encodeJSON r
    , response: ErrorPayload
        { error: true
        , errorMessage: "Unknown request: " <> encodeJSON r
        , userMessage: "Unknown request"
        }
    }

-- TODO: lazy?
affRunner :: forall a. Aff _ a -> Aff _ a
affRunner aff = aff

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

logAndCallAPIScript :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
logAndCallAPIScript = do
  logScript
  callAPIScript

runSysCmdScript :: BackendFlow Unit Unit String
runSysCmdScript = runSysCmd "echo 'ABC'"

doAffScript :: BackendFlow Unit Unit String
doAffScript = doAffRR (pure "This is result.")

runTests :: Spec _ Unit
runTests = do
  let backendRuntime mode = BackendRuntime
        { apiRunner   : apiRunner
        , connections : StrMap.empty
        , logRunner   : logRunner
        , affRunner   : affRunner
        , mode        : mode
        }
  let backendRuntimeRegular = backendRuntime RegularMode

  describe "Regular mode tests" do
    it "Log regular mode test" $ do
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRegular logScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> pure unit

    it "CallAPI regular mode test" $ do
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRegular callAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right (Tuple (Tuple eRes1 eRes2) _) -> do
          isRight eRes1 `shouldEqual` true    -- TODO: check particular results
          isRight eRes2 `shouldEqual` false   -- TODO: check particular results

  describe "Recording/replaying mode tests" do
    it "Record test" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef , disableEntries : ["",""]}
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording logAndCallAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> do
          recording <- liftEff $ readRef recordingRef
          length recording.entries `shouldEqual` 4
          index recording.entries 0 `shouldEqual` (Just $ RecordingEntry "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}")
          index recording.entries 1 `shouldEqual` (Just $ RecordingEntry "{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}")
          index recording.entries 2 `shouldEqual` (Just $ RecordingEntry "{\"mode\":\"Normal\",\"jsonResult\":{\"contents\":\"{\\\"string\\\":\\\"Hello there!\\\",\\\"code\\\":1}\",\"tag\":\"RightEx\"},\"jsonRequest\":\"{\\\"url\\\":\\\"1\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":1,\\\\\\\"code\\\\\\\":1}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\"}"
            )
          index recording.entries 3 `shouldEqual` (Just $ RecordingEntry "{\"mode\":\"Normal\",\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":\"{\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\"}"
            )

    it "Record / replay test: log and callAPI success" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef , disableEntries : ["","Log"]}
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepRef   <- liftEff $ newRef 0
      errorRef  <- liftEff $ newRef Nothing
      recording <- liftEff $ readRef recordingRef
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , mode        : ReplayingMode
              { recording
              , stepRef
              , errorRef
              , disableVerify : [""]
              , disableMocking : [""]
              , skip : ["CallAPIEntry"]
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- liftEff $ readRef stepRef
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 4

    it "Record / replay test: index out of range" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef, disableEntries : ["callApi","Log"] }
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepRef   <- liftEff $ newRef 10
      errorRef  <- liftEff $ newRef Nothing
      recording <- liftEff $ readRef recordingRef
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , mode        : ReplayingMode
              { recording
              , stepRef
              , errorRef
              , disableVerify : []
              , disableMocking : []
              , skip : []
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- liftEff $ readRef stepRef
      pbError  <- liftEff $ readRef errorRef
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just $ PlaybackError
        { errorMessage: "Expected: LogEntry"
        , errorType: UnexpectedRecordingEnd
        })
      curStep `shouldEqual` 10

    it "Record / replay test: started from the middle" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef, disableEntries : ["callApi","Log"] }
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepRef   <- liftEff $ newRef 2
      errorRef  <- liftEff $ newRef Nothing
      recording <- liftEff $ readRef recordingRef
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , mode        : ReplayingMode
              { recording
              , stepRef
              , errorRef
              , disableVerify : []
              , disableMocking : []
              , skip : []
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- liftEff $ readRef stepRef
      pbError  <- liftEff $ readRef errorRef
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just $ PlaybackError { errorMessage: "Expected: LogEntry", errorType: UnknownRRItem })
      curStep `shouldEqual` 3

    it "Record / replay test: runSysCmd success" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef , disableEntries : ["callApi","Log"]}
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording runSysCmdScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        _ -> fail $ show eResult

      stepRef   <- liftEff $ newRef 0
      errorRef  <- liftEff $ newRef Nothing
      recording <- liftEff $ readRef recordingRef
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , mode        : ReplayingMode
              { recording
              , stepRef
              , errorRef
              , disableVerify : []
              , disableMocking : []
              , skip : []
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime runSysCmdScript) unit) unit)
      curStep  <- liftEff $ readRef stepRef
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 1

    it "Record / replay test: doAff success" $ do
      recordingRef <- liftEff $ newRef { entries : [] }
      let backendRuntimeRecording = backendRuntime $ RecordingMode { recordingRef ,  disableEntries : ["callApi","Log"]}
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend backendRuntimeRecording doAffScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        _ -> fail $ show eResult

      stepRef   <- liftEff $ newRef 0
      errorRef  <- liftEff $ newRef Nothing
      recording <- liftEff $ readRef recordingRef
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , mode        : ReplayingMode
              { recording
              , stepRef
              , errorRef
              , disableVerify : []
              , disableMocking : []
              , skip : []
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime doAffScript) unit) unit)
      curStep  <- liftEff $ readRef stepRef
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        Left err -> fail $ show err
      curStep `shouldEqual` 1
