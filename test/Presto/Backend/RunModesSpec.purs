module Presto.Backend.RunModesSpec where

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVAR, AVar, makeVar, readVar)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff.Exception (error, message)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except.Trans (runExceptT)
import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (runStateT)
import Data.Array (length, index)
import Data.Either (Either(Left, Right), isRight)
import Data.Foreign (Foreign, F)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Foreign.Generic (encodeJSON, decodeJSON)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show as GShow
import Data.Maybe (Maybe(Nothing, Just))
import Data.StrMap as StrMap
import Data.Tuple (Tuple(..))
import Data.Traversable (traverse)
import Debug.Trace (spy)
import Prelude (class Eq, class Show, Unit, (<$>), bind, discard, pure, show, unit, ($), (*>), (<>), (==), id)
import Presto.Backend.Flow (BackendFlow, getOption, setOption, forkFlow, forkFlow', generateGUID, generateGUID', callAPI, doAffRR, getDBConn, log, runSysCmd, throwException)
import Presto.Backend.Language.Types.DB (MockedSqlConn(MockedSqlConn), SqlConn(MockedSql))
import Presto.Backend.Playback.Entries (CallAPIEntry(..), DoAffEntry(..), LogEntry(..), RunSysCmdEntry(..))
import Presto.Backend.Playback.Types (RecordingEntries, EntryReplayingMode(..), GlobalReplayingMode(..), PlaybackError(..), PlaybackErrorType(..), RecordingEntry(..))
import Presto.Backend.Runtime.Interpreter (RunningMode(..), runBackend)
import Presto.Backend.Runtime.Types (Connection(..), BackendRuntime(..), RunningMode(..), KVDBRuntime(..))
import Presto.Backend.Types.API (class RestEndpoint, APIResult, Request(..), Headers(..), Response(..), ErrorPayload(..), Method(..), defaultDecodeResponse)
import Presto.Backend.Types.Options (class OptionEntity)
import Presto.Core.Utils.Encoding (defaultEncode, defaultDecode)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, fail)
import Data.Foreign.Generic.EnumEncoding (class GenericDecodeEnum, class GenericEncodeEnum, genericDecodeEnum, genericEncodeEnum)
import Data.Ord

defaultEnumDecode :: forall a b. Generic a b => GenericDecodeEnum b => Foreign -> F a
defaultEnumDecode x = genericDecodeEnum { constructorTagTransform: id } x

defaultEnumEncode ::  forall a b. Generic a b => GenericEncodeEnum b => a -> Foreign
defaultEnumEncode x = genericEncodeEnum { constructorTagTransform: id } x

data Gateway = GwA | GwB | GwC
data GatewayKey = GatewayKey String

derive instance genericGatewayKey :: Generic GatewayKey _
instance decodeGatewaykey :: Decode GatewayKey where decode = defaultDecode
instance encodeGatewaykey :: Encode GatewayKey where encode = defaultEncode

derive instance eqGateway :: Eq Gateway
derive instance ordGateway :: Ord Gateway
derive instance genericGateway :: Generic Gateway _
instance showGateway :: Show Gateway where show = GShow.genericShow
instance decodeGateway :: Decode Gateway where decode = defaultEnumDecode
instance encodeGateway :: Encode Gateway where encode = defaultEnumEncode

instance optionGateway :: OptionEntity GatewayKey Gateway where

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

optionsV :: StrMap.StrMap String
optionsV = StrMap.insert (encodeJSON $ GatewayKey "explicitGWB") (encodeJSON GwB) $ StrMap.singleton (encodeJSON $ GatewayKey "explicitGWA") "\"GwA\""

mkOptions = makeVar optionsV

emptyHeaders :: Headers
emptyHeaders = Headers []

logScript :: BackendFlow Unit Unit Unit
logScript = do
  log "logging1" "try1"
  log "logging2" "try2"

log1 = "{\"contents\":{\"tag\":\"logging1\",\"message\":\"\\\"try1\\\"\"},\"tag\":\"LogEntry\"}"
log2 = "{\"contents\":{\"tag\":\"logging2\",\"message\":\"\\\"try2\\\"\"},\"tag\":\"LogEntry\"}"

