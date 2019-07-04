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

module Presto.Backend.Language.Flow.Extra where

import Prelude

import Control.Monad.Eff.Exception (Error, error, message)
import Data.Monoid (mempty)
import Data.Either (Either(..), note, hush, isLeft)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Options (Options)
import Data.Foreign.Class (class Encode, class Decode)
import Presto.Backend.Types (BackendAff)
import Presto.Backend.Types.EitherEx (EitherEx(..), fromCustomEitherEx, toCustomEitherEx)
import Presto.Backend.Playback.Types as Playback
import Presto.Backend.Playback.Entries as Playback
import Presto.Backend.Language.Types.DB (SqlConn(..), MockedSqlConn, SequelizeConn, DBError(..), toDBMaybeResult, fromDBMaybeResult)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)
import Presto.Backend.DB.Mock.Types as SqlDBMock
import Presto.Backend.DB.Mock.Actions as SqlDBMock
import Presto.Backend.Flow as Flow
import Presto.Backend.DB as DBImpl

findOne
  :: forall model st rt
   . Model model
  => String
  -> Options model
  -> Flow.BackendFlow st rt (Either Error (Maybe model))
findOne dbName options = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toDBMaybeResult <$> DBImpl.findOne conn options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkFindOne dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "findOne (impl)")
    id
  pure $ fromDBMaybeResult eResEx

findAll
  :: forall model st rt
   . Model model
  => String
  -> Options model
  -> Flow.BackendFlow st rt (Either Error (Array model))
findAll dbName options = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toCustomEitherEx <$> DBImpl.findAll conn options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkFindAll dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "findAll (impl)")
    id
  pure $ fromCustomEitherEx eResEx

query
  :: forall a st rt
   . Encode a
  => Decode a
  => String
  -> String
  -> Flow.BackendFlow st rt (Either Error (Array a))
query dbName rawq = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toCustomEitherEx <$> DBImpl.query conn rawq)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkQuery dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "query (impl)")
    id
  pure $ fromCustomEitherEx eResEx

createWithOpts
  :: forall model st rt
   . Model model
  => String
  -> model
  -> Options model
  -> Flow.BackendFlow st rt (Either Error (Maybe model))
createWithOpts dbName entity options = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toDBMaybeResult <$> DBImpl.createWithOpts conn entity options)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkCreateWithOpts dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "createWithOpts (impl)")
    id
  pure $ fromDBMaybeResult eResEx

create
  :: forall model st rt
   . Model model
  => String
  -> model
  -> Flow.BackendFlow st rt (Either Error (Maybe model))
create dbName entity = createWithOpts dbName entity mempty

update
  :: forall model st rt
   . Model model
  => String
  -> Options model
  -> Options model
  -> Flow.BackendFlow st rt (Either Error (Array model))
update dbName updateValues whereClause = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toCustomEitherEx <$> DBImpl.update conn updateValues whereClause)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkUpdate dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "update (impl)")
    id
  pure $ fromCustomEitherEx eResEx

update'
  :: forall model st rt
   . Model model
  => String
  -> Options model
  -> Options model
  -> Flow.BackendFlow st rt (Either Error Int)
update' dbName updateValues whereClause = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toCustomEitherEx <$> DBImpl.update' conn updateValues whereClause)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkUpdate dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "update' (impl)")
    id
  pure $ fromCustomEitherEx eResEx

delete
  :: forall model st rt
   . Model model
  => String
  -> Options model
  -> Flow.BackendFlow st rt (Either Error Int)
delete dbName whereClause = do
  eResEx <- Flow.wrap $ Flow.RunDB dbName
    (\conn     -> toCustomEitherEx <$> DBImpl.delete conn whereClause)
    (\connMock -> SqlDBMock.mkDbActionDict $ SqlDBMock.mkDelete dbName)
    (Playback.mkEntryDict $ Playback.mkRunDBEntry dbName "delete (impl)")
    id
  pure $ fromCustomEitherEx eResEx
