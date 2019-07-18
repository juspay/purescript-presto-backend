module Presto.Backend.RunModesSpec where

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVAR, makeVar, readVar)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff.Exception (error, message)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Data.Array (length, index)
import Data.Either (Either(Left, Right), isRight)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Foreign.Generic (encodeJSON)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show as GShow
import Data.Maybe (Maybe(Nothing, Just))
import Data.StrMap as StrMap
import Data.Tuple (Tuple(..))
import Debug.Trace (spy)
import Prelude (class Eq, class Show, Unit, bind, discard, pure, show, unit, ($), (*>), (<>), (==))
import Presto.Backend.Flow (BackendFlow, callAPI, doAffRR, getDBConn, log, runSysCmd, throwException)
import Presto.Backend.Language.Types.DB (MockedSqlConn(MockedSqlConn), SqlConn(MockedSql))
import Presto.Backend.Playback.Entries (CallAPIEntry(..), DoAffEntry(..), LogEntry(..), RunSysCmdEntry(..))
import Presto.Backend.Playback.Types (EntryReplayingMode(..), GlobalReplayingMode(..), PlaybackError(..), PlaybackErrorType(..), RecordingEntry(..))
import Presto.Backend.Runtime.Interpreter (RunningMode(..), runBackend)
import Presto.Backend.Runtime.Types (Connection(..), BackendRuntime(..), RunningMode(..), KVDBRuntime(..))
import Presto.Backend.Types.API (class RestEndpoint, APIResult, Request(..), Headers(..), Response(..), ErrorPayload(..), Method(..), defaultDecodeResponse)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, fail)

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
  -- You can spy the values going through the function:
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

logScript' :: BackendFlow Unit Unit Unit
logScript' = do
  log "logging1.1" "try3 is hitting actual LogRunner"
  log "logging2.1" "try4 is hitting actual LogRunner"

callAPIScript :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
callAPIScript = do
  eRes1 <- callAPI emptyHeaders $ SomeRequest { code: 1, number: 1.0 }
  eRes2 <- callAPI emptyHeaders $ SomeRequest { code: 2, number: 2.0 }
  pure $ Tuple eRes1 eRes2

callAPIScript' :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
callAPIScript' = do
  eRes1 <- callAPI emptyHeaders $ SomeRequest { code: 1, number: 3.0 }
  eRes2 <- callAPI emptyHeaders $ SomeRequest { code: 2, number: 4.0 }
  pure $ Tuple eRes1 eRes2

logAndCallAPIScript :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
logAndCallAPIScript = do
  logScript
  callAPIScript

logAndCallAPIScript' :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
logAndCallAPIScript' = do
  logScript'
  callAPIScript'

runSysCmdScript :: BackendFlow Unit Unit String
runSysCmdScript = runSysCmd "echo 'ABC'"

runSysCmdScript' :: BackendFlow Unit Unit String
runSysCmdScript' = runSysCmd "echo 'DEF'"

doAffScript :: BackendFlow Unit Unit String
doAffScript = doAffRR  (pure  "This is result.")

doAffScript' :: BackendFlow Unit Unit String
doAffScript' = doAffRR (pure "This is result 2.")

testDB :: String
testDB = "TestDB"

dbScript0 :: BackendFlow Unit Unit SqlConn
dbScript0 = getDBConn testDB

mkBackendRuntime :: KVDBRuntime -> RunningMode -> BackendRuntime
mkBackendRuntime kvdbRuntime mode = BackendRuntime
  { apiRunner
  , connections : StrMap.empty
  , logRunner
  , affRunner
  , kvdbRuntime
  , mode
  }

createKVDBRuntime :: forall t184.
  Aff
    ( avar :: AVAR
    | t184
    )
    KVDBRuntime
createKVDBRuntime = do
  multiesVar' <- makeVar StrMap.empty
  pure $ KVDBRuntime
    { multiesVar : multiesVar'
    }

