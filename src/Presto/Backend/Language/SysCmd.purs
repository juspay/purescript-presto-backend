module Presto.Backend.SysCmd where

import Prelude

import Control.Monad.Free (Free)
import Presto.Core.Flow (class Inject, inject)

data SysCmdF next = RunSysCmd String (String -> next)

instance functorSysCmdF :: Functor SysCmdF where
  map f (RunSysCmd g h) = RunSysCmd g (f <<< h)

runSysCmd :: forall f. Inject SysCmdF f => String -> Free f String
runSysCmd cmd = inject $ RunSysCmd cmd id
