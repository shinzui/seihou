module Seihou.Core.Registry
  ( Registry (..),
    RegistryEntry (..),
    RepoContents (..),
  )
where

import GHC.Generics (Generic)
import Seihou.Core.Types (ModuleName)
import Seihou.Prelude

-- | A single module listing within a registry.
data RegistryEntry = RegistryEntry
  { name :: ModuleName,
    path :: FilePath,
    description :: Maybe Text,
    tags :: [Text]
  }
  deriving stock (Eq, Show, Generic)

-- | Registry metadata for a multi-module repository.
-- Declared in @seihou-registry.dhall@ at the repo root.
data Registry = Registry
  { repoName :: Text,
    repoDescription :: Maybe Text,
    modules :: [RegistryEntry]
  }
  deriving stock (Eq, Show, Generic)

-- | What a cloned repository contains.
data RepoContents
  = -- | Repo root has @module.dhall@ (single module)
    SingleModule FilePath
  | -- | Repo root has @seihou-registry.dhall@
    MultiModule Registry
  | -- | Neither found
    EmptyRepo
  deriving stock (Show)
