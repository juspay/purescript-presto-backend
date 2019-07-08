module Presto.Backend.Runtime.Types
  ( module Presto.Backend.Runtime.Types
  , module DB
  ) where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Except.Trans (ExceptT) as E
import Control.Monad.Reader.Trans (ReaderT) as R
import Control.Monad.State.Trans (StateT) as S
import Data.Tuple (Tuple)
import Data.StrMap (StrMap)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.API (APIRunner)
import Presto.Backend.Playback.Types (RecorderRuntime, PlayerRuntime)
import Presto.Backend.Language.Types.DB (Connection)
import Presto.Backend.Language.Types.DB as DB

type InterpreterMT rt st err eff a = R.ReaderT rt (S.StateT st (E.ExceptT err (BackendAff eff))) a
type InterpreterMT' rt st eff a = InterpreterMT rt st (Tuple Error st) eff a

type LogRunner = forall e a. String -> a -> Aff e Unit
type AffRunner = forall e a. Aff e a -> Aff e a

-- Running mode.
data RunningMode
  = RegularMode
  | RecordingMode RecorderRuntime
  | ReplayingMode PlayerRuntime


newtype BackendRuntime = BackendRuntime
  { apiRunner   :: APIRunner
  , connections :: StrMap Connection
  , logRunner   :: LogRunner
  , affRunner   :: AffRunner
  , mode        :: RunningMode
  }
