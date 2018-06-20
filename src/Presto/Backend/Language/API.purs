module Presto.Backend.API where

import Prelude

import Control.Monad.Free (Free)
import Data.Foreign.Class (class Decode, class Encode)
import Presto.Core.Flow (class Inject, APIResult, Interaction, inject)
import Presto.Core.Types.API (class RestEndpoint, Headers)
import Presto.Core.Types.Language.APIInteract (apiInteract)
import Presto.Core.Utils.Existing (Existing, mkExisting, unExisting)


data APIMethod s next = CallAPI (Interaction (APIResult s)) (APIResult s -> next)

instance functorAPIMethod :: Functor (APIMethod s) where
  map f (CallAPI g h) = CallAPI g (f <<< h)

newtype ApiF next = ApiF (Existing APIMethod next)

instance functorApiF :: Functor ApiF where
  map f (ApiF e) = ApiF $ mkExisting $ f <$> unExisting e

callAPI :: forall f a b. Inject ApiF f => Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> Free f (APIResult b)
callAPI headers a = inject $ ApiF $ mkExisting $ CallAPI (apiInteract a headers) id 

