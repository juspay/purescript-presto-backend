{-
 Copyright (c) 2012-2017 "JUSPAY Technologies"
 JUSPAY Technologies Pvt. Ltd. [https://www.juspay.in]
 This file is part of JUSPAY Platform.
 JUSPAY Platform is free software: you can redistribute it and/or modify
 it for only educational purposes under the terms of the GNU Affero General
 Public License (GNU AGPL) as published by the Free Software Foundation,
 either version 3 of the License, or (at your option) any later version.
 For Enterprise/Commerical licenses, contact <info@juspay.in>.
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  The end user will
 be liable for all damages without limitation, which is caused by the
 ABUSE of the LICENSED SOFTWARE and shall INDEMNIFY JUSPAY for such
 damages, claims, cost, including reasonable attorney fee claimed on Juspay.
 The end user has NO right to claim any indemnification based on its use
 of Licensed Software. See the GNU Affero General Public License for more details.
 You should have received a copy of the GNU Affero General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/agpl.html>.
-}

module Presto.Backend.Runtime.Types
  ( module Presto.Backend.Runtime.Types
  , module DB
  ) where

import Prelude

import Cache.Multi (Multi) as Native
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVar)
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

type MultiCatalogue = StrMap Native.Multi

newtype KVDBRuntime = KVDBRuntime
  { multiesVar   :: AVar MultiCatalogue
  }

newtype BackendRuntime = BackendRuntime
  { apiRunner   :: APIRunner
  , connections :: StrMap Connection
  , logRunner   :: LogRunner
  , affRunner   :: AffRunner
  , kvdbRuntime :: KVDBRuntime
  , mode        :: RunningMode
  , options     :: AVar (StrMap String)
  }
