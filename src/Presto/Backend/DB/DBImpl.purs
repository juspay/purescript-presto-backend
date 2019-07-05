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

module Presto.Backend.DBImpl
  (
    useMasterClause,
    getModelByName,
    findOne,
    findAll,
    query,
    create,
    createWithOpts,
    update,
    update',
    delete
  ) where

import Prelude

import Control.Monad.Aff (Aff, attempt)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Promise (Promise, toAff)
import Data.Bifunctor (bimap)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, runFn2)
import Data.Maybe (Maybe(..), maybe)
import Data.Monoid (mempty)
import Data.Options (Options, assoc, opt)
import Sequelize.CRUD.Create (create')
import Sequelize.CRUD.Create (createWithOpts') as Seql
import Sequelize.CRUD.Destroy (delete) as Destroy
import Sequelize.CRUD.Read (findAll', findOne', query')
import Sequelize.CRUD.Update (updateModel)
import Sequelize.Class (class Model, modelName)
import Sequelize.Instance (instanceToModelE)
import Sequelize.Types (Conn, Instance, ModelOf, SEQUELIZE)
import Type.Proxy (Proxy(..))

foreign import _getModelByName :: forall a e. Fn2 Conn String (Eff (sequelize :: SEQUELIZE | e) (ModelOf a))


-- Add this clause if you want to force a query to be executed on Master DB
useMasterClause :: forall t7. Options t7
useMasterClause = (maybe mempty (assoc (opt "useMaster")) $ Just true)

getModelByName
  :: forall a e
   . Model a
  => Conn
  -> Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a))
getModelByName conn = do
    let mName = modelName (Proxy :: Proxy a)
    attempt $ liftEff $ runFn2 _getModelByName conn mName

findOne :: forall a e. Model a => Conn -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Maybe a))
findOne conn options = do
    model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ findOne' m options
            case val of
                Right (Just v) -> pure $ bimap (\err -> error $ show err) Just (instanceToModelE v)
                Right Nothing -> pure <<< Right $ Nothing
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

findAll :: forall a e. Model a => Conn -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Array a))
findAll conn options = do
    model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ findAll' m options
            case val of
                Right arrayRec -> pure <<< Right $ arrayRec
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err


query :: forall a e. Conn -> String -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Array a))
query conn rawq = do
    val <- attempt $ query' conn rawq
    case val of
        Right arrayRec -> pure <<< Right $ arrayRec
        Left err -> pure <<< Left $ error $ show err


createWithOpts :: forall a e. Model a => Conn -> a -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Maybe a))
createWithOpts conn entity options = do
    model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ Seql.createWithOpts' m entity options
            case val of
                Right rec -> pure $ bimap (\err -> error $ show err) Just (instanceToModelE rec)
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

create :: forall a e. Model a => Conn -> a -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Maybe a))
create conn entity = createWithOpts conn entity mempty

update :: forall a e . Model a => Conn -> Options a -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error (Array a))
update conn updateValues whereClause = do
    model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- update' conn updateValues whereClause
            recs <- findAll' m (whereClause <> useMasterClause)
            case val of
                Right _ -> pure <<< Right $ recs
                Left err -> pure <<< Left $ err
        Left err -> pure $ Left $ error $ show err

update' :: forall a e . Model a => Conn -> Options a -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error Int)
update' conn updateValues whereClause = do
    model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ updateModel m updateValues whereClause
            case val of
                Right {affectedCount} -> pure <<< Right $ affectedCount
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

delete :: forall a e. Model a => Conn -> Options a -> Aff (sequelize :: SEQUELIZE | e) (Either Error Int)
delete conn whereClause = do
  model <- getModelByName conn :: (Aff (sequelize :: SEQUELIZE | e) (Either Error (ModelOf a)))
  let mName = modelName (Proxy :: Proxy a)
  case model of
    Right m -> do
      val <- attempt $ Destroy.delete m whereClause
      case val of
        Right { affectedCount : count } -> pure <<< Right $ count
        Left err ->pure $ Left $ error $ show err
    Left err -> pure $ Left $ error $ show err
