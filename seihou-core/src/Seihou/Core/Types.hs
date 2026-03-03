module Seihou.Core.Types
  ( ModuleName (..),
    VarName (..),
    VarType (..),
    VarValue (..),
    Validation (..),
    VarDecl (..),
    VarExport (..),
    Prompt (..),
    Expr (..),
    Strategy (..),
    Step (..),
    Module (..),
    Operation (..),
    ModuleLoadError (..),
    Manifest (..),
    AppliedModule (..),
    FileRecord (..),
    SHA256 (..),
    DiffResult (..),
    PlannedFile (..),
    ModifiedFile (..),
    ConflictFile (..),
    OrphanedFile (..),
    ConflictResolution (..),
    VarSource (..),
    ResolvedVar (..),
    VarError (..),
    PlaceholderError (..),
    CompositionWarning (..),
    ConfigError (..),
  )
where

import Data.Map.Strict (Map)
import Data.String (IsString)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | A module identifier such as @"haskell-base"@.
newtype ModuleName = ModuleName {unModuleName :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

-- | A variable identifier such as @"project.name"@.
newtype VarName = VarName {unVarName :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

-- | The type of a variable declaration.
data VarType
  = VTText
  | VTBool
  | VTInt
  | VTList VarType
  | VTChoice [Text]
  deriving stock (Eq, Show, Generic)

-- | A concrete variable value.
data VarValue
  = VText Text
  | VBool Bool
  | VInt Int
  | VList [VarValue]
  deriving stock (Eq, Show, Generic)

-- | Validation constraints on a variable.
data Validation
  = ValPattern Text
  | ValRange Int Int
  | ValMinLength Int
  | ValMaxLength Int
  deriving stock (Eq, Show, Generic)

-- | A variable declaration within a module.
data VarDecl = VarDecl
  { varName :: VarName,
    varType :: VarType,
    varDefault :: Maybe VarValue,
    varDescription :: Maybe Text,
    varRequired :: Bool,
    varValidation :: Maybe Validation
  }
  deriving stock (Eq, Show, Generic)

-- | A variable export for cross-module visibility.
data VarExport = VarExport
  { exportVar :: VarName,
    exportAs :: Maybe VarName
  }
  deriving stock (Eq, Show, Generic)

-- | An interactive prompt for a variable.
data Prompt = Prompt
  { promptVar :: VarName,
    promptText :: Text,
    promptWhen :: Maybe Expr,
    promptChoices :: Maybe [Text]
  }
  deriving stock (Eq, Show, Generic)

-- | Expression AST for conditional logic in @when@ clauses.
-- Expressions are stored as strings in Dhall (e.g., @"IsSet license && Eq license MIT"@)
-- and parsed into this AST by the expression parser in @Seihou.Core.Expr@.
data Expr
  = ExprEq VarName VarValue
  | ExprAnd Expr Expr
  | ExprOr Expr Expr
  | ExprNot Expr
  | ExprIsSet VarName
  | ExprLit Bool
  deriving stock (Eq, Show, Generic)

-- | The four generation strategies.
data Strategy
  = Copy
  | Template
  | DhallText
  | Structured
  deriving stock (Eq, Show, Generic)

-- | A generation step within a module.
data Step = Step
  { stepStrategy :: Strategy,
    stepSrc :: FilePath,
    stepDest :: Text,
    stepWhen :: Maybe Expr
  }
  deriving stock (Eq, Show, Generic)

-- | A module definition: the fundamental unit of composition.
data Module = Module
  { moduleName :: ModuleName,
    moduleDescription :: Maybe Text,
    moduleVars :: [VarDecl],
    moduleExports :: [VarExport],
    modulePrompts :: [Prompt],
    moduleSteps :: [Step],
    moduleDependencies :: [ModuleName]
  }
  deriving stock (Eq, Show, Generic)

-- | Filesystem operations produced by the generation engine.
data Operation
  = WriteFileOp
      { opDest :: FilePath,
        opContent :: Text,
        opStrategy :: Strategy
      }
  | CreateDirOp
      { opPath :: FilePath
      }
  | CopyFileOp
      { opSrc :: FilePath,
        opDest :: FilePath
      }
  | RunCommandOp
      { opCommand :: Text,
        opWorkDir :: Maybe FilePath
      }
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur during module loading and validation.
data ModuleLoadError
  = ModuleNotFound ModuleName [FilePath]
  | DhallEvalError ModuleName Text
  | DhallDecodeError ModuleName Text
  | ValidationError ModuleName [Text]
  | CircularDependency [ModuleName]
  | MissingSourceFile ModuleName FilePath
  deriving stock (Eq, Show, Generic)

-- | Tracks where a variable's value came from (for provenance / @--explain@).
data VarSource
  = FromCLI
  | FromEnv Text
  | FromLocalConfig
  | FromNamespaceConfig Text
  | FromGlobalConfig
  | FromDefault
  | FromPrompt
  deriving stock (Eq, Show, Generic)

-- | A variable that has been resolved to a concrete value with provenance.
data ResolvedVar = ResolvedVar
  { resolvedValue :: VarValue,
    resolvedSource :: VarSource,
    resolvedDecl :: VarDecl
  }
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur during variable resolution.
data VarError
  = MissingRequiredVar VarName
  | TypeMismatch VarName VarType VarValue
  | ValidationFailed VarName Text
  | CoercionFailed VarName VarType Text
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur during template placeholder substitution.
data PlaceholderError
  = UnresolvedPlaceholder VarName Int
  | MalformedPlaceholder Text Int
  deriving stock (Eq, Show, Generic)

-- | Tracks the state of generated files for incremental re-generation
-- and conflict detection. Stored at @.seihou/manifest.json@.
data Manifest = Manifest
  { manifestVersion :: Int,
    manifestGenAt :: UTCTime,
    manifestModules :: [AppliedModule],
    manifestVars :: Map VarName Text,
    manifestFiles :: Map FilePath FileRecord
  }
  deriving stock (Eq, Show, Generic)

-- | A module that has been applied to generate files.
data AppliedModule = AppliedModule
  { appliedName :: ModuleName,
    appliedSource :: FilePath,
    appliedAt :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

-- | A record of a generated file, stored in the manifest.
data FileRecord = FileRecord
  { fileHash :: SHA256,
    fileModule :: ModuleName,
    fileStrategy :: Strategy,
    fileGeneratedAt :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

-- | A SHA256 content hash, stored as a hex-encoded text string.
newtype SHA256 = SHA256 {unSHA256 :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

-- | Result of the three-state diff: manifest vs plan vs disk.
data DiffResult = DiffResult
  { diffNew :: [PlannedFile],
    diffModified :: [ModifiedFile],
    diffUnchanged :: [FilePath],
    diffConflict :: [ConflictFile],
    diffOrphaned :: [OrphanedFile]
  }
  deriving stock (Eq, Show, Generic)

-- | A file that exists in the plan but not in the manifest or on disk.
data PlannedFile = PlannedFile
  { plannedPath :: FilePath,
    plannedModule :: ModuleName,
    plannedContent :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file that has changed between the manifest and the plan,
-- but the user has not modified the disk copy.
data ModifiedFile = ModifiedFile
  { modifiedPath :: FilePath,
    modifiedModule :: ModuleName,
    modifiedOldHash :: SHA256,
    modifiedNewContent :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file where the user has modified the disk copy since it was generated.
data ConflictFile = ConflictFile
  { conflictPath :: FilePath,
    conflictModule :: ModuleName,
    conflictManifest :: SHA256,
    conflictDisk :: SHA256,
    conflictPlan :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file that exists in the manifest but not in the current plan
-- (the module that generated it was removed or no longer produces it).
data OrphanedFile = OrphanedFile
  { orphanedPath :: FilePath,
    orphanedModule :: ModuleName
  }
  deriving stock (Eq, Show, Generic)

-- | How to resolve a conflict when a user has modified a generated file.
data ConflictResolution
  = AcceptNew
  | KeepCurrent
  | Skip
  | Abort
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur when reading config files.
data ConfigError
  = ConfigParseError FilePath Text
  | InvalidNamespace Text Text
  deriving stock (Eq, Show, Generic)

-- | Warnings emitted during multi-module composition.
-- 'FileOverwritten' records that a file produced by one module was
-- overwritten by a later module in execution order (last-writer-wins).
data CompositionWarning
  = FileOverwritten FilePath ModuleName ModuleName
  deriving stock (Eq, Show, Generic)
