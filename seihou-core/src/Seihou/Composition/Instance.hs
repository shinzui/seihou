module Seihou.Composition.Instance
  ( ModuleInstance (..),
    mkInstance,
    primaryInstance,
    qualifiedName,
    stableHash,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.Core.Types
  ( ModuleName (..),
    ParentVars (..),
    VarName (..),
    emptyParentVars,
  )
import Seihou.Prelude

-- | Identity of a module invocation within a composition.
--
-- Two invocations of the same module with different parent-supplied
-- bindings are distinct instances; two with identical bindings share
-- one instance. See @docs/plans/10-parameterized-dep-multi-instantiation.md@
-- for the full rationale.
data ModuleInstance = ModuleInstance
  { instanceModule :: ModuleName,
    instanceParentVars :: ParentVars
  }
  deriving stock (Eq, Ord, Show)

-- | Build a 'ModuleInstance' from a module name and the parent-supplied
-- bindings along the edge that reached it.
mkInstance :: ModuleName -> ParentVars -> ModuleInstance
mkInstance n pv = ModuleInstance {instanceModule = n, instanceParentVars = pv}

-- | The 'ModuleInstance' for a top-level (primary / CLI-additional /
-- recipe-expanded) module, which receives no parent-supplied bindings.
primaryInstance :: ModuleName -> ModuleInstance
primaryInstance n = mkInstance n emptyParentVars

-- | Collapse a 'ModuleInstance' to a 'ModuleName' that is unique within
-- a single composition.
--
-- When the instance has no parent-supplied bindings, the bare module
-- name is returned unchanged — single-instance compositions continue
-- to use plain names in file records, patch operations, and manifest
-- keys. When bindings are present, an @\#@-suffixed 'stableHash' of
-- those bindings is appended so two instances of the same module do
-- not collide.
--
-- This function is only used where a 'ModuleName' must be unique
-- within a composition (e.g. 'FileRecord.moduleName',
-- 'PatchFileOp.moduleName', internal manifest grouping keys). User-
-- facing provenance such as 'VarSource.FromParent' keeps the bare
-- 'ModuleName' alongside the bindings so output stays readable.
qualifiedName :: ModuleInstance -> ModuleName
qualifiedName inst =
  case Map.null inst.instanceParentVars.unParentVars of
    True -> inst.instanceModule
    False ->
      ModuleName $
        inst.instanceModule.unModuleName
          <> "#"
          <> stableHash inst.instanceParentVars

-- | Compute the disambiguating hash for a 'ParentVars' set.
--
-- Canonicalisation: the bindings are sorted ascending by 'VarName',
-- each rendered as @name=value@, and the lines joined with @\\n@.
-- The UTF-8 bytes of that canonical string are hashed with SHA-256
-- and the first eight hex characters of the digest are returned.
--
-- The hash is only a within-composition disambiguator; collision
-- probability at 2^32 is acceptable for compositions of realistic
-- size.
stableHash :: ParentVars -> Text
stableHash (ParentVars m) =
  let sorted = Map.toAscList m
      canonical = T.intercalate "\n" [n <> "=" <> v | (VarName n, v) <- sorted]
      digest = SHA256.hash (TE.encodeUtf8 canonical)
      hex = TE.decodeUtf8 (Base16.encode digest)
   in T.take 8 hex
