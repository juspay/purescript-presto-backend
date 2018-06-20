module Presto.Backend.SysCmd where

import Prelude

import Control.Monad.Free (Free)
import Presto.Backend.Flow (BackendFlow(..), doAff)
import Presto.Core.Flow (class Inject, class Run, inject)
import Presto.Backend.SystemCommands as Sys

data SysCmdF next = RunSysCmd String (String -> next)

instance functorSysCmdF :: Functor SysCmdF where
  map f (RunSysCmd g h) = RunSysCmd g (f <<< h)

instance runSysCmdF :: Run SysCmdF BackendFlow where
  runAlgebra (RunSysCmd cmd nextF) = doAff (Sys.runSysCmd cmd) >>= (pure <<< nextF)

runSysCmd :: forall f. Inject SysCmdF f => String -> Free f String
runSysCmd cmd = inject $ RunSysCmd cmd id
