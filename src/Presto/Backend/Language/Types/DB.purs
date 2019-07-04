module Presto.Backend.Language.Types.DB where

import Prelude

import Cache (SimpleConn)
import Data.Tuple (Tuple)
import Data.StrMap (StrMap)
import Sequelize.Types (Conn)


type Cache =
  { name :: String
  , connection :: SimpleConn
  }

type DB =
  { name :: String
  , connection :: Conn
  }

-- TODO: this should be reworked.
-- DB facilities design is not good enough.
-- For now, mocking approach is suboptimal, fast & dirty.

data MockedSqlConn = MockedSqlConn String
data SequelizeConn = SequelizeConn Conn

data SqlConn
  = MockedSql MockedSqlConn
  | Sequelize SequelizeConn
