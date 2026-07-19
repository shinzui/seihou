module Seihou.Effect.BaselineStore
  ( BaselineStore (..),
    BaselineError (..),
    putBaseline,
    readBaseline,
    pruneBaselines,
  )
where

import Data.Set (Set)
import Seihou.Core.Types (BaselineRef, SHA256)
import Seihou.Prelude

-- | Failures that make a generated baseline unavailable. Store failures are
-- represented here for callers that validate the project file before writing;
-- interpreter-level filesystem exceptions still propagate through 'IOE'.
data BaselineError
  = BaselineMissing BaselineRef
  | BaselineCorrupt BaselineRef SHA256
  | BaselineStoreFailure Text
  deriving stock (Eq, Show)

-- | Content-addressed storage for generated file ancestors.
data BaselineStore :: Effect where
  PutBaseline :: Text -> BaselineStore m BaselineRef
  ReadBaseline :: BaselineRef -> BaselineStore m (Either BaselineError Text)
  PruneBaselines :: Set BaselineRef -> BaselineStore m [BaselineRef]

type instance DispatchOf BaselineStore = Dynamic

putBaseline :: (BaselineStore :> es) => Text -> Eff es BaselineRef
putBaseline content = send (PutBaseline content)

readBaseline :: (BaselineStore :> es) => BaselineRef -> Eff es (Either BaselineError Text)
readBaseline ref = send (ReadBaseline ref)

pruneBaselines :: (BaselineStore :> es) => Set BaselineRef -> Eff es [BaselineRef]
pruneBaselines refs = send (PruneBaselines refs)