logScript' :: BackendFlow Unit Unit Unit
logScript' = do
  log "logging1.1" "try3 is hitting actual LogRunner"
  log "logging2.1" "try4 is hitting actual LogRunner"

callAPIScript :: BackendFlow Unit Unit (Tuple (APIResult SomeResponse) (APIResult SomeResponse))
callAPIScript = do
  eRes1 <- callAPI emptyHeaders $ SomeRequest { code: 1, number: 1.0 }
  eRes2 <- callAPI emptyHeaders $ SomeRequest { code: 2, number: 2.0 }
  pure $ Tuple eRes1 eRes2

capi1 = "{\"contents\":{\"jsonResult\":{\"contents\":{\"string\":\"Hello there!\",\"code\":1},\"tag\":\"RightEx\"},\"jsonRequest\":{\"url\":\"1\",\"payload\":\"{\\\"number\\\":1,\\\"code\\\":1}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}},\"tag\":\"CallAPIEntry\"}"
capi2 = "{\"contents\":{\"jsonResult\":{\"contents\":{\"status\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"response\":{\"userMessage\":\"Unknown request\",\"errorMessage\":\"Unknown request: {\\\"url\\\":\\\"2\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":2,\\\\\\\"code\\\\\\\":2}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}\",\"error\":true},\"code\":400},\"tag\":\"LeftEx\"},\"jsonRequest\":{\"url\":\"2\",\"payload\":\"{\\\"number\\\":2,\\\"code\\\":2}\",\"method\":{\"tag\":\"GET\"},\"headers\":[]}},\"tag\":\"CallAPIEntry\"}"

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
doAffScript = doAffRR (pure  "This is result.")

doAffScript' :: BackendFlow Unit Unit String
doAffScript' = doAffRR (pure "This is result 2.")

testDB :: String
testDB = "TestDB"

dbScript0 :: BackendFlow Unit Unit SqlConn
dbScript0 = getDBConn testDB

skipScript1 :: BackendFlow Unit Unit String
skipScript1 = do
  _ <- runSysCmd "echo 'abcde'"
  _ <- doAffRR (pure "doAffRR result")
  runSysCmd "echo 'fghij'"

skipScript2 :: BackendFlow Unit Unit String
skipScript2 = do
  _ <- runSysCmd "echo 'abcde'"
  runSysCmd "echo 'fghij'"

forkFlowScript :: BackendFlow Unit Unit String
forkFlowScript = do
  _ <- doAffRR (pure "doAff from main flow")
  _ <- forkFlow' "Child 1" $ do
          _ <- doAffRR (pure "doAff 1 from forkFlow")
          _ <- doAffRR (pure "doAff 2 from forkFlow")
          _ <- runSysCmd "sleep 0.5s"
          _ <- doAffRR (pure "doAff 3 from forkFlow")
          _ <- doAffRR (pure "doAff 4 from forkFlow")
          _ <- runSysCmd "sleep 1s"
          _ <- doAffRR (pure "doAff 5 from forkFlow")
          doAffRR (pure "doAff 6 from forkFlow")
  _ <- doAffRR (pure "doAff from main flow")
  _ <- runSysCmd "echo 'mainflow 1'"
  _ <- runSysCmd "echo 'mainflow 2'"
  _ <- forkFlow' "Child 2" $ do
          _ <- doAffRR (pure "doAff 1 from forkFlow 2")
          _ <- forkFlow' "Child 2 Child 1" $ do
                _ <- doAffRR (pure "doAff 1 from forkFlow Child 2 Child 1")
                _ <- doAffRR (pure "doAff 2 from forkFlow Child 2 Child 1")
                doAffRR (pure "doAff 3 from forkFlow Child 2 Child 1")
          _ <- doAffRR (pure "doAff 2 from forkFlow 2")
          _ <- runSysCmd "sleep 0.5s"
          _ <- doAffRR (pure "doAff 3 from forkFlow 2")
          _ <- doAffRR (pure "doAff 4 from forkFlow 2")
          _ <- runSysCmd "sleep 1s"
          _ <- doAffRR (pure "doAff 5 from forkFlow 2")
          doAffRR (pure "doAff 6 from forkFlow 2")
  _ <- runSysCmd "sleep 0.5s"
  _ <- runSysCmd "echo 'mainflow 3'"
  _ <- runSysCmd "echo 'mainflow 4'"
  _ <- runSysCmd "sleep 0.5s"
  _ <- runSysCmd "echo 'mainflow 5'"
  runSysCmd "echo 'mainflow 6'"