createRegularBackendRuntime :: forall t274.
  Aff
    ( avar :: AVAR
    | t274
    )
    BackendRuntime
createRegularBackendRuntime = do
  kvdbRuntime <- createKVDBRuntime
  pure $ mkBackendRuntime kvdbRuntime RegularMode

createRecordingBackendRuntime = do
  kvdbRuntime  <- createKVDBRuntime
  recordingVar <- makeVar []
  let brt = mkBackendRuntime kvdbRuntime $ RecordingMode { recordingVar , disableEntries : [] }
  pure $ Tuple brt recordingVar

createRecordingBackendRuntimeWithMode entries  = do
    kvdbRuntime <- createKVDBRuntime
    recordingVar <- makeVar []
    let brt = mkBackendRuntime kvdbRuntime $ RecordingMode {recordingVar , disableEntries : entries}
    pure $ Tuple brt recordingVar
createRecordingBackendRuntimeWithEntryMode entryMode = do
  kvdbRuntime  <- createKVDBRuntime
  recordingVar <- makeVar entryMode
  let brt = mkBackendRuntime kvdbRuntime $ RecordingMode { recordingVar , disableEntries : [] }
  pure $ Tuple brt recordingVar


runTests :: Spec _ Unit
runTests = do
  describe "Regular mode tests" do
    it "Log regular mode test" $ do
      brt <- createRegularBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> pure unit

    it "CallAPI regular mode test" $ do
      brt <- createRegularBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt callAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right (Tuple (Tuple eRes1 eRes2) _) -> do
          isRight eRes1 `shouldEqual` true    -- TODO: check particular results
          isRight eRes2 `shouldEqual` false   -- TODO: check particular results

  describe "Recording/replaying mode tests" do
    it "Record test" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> do
          recording <- readVar recordingVar
          length recording `shouldEqual` 4
          index recording 0 `shouldEqual` (Just $ RecordingEntry Normal "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}")
          index recording 1 `shouldEqual` (Just $ RecordingEntry Normal"{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}")
          index recording 2 `shouldEqual` (Just (RecordingEntry Normal "{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"))
          index recording 3 `shouldEqual` (Just (RecordingEntry Normal  "{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"))

    it "Record / replay test: log and callAPI success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 4

    it "Record / replay test: index out of range" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 10
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      pbError  <- readVar errorVar
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just $ PlaybackError
        { errorMessage: "Expected: LogEntry"
        , errorType: UnexpectedRecordingEnd
        })
      curStep `shouldEqual` 10

    it "Record / replay test: started from the middle" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 2
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      pbError  <- readVar errorVar
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just $ PlaybackError { errorMessage: "Expected: LogEntry", errorType: UnknownRRItem })
      curStep `shouldEqual` 3

    it "Record / replay test: runSysCmd success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt runSysCmdScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        _ -> fail $ show eResult

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime runSysCmdScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 1

    it "Record / replay test: throwException success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt $ throwException "This is error!") unit) unit)
      case eResult of
        Left (Tuple err _) -> message err `shouldEqual` "This is error!"
        _ -> fail "Unexpected success."

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime $ throwException "This is error!") unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Left (Tuple err _) -> message err `shouldEqual` "This is error!"
        _ -> fail "Unexpected success."
      curStep `shouldEqual` 1

    it "Record / replay test: doAff success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt doAffScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        _ -> fail $ show eResult

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime doAffScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        Left err -> fail $ show err
      curStep `shouldEqual` 1

    it "Record / replay test: getDBConn success" $ do
      Tuple (BackendRuntime rt') recordingVar <- createRecordingBackendRuntime
      let conns = StrMap.singleton testDB $ SqlConn $ MockedSql $ MockedSqlConn testDB
      let rt = BackendRuntime $ rt' { connections = conns }
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend rt dbScript0) unit) unit)
      case eResult of
        Right (Tuple (MockedSql (MockedSqlConn dbName)) unit) -> dbName `shouldEqual` testDB
        Left err -> fail $ show err
        _ -> fail "Unknown result"

  describe "Recording  test with Global Config Mode" do
    it "Record Test : LogEntry success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntimeWithMode ["LogEntry"]
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> do
          recording <- readVar recordingVar
          length recording `shouldEqual` 2
          index recording 0 `shouldEqual` (Just (RecordingEntry Normal "{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"))
          index recording 1 `shouldEqual` (Just (RecordingEntry Normal  "{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"))

    it "Record Test : CallAPIEntry success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntimeWithMode ["CallAPIEntry"]
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> do
          recording <- readVar recordingVar
          length recording `shouldEqual` 2
          index recording 0 `shouldEqual` (Just $ RecordingEntry Normal "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}")
          index recording 1 `shouldEqual` (Just $ RecordingEntry Normal"{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}")

    it "Record Test: runSysCmd success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntimeWithMode ["RunSysCmdEntry"]
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt runSysCmdScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        _ -> fail "Test failed."

    it "Record test: doAff success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntimeWithMode ["DoAffEntry"]
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt doAffScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        _ -> fail "Test failed."

  describe "Replaying test with disable Verify Global Config Mode" do
    it "Replay test : LogEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : ["LogEntry"]
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logScript') unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 2
    it "Replay test : CallAPIEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt callAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : ["CallAPIEntry"]
              , disableMocking : []
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime callAPIScript') unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 2
  describe "Replaying Test with disableMocking Global Config mode" $ do
    it "Replay Test : LogEntry and CallAPIEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : ["LogEntry","CallAPIEntry"]
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
      curStep  <- readVar stepVar
      curStep `shouldEqual` 4

    it "Replay Test : DoAffEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt doAffScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        _ -> fail $ show eResult

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : affRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : ["DoAffEntry"]
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime doAffScript') unit) unit)
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "This is result 2."
        _ -> fail $ show eResult

      curStep  <- readVar stepVar
      curStep `shouldEqual` 1
    it "Replay test: runSysCmd success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt runSysCmdScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        _ -> fail $ show eResult

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { recording
              , disableVerify : []
              , disableMocking : ["RunSysCmdEntry"]
              , stepVar
              , errorVar
              }
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime runSysCmdScript') unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "DEF\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 1

  describe "Replaying Test in Entry config Mode" do
      it "Replay Test in Normal Entry Mode : Log and CallAPI" $ do
        let entryMode = [
                         RecordingEntry Normal "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}"
                        ,RecordingEntry Normal "{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}"
                        ,RecordingEntry Normal "{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        ,RecordingEntry Normal "{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request:                  {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : failingApiRunner
              , connections : StrMap.empty
              , logRunner   : failingLogRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { recording
                , disableVerify : []
                , disableMocking : []
                , stepVar
                , errorVar
                }
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4

      it "Replay Test in NoVerify Entry Mode : Log and CallAPI disable LogEntry" $ do
        let entryMode = [ RecordingEntry NoVerify "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}"
                        , RecordingEntry NoVerify "{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}"
                        , RecordingEntry NoVerify "{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        , RecordingEntry NoVerify "{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request:                  {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : failingApiRunner
              , connections : StrMap.empty
              , logRunner   : failingLogRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { recording
                , disableVerify : []
                , disableMocking : ["LogEntry"]  -- This will have no efect since the priority of Entry Configs are higher than Global Config
                , stepVar
                , errorVar
                }
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4

      it "Replay Test in NoVerify Entry Mode : Log and CallAPI" $ do
        let entryMode = [ RecordingEntry NoMock "{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"}"
                        , RecordingEntry NoMock "{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"}"
                        , RecordingEntry NoMock "{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        , RecordingEntry NoMock "{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request:                  {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}}"
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : apiRunner
              , connections : StrMap.empty
              , logRunner   : logRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { recording
                , disableVerify : []
                , disableMocking : []
                , stepVar
                , errorVar
                }
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4
