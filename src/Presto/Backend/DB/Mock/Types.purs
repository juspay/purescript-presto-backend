module Presto.Backend.DB.Mock.Types where

import Presto.Backend.Language.Types.DB (MockedSqlConn)

-- TODO, draft

class DBAction act where
  someMethod :: act -> String

class ModelDict model where
  someMethod2 :: model -> String


newtype DBActionDict = DBActionDict
  { some :: String
  }

mkDbActionDict act = DBActionDict { some : "abc" }
