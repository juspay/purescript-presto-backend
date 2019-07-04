module Presto.Backend.DB.Mock.Types where

import Presto.Backend.Language.Types.DB (MockedSqlConn)


class DBAction act where
  someMethod :: act -> String

class ModelDict model where
  someMethod2 :: model -> String


newtype DBActionDict = DBActionDict
  { some :: String

  }

-- findOne
--   :: forall model st rt
--    . Model model
--   => String -> Options model -> BackendFlow st rt (Either Error (Maybe model))
--
-- mkDbActionDict
--   :: forall act
--    . DBAction act
--   => act
--   -> DBActionDict
mkDbActionDict act = DBActionDict { some : "abc" }