getOptionScript :: BackendFlow Unit Unit (Tuple (Maybe Gateway) (Maybe Gateway))
getOptionScript = do
  gwa <- getOption $ GatewayKey "explicitGWA"
  gwb <- getOption $ GatewayKey "explicitGWB"
  pure $ Tuple gwa gwb

setOptionScript :: BackendFlow Unit Unit (Maybe Gateway)
setOptionScript = do
  setOption (GatewayKey  "explicitGWC") GwC
  getOption $ GatewayKey "explicitGWC"

mkBackendRuntime :: AVar (StrMap.StrMap String) -> KVDBRuntime -> RunningMode -> BackendRuntime
mkBackendRuntime options kvdbRuntime mode = BackendRuntime
  { apiRunner
  , connections : StrMap.empty
  , logRunner
  , affRunner
  , kvdbRuntime
  , mode
  , options
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
  options <-mkOptions
  pure $ mkBackendRuntime options kvdbRuntime RegularMode

createRecordingBackendRuntimeForked
  :: forall eff
   . Aff ( avar :: AVAR | eff )
      { brt :: BackendRuntime
      , recordingVar :: AVar RecordingEntries
      , forkedRecordingsVar :: AVar (StrMap.StrMap (AVar RecordingEntries))
      }
createRecordingBackendRuntimeForked = do
  kvdbRuntime  <- createKVDBRuntime
  recordingVar <- makeVar []
  options <- mkOptions
  forkedRecordingsVar <- makeVar StrMap.empty
  let brt = mkBackendRuntime options kvdbRuntime $ RecordingMode
        { flowGUID : ""
        , recordingVar
        , forkedRecordingsVar
        , disableEntries : []
        }
  pure { brt, recordingVar, forkedRecordingsVar }

createRecordingBackendRuntime
  :: forall eff
   . Aff ( avar :: AVAR | eff ) (Tuple BackendRuntime (AVar (Array RecordingEntry)))
createRecordingBackendRuntime = do
  kvdbRuntime  <- createKVDBRuntime
  recordingVar <- makeVar []
  forkedRecordingsVar <- makeVar StrMap.empty
  options <- mkOptions
  let brt = mkBackendRuntime options kvdbRuntime $ RecordingMode
        { flowGUID : ""
        , recordingVar
        , forkedRecordingsVar
        , disableEntries : []
        }
  pure $ Tuple brt recordingVar

createRecordingBackendRuntimeWithMode entries  = do
    kvdbRuntime <- createKVDBRuntime
    recordingVar <- makeVar []
    forkedRecordingsVar <- makeVar StrMap.empty
    options <- mkOptions
    let brt = mkBackendRuntime options kvdbRuntime $ RecordingMode
          { flowGUID : ""
          , recordingVar
          , forkedRecordingsVar
          , disableEntries : entries
          }
    pure $ Tuple brt recordingVar

createRecordingBackendRuntimeWithEntryMode entryMode = do
  kvdbRuntime  <- createKVDBRuntime
  recordingVar <- makeVar entryMode
  forkedRecordingsVar <- makeVar StrMap.empty
  options <- mkOptions
  let brt = mkBackendRuntime options kvdbRuntime $ RecordingMode
        { flowGUID : ""
        , forkedRecordingsVar
        , recordingVar
        , disableEntries : []
        }
  pure $ Tuple brt recordingVar


runTests :: Spec _ Unit
runTests = do
  describe "Options test" do
    it "getOption test" $ do
      brt <- createRegularBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt getOptionScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right (Tuple (Tuple gwa gwb) unit) -> do
          gwa `shouldEqual` (Just GwA)
          gwb `shouldEqual` (Just GwB)

    it "setOption test" $ do
      brt <- createRegularBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt setOptionScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right (Tuple gwc unit) -> gwc `shouldEqual` Just GwC

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
          index recording 0 `shouldEqual` (Just $ RecordingEntry 0 Normal "LogEntry" log1 )
          index recording 1 `shouldEqual` (Just $ RecordingEntry 1 Normal "LogEntry" log2 )
          index recording 2 `shouldEqual` (Just (RecordingEntry 2 Normal  "CallAPIEntry" capi1 ))
          index recording 3 `shouldEqual` (Just (RecordingEntry 3 Normal  "CallAPIEntry" capi2 ))

    it "Record / replay test: log and callAPI success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      case [eResult, eResult2] of
        [Right res, Right res2] -> res `shouldEqual` res2
        _ -> fail "Not equal."
      curStep `shouldEqual` 4
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

    it "Record / replay test: index out of range" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 10
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      pbError  <- readVar errorVar
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just (PlaybackError
        { errorMessage: "\n    Flow step: tag: logging1, message: \"try1\""
        , errorType: UnexpectedRecordingEnd
        }))
      curStep `shouldEqual` 10

    it "Record / replay test: started from the middle" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 2
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
      curStep  <- readVar stepVar
      pbError  <- readVar errorVar
      isRight eResult2 `shouldEqual` false
      pbError `shouldEqual` (Just (PlaybackError { errorMessage: "\n    Flow step: tag: logging1, message: \"try1\"\n    Recording entry: (RecordingEntry 2 Normal \"CallAPIEntry\" \"{\\\"contents\\\":{\\\"jsonResult\\\":{\\\"contents\\\":{\\\"string\\\":\\\"Hello there!\\\",\\\"code\\\":1},\\\"tag\\\":\\\"RightEx\\\"},\\\"jsonRequest\\\":{\\\"url\\\":\\\"1\\\",\\\"payload\\\":\\\"{\\\\\\\"number\\\\\\\":1,\\\\\\\"code\\\\\\\":1}\\\",\\\"method\\\":{\\\"tag\\\":\\\"GET\\\"},\\\"headers\\\":[]}},\\\"tag\\\":\\\"CallAPIEntry\\\"}\")", errorType: UnknownRRItem }))
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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime runSysCmdScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "ABC\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 1

      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime $ throwException "This is error!") unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Left (Tuple err _) -> message err `shouldEqual` "This is error!"
        _ -> fail "Unexpected success."
      curStep `shouldEqual` 1

      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime doAffScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "This is result."
        Left err -> fail $ show err
      curStep `shouldEqual` 1

      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

    it "Record / replay test: forkFlow no forked entries" $ do
      {brt, recordingVar, forkedRecordingsVar} <- createRecordingBackendRuntimeForked
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt forkFlowScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "mainflow 6\n"
        _ -> fail $ show eResult

      stepVar           <- makeVar 0
      errorVar          <- makeVar Nothing
      recording         <- readVar recordingVar
      kvdbRuntime       <- createKVDBRuntime
      forkedRecordings' <- readVar forkedRecordingsVar

      let kvFunc (Tuple k recVar) = Tuple k <$> readVar recVar
      let (kvs :: Array (Tuple String (AVar RecordingEntries))) = StrMap.toUnfoldable forkedRecordings'
      forkedRecordings'' <- traverse kvFunc kvs
      let forkedRecordings = StrMap.fromFoldable forkedRecordings''

      length recording `shouldEqual` 16
      StrMap.size forkedRecordings `shouldEqual` 3

      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime forkFlowScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "mainflow 6\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 16
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing
      forkedErrs <- readVar forkedFlowErrorsVar
      StrMap.size forkedErrs `shouldEqual` 2

    it "Record / replay test: forkFlow success" $ do
      {brt, recordingVar, forkedRecordingsVar} <- createRecordingBackendRuntimeForked
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt forkFlowScript) unit) unit)
      case eResult of
        Right (Tuple n unit) -> n `shouldEqual` "mainflow 6\n"
        _ -> fail $ show eResult

      stepVar           <- makeVar 0
      errorVar          <- makeVar Nothing
      recording         <- readVar recordingVar
      kvdbRuntime       <- createKVDBRuntime
      forkedRecordings' <- readVar forkedRecordingsVar

      let kvFunc (Tuple k recVar) = Tuple k <$> readVar recVar
      let (kvs :: Array (Tuple String (AVar RecordingEntries))) = StrMap.toUnfoldable forkedRecordings'
      forkedRecordings'' <- traverse kvFunc kvs
      let forkedRecordings = StrMap.fromFoldable forkedRecordings''

      length recording `shouldEqual` 16
      StrMap.size forkedRecordings `shouldEqual` 3

      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : forkedRecordings
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime forkFlowScript) unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "mainflow 6\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 16
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing
      forkedErrs <- readVar forkedFlowErrorsVar
      StrMap.size forkedErrs `shouldEqual` 0

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
          index recording 0 `shouldEqual` (Just (RecordingEntry 0 Normal "CallAPIEntry" capi1))
          index recording 1 `shouldEqual` (Just (RecordingEntry 1 Normal "CallAPIEntry" capi2 ))

    it "Record Test : CallAPIEntry success" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntimeWithMode ["CallAPIEntry"]
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      case eResult of
        Left err -> fail $ show err
        Right _  -> do
          recording <- readVar recordingVar
          length recording `shouldEqual` 2
          index recording 0 `shouldEqual` (Just $ RecordingEntry 0 Normal  "LogEntry" log1 )
          index recording 1 `shouldEqual` (Just $ RecordingEntry 1 Normal  "LogEntry" log2 )

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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : ["LogEntry"]
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logScript') unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 2
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

    it "Replay test : CallAPIEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt callAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : ["CallAPIEntry"]
              , disableMocking : []
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime callAPIScript') unit) unit)
      curStep  <- readVar stepVar
      isRight eResult2 `shouldEqual` true
      curStep `shouldEqual` 2
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

  describe "Replaying Test with disableMocking Global Config mode" $ do
    it "Replay Test : LogEntry and CallAPIEntry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt logAndCallAPIScript) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : ["LogEntry","CallAPIEntry"]
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
      curStep  <- readVar stepVar
      curStep `shouldEqual` 4
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : affRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : ["DoAffEntry"]
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime doAffScript') unit) unit)
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing
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
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : failingApiRunner
            , connections : StrMap.empty
            , logRunner   : failingLogRunner
            , affRunner   : failingAffRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : ["RunSysCmdEntry"]
              , skipEntries : []
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime runSysCmdScript') unit) unit)
      curStep  <- readVar stepVar
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "DEF\n"
        Left err -> fail $ show err
      curStep `shouldEqual` 1
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing

  describe "Replaying Test in Entry config Mode" do
      it "Replay Test in Normal Entry Mode : Log and CallAPI" $ do
        let entryMode = [ RecordingEntry 0 Normal  "LogEntry" log1
                        , RecordingEntry 1 Normal  "LogEntry" log2
                        , RecordingEntry 2 Normal  "CallAPIEntry" capi1
                        , RecordingEntry 3 Normal  "CallAPIEntry" capi2
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        forkedFlowErrorsVar <- makeVar StrMap.empty
        options <- mkOptions
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : failingApiRunner
              , connections : StrMap.empty
              , logRunner   : failingLogRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { flowGUID : ""
                , forkedFlowRecordings : StrMap.empty
                , forkedFlowErrorsVar
                , recording
                , disableVerify : []
                , disableMocking : []
                , skipEntries : []
                , entriesFiltered : false
                , stepVar
                , errorVar
                }
                , options
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript) unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4
        mbErr <- readVar errorVar
        mbErr `shouldEqual` Nothing

      it "Replay Test in NoVerify Entry Mode : Log and CallAPI disable LogEntry" $ do
        let entryMode = [ RecordingEntry 0 NoVerify  "LogEntry" log1
                        , RecordingEntry 1 NoVerify  "LogEntry" log2
                        , RecordingEntry 2 NoVerify  "CallAPIEntry" capi1
                        , RecordingEntry 3 NoVerify  "CallAPIEntry" capi2
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        forkedFlowErrorsVar <- makeVar StrMap.empty
        options <- mkOptions
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : failingApiRunner
              , connections : StrMap.empty
              , logRunner   : failingLogRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { flowGUID : ""
                , forkedFlowRecordings : StrMap.empty
                , forkedFlowErrorsVar
                , recording
                , disableVerify : []
                , disableMocking : ["LogEntry"]  -- This will have no efect since the priority of Entry Configs are higher than Global Config
                , skipEntries : []
                , entriesFiltered : false
                , stepVar
                , errorVar
                }
                , options
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4
        mbErr <- readVar errorVar
        mbErr `shouldEqual` Nothing

      it "Replay Test in NoMock Entry Mode : Log and CallAPI" $ do
        let entryMode = [ RecordingEntry 0 NoMock  "LogEntry" log1
                        , RecordingEntry 1 NoMock  "LogEntry" log2
                        , RecordingEntry 2 NoMock  "CallAPIEntry" capi1
                        , RecordingEntry 3 NoMock  "CallAPIEntry" capi2
                        ]
        Tuple brt recordingVar <- createRecordingBackendRuntimeWithEntryMode entryMode
        stepVar     <- makeVar 0
        errorVar    <- makeVar Nothing
        recording   <- readVar recordingVar
        kvdbRuntime <- createKVDBRuntime
        forkedFlowErrorsVar <- makeVar StrMap.empty
        options <- mkOptions
        let replayingBackendRuntime = BackendRuntime
              { apiRunner   : apiRunner
              , connections : StrMap.empty
              , logRunner   : logRunner
              , affRunner   : failingAffRunner
              , kvdbRuntime
              , mode        : ReplayingMode
                { flowGUID : ""
                , forkedFlowRecordings : StrMap.empty
                , forkedFlowErrorsVar
                , recording
                , disableVerify : []
                , disableMocking : []
                , skipEntries : []
                , entriesFiltered : false
                , stepVar
                , errorVar
                }
                , options
              }
        eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime logAndCallAPIScript') unit) unit)
        curStep  <- readVar stepVar
        curStep `shouldEqual` 4
        mbErr <- readVar errorVar
        mbErr `shouldEqual` Nothing

  describe "Replaying Test with SkipGlobal Config mode" $ do
    it "Replay Test : SkipScript - filter entry" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt skipScript1) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , affRunner   : affRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : ["DoAffEntry"]
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime skipScript2) unit) unit)
      curStep  <- readVar stepVar
      curStep `shouldEqual` 2
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "fghij\n"
        Left  err -> fail $ show err

    it "Replay Test : SkipScript - ignore method in flow" $ do
      Tuple brt recordingVar <- createRecordingBackendRuntime
      eResult <- liftAff $ runExceptT (runStateT (runReaderT (runBackend brt skipScript2) unit) unit)
      isRight eResult `shouldEqual` true

      stepVar     <- makeVar 0
      errorVar    <- makeVar Nothing
      recording   <- readVar recordingVar
      kvdbRuntime <- createKVDBRuntime
      forkedFlowErrorsVar <- makeVar StrMap.empty
      options <- mkOptions
      let replayingBackendRuntime = BackendRuntime
            { apiRunner   : apiRunner
            , connections : StrMap.empty
            , logRunner   : logRunner
            , affRunner   : affRunner
            , kvdbRuntime
            , mode        : ReplayingMode
              { flowGUID : ""
              , forkedFlowRecordings : StrMap.empty
              , forkedFlowErrorsVar
              , recording
              , disableVerify : []
              , disableMocking : []
              , skipEntries : ["DoAffEntry"]
              , entriesFiltered : false
              , stepVar
              , errorVar
              }
              , options
            }
      eResult2 <- liftAff $ runExceptT (runStateT (runReaderT (runBackend replayingBackendRuntime skipScript1) unit) unit)
      curStep  <- readVar stepVar
      curStep `shouldEqual` 2
      mbErr <- readVar errorVar
      mbErr `shouldEqual` Nothing
      case eResult2 of
        Right (Tuple n unit) -> n `shouldEqual` "fghij\n"
        Left  err -> fail $ show err
