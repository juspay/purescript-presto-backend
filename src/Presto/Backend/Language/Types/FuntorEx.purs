module Presto.Backend.Language.Types.FunctorEx
  ( doubleMap
  , (<<$>>)
  ) where

import Prelude

doubleMap :: forall f g a b. Functor f => Functor g => (a -> b) -> f (g a) -> f (g b)
doubleMap = map <<< map

infixl 4 doubleMap as <<$>>
