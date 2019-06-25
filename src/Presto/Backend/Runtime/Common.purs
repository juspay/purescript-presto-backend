module Presto.Backend.Runtime.Common where

import Prelude

import Control.Monad.Except.Trans (lift) as E
import Control.Monad.Reader.Trans (lift) as R
import Control.Monad.State.Trans (lift) as S
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Runtime.Types (InterpreterMT')


foreign import jsonStringify :: forall a. a -> String


lift3 :: forall eff err rt st a. BackendAff eff a -> InterpreterMT' rt st eff a
lift3 m = R.lift (S.lift (E.lift m))
