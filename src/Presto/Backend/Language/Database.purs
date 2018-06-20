module Presto.Backend.Database where

import Prelude

import Control.Monad.Eff.Exception (Error)
import Control.Monad.Free (Free)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Presto.Backend.DB (findOne, findAll, create, update, delete) as DB
import Presto.Backend.Types (BackendAff)
import Presto.Core.Utils.Existing (Existing, mkExisting, unExisting)
import Presto.Core.Utils.Inject (class Inject, inject)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)

data DatabaseCommand s next =
      FindOne (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindAll (Either Error (Array s)) (Either Error (Array s) -> next)
    | Create  (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindOrCreate (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | Update (Either Error (Array s)) (Either Error (Array s) -> next)
    | Delete (Either Error Int) (Either Error Int -> next)
    | GetDBConn String (Conn -> next)
    | DoAff (forall eff. BackendAff eff s) (s -> next)


instance functorDatabaseCommand :: Functor (DatabaseCommand s) where
    map f (FindOne g h) = FindOne g (f <<< h)
    map f (FindAll g h) = FindAll g (f <<< h)
    map f (Create g h) = Create g (f <<< h)
    map f (FindOrCreate g h) = FindOrCreate g (f <<< h)
    map f (Update g h) = Update g (f <<< h)
    map f (Delete g h) = Delete g (f <<< h)
    map f (GetDBConn g h) = GetDBConn g (f <<< h)
    map f (DoAff g h) = DoAff g (f <<< h)

newtype DatabaseF next = DatabaseF (Existing DatabaseCommand next)

instance functorDatabaseF :: Functor DatabaseF where
    map f (DatabaseF e) = DatabaseF $ mkExisting $ f <$> unExisting e


wrap :: forall s a f. Inject DatabaseF f => DatabaseCommand s a -> Free f a
wrap = inject <<< DatabaseF <<< mkExisting

findOne :: forall model f. Inject DatabaseF f => Model model => String -> Options model -> Free f (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model id

findAll :: forall model f. Inject DatabaseF f => Model model => String -> Options model -> Free f (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model id 

create :: forall model f. Inject DatabaseF f => Model model => String -> model -> Free f (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result id

findOrCreate :: forall model f. Inject DatabaseF f => Model model => String -> Options model -> Free f (Either Error (Maybe model))
findOrCreate dbName options = do
  --conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) id

update :: forall model f. Inject DatabaseF f => Model model => String -> Options model -> Options model -> Free f (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model id

delete :: forall model f. Inject DatabaseF f => Model model => String -> Options model -> Free f (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model id

getDBConn :: forall f. Inject DatabaseF f => String -> Free f Conn
getDBConn dbName = wrap $ GetDBConn dbName id

doAff :: forall f a. Inject DatabaseF f => (forall eff. BackendAff eff a) -> Free f a
doAff aff = wrap $ DoAff aff id
