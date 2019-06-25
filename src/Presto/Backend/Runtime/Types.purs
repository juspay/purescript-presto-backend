module Presto.Backend.Runtime.Types where

import Prelude

import Cache (SimpleConn)
import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Except.Trans (ExceptT) as E
import Control.Monad.Reader.Trans (ReaderT) as R
import Control.Monad.State.Trans (StateT) as S
import Data.Tuple (Tuple)
import Data.StrMap (StrMap)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Playback.Types (RecorderRuntime, PlayerRuntime)
import Presto.Core.Language.Runtime.API (APIRunner)
import Sequelize.Types (Conn)

type InterpreterMT rt st err eff a = R.ReaderT rt (S.StateT st (E.ExceptT err (BackendAff eff))) a
type InterpreterMT' rt st eff a = InterpreterMT rt st (Tuple Error st) eff a

type LogRunner = forall e a. String -> a -> Aff e Unit

-- Running mode.
data RunningMode
  = RegularMode
  | RecordingMode RecorderRuntime
  | ReplayingMode PlayerRuntime

type Cache = {
    name :: String
  , connection :: SimpleConn
}

type DB = {
    name :: String
  , connection :: Conn
}

data Connection
  = Sequelize Conn
  | Redis SimpleConn

newtype BackendRuntime = BackendRuntime
  { apiRunner   :: APIRunner
  , connections :: StrMap Connection
  , logRunner   :: LogRunner
  , mode        :: RunningMode
  }
