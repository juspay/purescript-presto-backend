module Test.Main where

import Prelude

import Control.Monad.Eff (Eff)
import Unsafe.Coerce (unsafeCoerce)

import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run) as T

import Presto.Backend.RunModesSpec as RunModesSpec

-- Temporary unsafeCorece to avoid effects mangling and "no match" of PROCESS problem.
-- TODO: fix the problem later (it can also lead to evaluation problems)

main :: Eff _ Unit
main = T.run [consoleReporter] $
  unsafeCoerce RunModesSpec.runTests
