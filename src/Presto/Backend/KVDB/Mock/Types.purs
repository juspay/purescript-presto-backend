module Presto.Backend.KVDB.Mock.Types where

import Presto.Backend.Language.Types.DB (MockedKVDBConn)

-- TODO, draft

data KVDBActionDict = KVDBActionDict

mkKVDBActionDict :: MockedKVDBConn -> KVDBActionDict
mkKVDBActionDict _ = KVDBActionDict
