module Presto.Backend.Playback.Machine where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Except (runExcept) as E
import Control.Monad.Except.Trans (ExceptT(..), lift, throwError, runExceptT) as E
import Control.Monad.Reader.Trans (ReaderT, ask, lift, runReaderT) as R
import Control.Monad.State.Trans (StateT, get, lift, modify, put, runStateT) as S
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Data.Foreign.Generic (encodeJSON)
import Data.Array as Array
import Data.Either (Either(..), note, hush, isLeft)
import Data.Maybe (Maybe(..), isJust)
import Data.Tuple (Tuple(..))
import Data.Foreign.Generic as G
import Data.Lazy (Lazy, force)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Runtime.Common (jsonStringify, lift3)
import Presto.Backend.Runtime.Types
import Presto.Backend.Playback.Types
import Presto.Backend.Playback.Entries
import Type.Proxy (Proxy(..))
import Presto.Backend.Playback.Machine.Classless (withRunModeClassless)

withRunMode
  :: forall eff rt st rrItem native
   . RRItem rrItem
  => MockedResult rrItem native
  => BackendRuntime
  -> Lazy (InterpreterMT' rt st eff native)
  -> (native -> rrItem)
  -> InterpreterMT' rt st eff native
withRunMode brt lAct rrItemF = withRunModeClassless brt rrDict lAct
  where
    rrDict :: RRItemDict rrItem native
    rrDict = RRItemDict
        { toRecordingEntry   : toRecordingEntry
        , fromRecordingEntry : fromRecordingEntry
        , getTag             : getTag
        , isMocked           : isMocked
        , parseRRItem        : parseRRItem
        , mkEntry            : rrItemF
        , compare            : (==)
        , encodeJSON         : encodeJSON
        }
