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

module Presto.Backend.DB where

import Prelude

import Data.Bifunctor (bimap)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, runFn2)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Effect (Effect)
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Exception (Error, error)
import Sequelize.CRUD.Create (bulkCreate, create')
import Sequelize.CRUD.Destroy (delete) as Destroy
import Sequelize.CRUD.Read (findAll', findAndCountAll', findOne')
import Sequelize.CRUD.Update (updateModel')
import Sequelize.Class (class Model, modelName)
import Sequelize.Instance (instanceToModelE)
import Sequelize.Types (Conn, ModelOf)
import Type.Proxy (Proxy(..))

foreign import _getModelByName :: forall a. Fn2 Conn String (Effect (ModelOf a))


getModelByName :: forall a. Model a => Conn -> Aff (Either Error (ModelOf a))
getModelByName conn = do
    let mName = modelName (Proxy :: Proxy a)
    attempt $ liftEffect $ runFn2 _getModelByName conn mName

findOne :: forall a. Model a => Conn -> Options a -> Aff (Either Error (Maybe a))
findOne conn options = do
    model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ findOne' m options
            case val of
                Right (Just v) -> pure $ bimap (\err -> error $ show err) Just (instanceToModelE v)
                Right Nothing -> pure <<< Right $ Nothing
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

-- findOneE :: forall a. Model a => Options a -> FlowES Configs _ a
-- findOneE options = do
--   conn <- get
--   model <- getModelByName :: (FlowES Configs _ (ModelOf a))
--   let mName = modelName (Proxy :: Proxy a)
--   lift $ ExceptT $ doAff do
--     val <- attempt $ findOne' model options
--     case val of
--       Right (Just v) -> pure $ bimap (\err -> DBError { message : show err  }) id (instanceToModelE v)
--       Right Nothing -> pure <<< Left $ DBError { message : mName <> " not found" }
--       Left err -> pure <<< Left $ DBError { message : show err }

findAll :: forall a. Model a => Conn -> Options a -> Aff (Either Error (Array a))
findAll conn options = do
    model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ findAll' m options
            case val of
                Right arrayRec -> pure <<< Right $ arrayRec
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

findAndCountAll :: forall a. Model a => Conn -> Options a
  -> Aff (Either Error { count :: Int, rows :: Array a})
findAndCountAll conn options = do
  model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
  case model of
      Right m -> do
          val <- attempt $ findAndCountAll' m options
          case val of
              Right arrayRec -> pure <<< Right $ arrayRec
              Left err -> pure <<< Left $ error $ show err
      Left err -> pure $ Left $ error $ show err

create :: forall a. Model a => Conn -> a -> Aff (Either Error (Maybe a))
create conn entity = do
    model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ create' m entity
            case val of
                Right rec -> pure $ bimap (\err -> error $ show err) Just (instanceToModelE rec)
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

bCreate' :: forall a. Model a => Conn -> Array a -> Aff (Either Error Unit)
bCreate' conn entity = do
    model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ bulkCreate m entity
            case val of
                Right rec -> pure $ Right unit
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

update :: forall a. Model a => Conn -> Options a -> Options a -> Aff (Either Error (Array a))
update conn updateValues whereClause = do
    model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
    case model of
        Right m -> do
            val <- attempt $ updateModel' m updateValues whereClause
            case val of
                Right {affectedCount : 0, affectedRows } -> pure <<< Right $ []
                Right {affectedCount , affectedRows : Nothing } -> do
                    recs <- findAll' m whereClause
                    pure <<< Right $ recs
                Right {affectedCount , affectedRows : Just x } -> pure <<< Right $ x
                Left err -> pure <<< Left $ error $ show err
        Left err -> pure $ Left $ error $ show err

-- updateE :: forall a e . Model a => Options a -> Options a -> FlowES Configs _ (Array a)
-- updateE updateValues whereClause = do
--   { conn } <- get
--   model <- getModelByName :: (FlowES Configs _ (ModelOf a))
--   let mName = modelName (Proxy :: Proxy a)
--   lift $ ExceptT $ doAff do
--     val <- attempt $ updateModel model updateValues whereClause
--     recs <- Read.findAll' model whereClause
--     case val of
--       Right { affectedCount : 0, affectedRows } -> pure <<< Left $ DBError { message : "No record updated " <> mName }
--       Right { affectedCount , affectedRows : Nothing } -> pure <<< Left $ DBError { message : "No record updated " <> mName }
--       Right { affectedCount , affectedRows : Just x } -> pure <<< Right $ recs
--       Left err -> pure <<< Left $ DBError { message : message err }

delete :: forall a. Model a => Conn -> Options a -> Aff (Either Error Int)
delete conn whereClause = do
  model <- getModelByName conn :: (Aff (Either Error (ModelOf a)))
  let mName = modelName (Proxy :: Proxy a)
  case model of
    Right m -> do
      val <- attempt $ Destroy.delete m whereClause
      case val of
        Right { affectedCount : count } -> pure <<< Right $ count
        Left err ->pure $ Left $ error $ show err
    Left err -> pure $ Left $ error $ show err
