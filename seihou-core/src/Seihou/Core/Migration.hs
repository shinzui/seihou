module Seihou.Core.Migration
  ( -- * Author-declared migrations
    Migration (..),
    MigrationOp (..),
  )
where

import GHC.Generics (Generic)
import Seihou.Prelude

-- | A single filesystem operation declared by a migration.
--
-- The variants mirror the Dhall union @schema/MigrationOp.dhall@ exactly:
--
--   * 'MoveFile'   — rename a tracked file. The migration engine rewrites
--     the manifest's @files@ map key from @src@ to @dest@.
--   * 'MoveDir'    — rename a directory. Every manifest @files@ entry whose
--     path starts with @src/@ has its key rewritten with the @dest/@ prefix.
--   * 'DeleteFile' — remove a tracked file from disk and drop it from the
--     manifest.
--   * 'DeleteDir'  — remove a directory recursively and drop every manifest
--     entry under that prefix.
--   * 'RunCommand' — execute a shell command. The manifest is not rewritten
--     by this op; if the command moves files, the migration author is
--     responsible for following it with explicit move/delete ops.
data MigrationOp
  = MoveFile {src :: FilePath, dest :: FilePath}
  | MoveDir {src :: FilePath, dest :: FilePath}
  | DeleteFile {path :: FilePath}
  | DeleteDir {path :: FilePath}
  | RunCommand {run :: Text, workDir :: Maybe FilePath}
  deriving stock (Eq, Show, Generic)

-- | A migration that moves a project from module version @from@ to module
-- version @to@. The 'ops' list is applied in declaration order.
data Migration = Migration
  { from :: Text,
    to :: Text,
    ops :: [MigrationOp]
  }
  deriving stock (Eq, Show, Generic)
