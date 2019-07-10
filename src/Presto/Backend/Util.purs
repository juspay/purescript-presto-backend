module Presto.Backend.Util where

import Prelude
import Control.Monad.Eff (Eff)

foreign import currentTime :: forall e. Eff e Number