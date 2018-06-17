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

module Presto.Backend.Flow where

import Prelude
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Free (Free, liftF)
import Presto.Backend.DB (findOne, findAll, create, update, delete) as DB
import Data.Either (Either(..))
import Data.Exists (Exists, mkExists)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Maybe (Maybe(..))
import Data.Options (Options)
import Presto.Backend.Types (BackendAff)
import Presto.Core.Types.API (class RestEndpoint, Headers)
import Presto.Core.Types.Language.APIInteract (apiInteract)
import Presto.Core.Types.Language.Flow (APIResult, Control)
import Presto.Core.Types.Language.Interaction (Interaction)
import Sequelize.Class (class Model)
import Sequelize.Types (Conn)
import Cache (CacheConn)

data BackendFlowCommands next st rt s = 
      Ask (rt -> next)
    | Get (st -> next)
    | Put st (st -> next)
    | Modify (st -> st) (st -> next)
    | CallAPI (Interaction (APIResult s)) (APIResult s -> next)
    | DoAff (forall eff. BackendAff eff s) (s -> next)
    | ThrowException String (s -> next)
    | FindOne (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindAll (Either Error (Array s)) (Either Error (Array s) -> next)
    | Create  (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | FindOrCreate (Either Error (Maybe s)) (Either Error (Maybe s) -> next)
    | Update (Either Error (Array s)) (Either Error (Array s) -> next)
    | Delete (Either Error Int) (Either Error Int -> next)
    | GetDBConn String (Conn -> next)
    | Fork (BackendFlow st rt s) (Control s -> next)
    | Log String s next
    | RunSysCmd String (String -> next)

    -- | HandleException 
    -- | Await (Control s) (s -> next)
    -- | Delay Milliseconds next

type BackendFlowCommandsWrapper st rt s next = BackendFlowCommands next st rt s

newtype BackendFlowWrapper st rt next = BackendFlowWrapper (Exists (BackendFlowCommands next st rt))

type BackendFlow st rt next = Free (BackendFlowWrapper st rt) next

wrap :: forall next st rt s. BackendFlowCommands next st rt s -> BackendFlow st rt next
wrap = liftF <<< BackendFlowWrapper <<< mkExists

ask :: forall st rt. BackendFlow st rt rt
ask = wrap $ Ask id

get :: forall st rt. BackendFlow st rt st
get = wrap $ Get id

put :: forall st rt. st -> BackendFlow st rt st
put st = wrap $ Put st id

modify :: forall st rt. (st -> st) -> BackendFlow st rt st
modify fst = wrap $ Modify fst id

throwException :: forall st rt a. String -> BackendFlow st rt a
throwException errorMessage = wrap $ ThrowException errorMessage id

doAff :: forall st rt a. (forall eff. BackendAff eff a) -> BackendFlow st rt a
doAff aff = wrap $ DoAff aff id

findOne :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOne dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findOne conn options
  wrap $ FindOne model id

findAll :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Array model))
findAll dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.findAll conn options
  wrap $ FindAll model id 

create :: forall model st rt. Model model => String -> model -> BackendFlow st rt (Either Error (Maybe model))
create dbName model = do
  conn <- getDBConn dbName
  result <- doAff do
        DB.create conn model
  wrap $ Create result id

findOrCreate :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
findOrCreate dbName options = do
  conn <- getDBConn dbName
  wrap $ FindOrCreate (Right Nothing) id

update :: forall model st rt. Model model => String -> Options model -> Options model -> BackendFlow st rt (Either Error (Array model))
update dbName updateValues whereClause = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.update conn updateValues whereClause
  wrap $ Update model id

delete :: forall model st rt. Model model => String -> Options model -> BackendFlow st rt (Either Error Int)
delete dbName options = do
  conn <- getDBConn dbName
  model <- doAff do
        DB.delete conn options
  wrap $ Delete model id

getDBConn :: forall st rt. String -> BackendFlow st rt Conn
getDBConn dbName = do
  wrap $ GetDBConn dbName id

callAPI :: forall st rt a b. Encode a => Decode b => RestEndpoint a b
  => Headers -> a -> BackendFlow st rt (APIResult b)
callAPI headers a = wrap $ CallAPI (apiInteract a headers) id 

log :: forall st rt a. String -> a -> BackendFlow st rt Unit
log tag message = wrap $ Log tag message unit


runSysCmd :: forall st rt. String -> BackendFlow st rt String
runSysCmd cmd = wrap $ RunSysCmd cmd id