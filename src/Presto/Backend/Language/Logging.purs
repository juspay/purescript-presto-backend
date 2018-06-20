module Presto.Backend.Logging where

import Prelude

import Control.Monad.Free (Free)
import Presto.Core.Flow (class Inject, inject)
import Presto.Core.Utils.Existing (Existing, mkExisting, unExisting)

data LoggingMethod s next = Log String s next

instance functorLoggingMethod :: Functor (LoggingMethod s) where
  map f (Log t m h) = Log t m (f h)

newtype LoggingF next = LoggingF (Existing LoggingMethod next)

instance functorLoggingF :: Functor LoggingF where
  map f (LoggingF e) = LoggingF $ mkExisting $ f <$> unExisting e


log :: forall f a. Inject LoggingF f => String -> a -> Free f Unit
log tag message = inject $ LoggingF $ mkExisting $ Log tag message unit
