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
    PatchOp (..),
    Step (..),
    Command (..),
    Dependency (..),
    simpleDep,
    depModuleNames,
    ParentVars (..),
    emptyParentVars,
    parentVarsFromDep,
    RemovalAction (..),
    RemovalStep (..),
    Removal (..),
    Module (..),
    RecipeName (..),
    Recipe (..),
    Runnable (..),
    recipeNameToModuleName,
    Operation (..),
    ModuleLoadError (..),
    Manifest (..),
    AppliedModule (..),
    AppliedRecipe (..),
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
    ConfigScope (..),
    LogLevel (..),
    TrackedFileStatus (..),
    TrackedFile (..),
  )
where

import Data.Map.Strict (Map)
import Data.String (IsString)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Seihou.Core.Migration (Migration)

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
  { name :: VarName,
    type_ :: VarType,
    default_ :: Maybe VarValue,
    description :: Maybe Text,
    required :: Bool,
    validation :: Maybe Validation
  }
  deriving stock (Eq, Show, Generic)

-- | A variable export for cross-module visibility.
data VarExport = VarExport
  { var :: VarName,
    alias :: Maybe VarName
  }
  deriving stock (Eq, Show, Generic)

-- | An interactive prompt for a variable.
data Prompt = Prompt
  { var :: VarName,
    text :: Text,
    condition :: Maybe Expr,
    choices :: Maybe [Text]
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

-- | Patch operations for modifying existing files during composition.
-- A step with a 'PatchOp' contributes content to a file that another module
-- creates, rather than overwriting it.
data PatchOp
  = AppendFile
  | PrependFile
  | AppendSection
  | AppendLineIfAbsent
  deriving stock (Eq, Show, Generic)

-- | A generation step within a module.
data Step = Step
  { strategy :: Strategy,
    src :: FilePath,
    dest :: Text,
    condition :: Maybe Expr,
    patch :: Maybe PatchOp
  }
  deriving stock (Eq, Show, Generic)

-- | A shell command to run after file generation.
data Command = Command
  { run :: Text,
    workDir :: Maybe Text,
    condition :: Maybe Expr
  }
  deriving stock (Eq, Show, Generic)

-- | A dependency on another module, optionally supplying variable bindings.
-- When @depVars@ is non-empty, the listed variables are pre-supplied to the
-- dependency during resolution, sitting between global config and module
-- defaults in the precedence chain.
data Dependency = Dependency
  { depModule :: ModuleName,
    depVars :: Map VarName Text
  }
  deriving stock (Eq, Show, Generic)

-- | Create a bare dependency with no variable bindings.
simpleDep :: ModuleName -> Dependency
simpleDep name = Dependency {depModule = name, depVars = mempty}

-- | Extract module names from a list of dependencies.
depModuleNames :: [Dependency] -> [ModuleName]
depModuleNames = map (.depModule)

-- | The variable bindings supplied by a dependent module along a specific
-- dependency edge. This is the "edge decoration" — the identity of a
-- 'ModuleInstance' is determined by the @depVars@ the parent supplied,
-- not by anything resolved downstream.
--
-- The underlying 'Data.Map.Strict' @Ord@ instance gives structural equality:
-- two 'ParentVars' values are equal iff they contain the same name/value
-- pairs regardless of construction order.
newtype ParentVars = ParentVars {unParentVars :: Map VarName Text}
  deriving stock (Eq, Ord, Show, Generic)

-- | The identity used when a module is invoked with no parent-supplied
-- bindings (the CLI primary module, recipe-expanded additionals, or any
-- dependency declared with @vars = []@).
emptyParentVars :: ParentVars
emptyParentVars = ParentVars mempty

-- | Build 'ParentVars' from a 'Dependency' record's @depVars@ field.
parentVarsFromDep :: Dependency -> ParentVars
parentVarsFromDep dep = ParentVars dep.depVars

-- | The type of removal action for a removal step.
data RemovalAction
  = -- | Delete the file entirely.
    RemoveFileAction
  | -- | Strip this module's section markers from the file.
    RemoveSectionAction
  | -- | Apply a Dhall text function to transform the file.
    RewriteFileAction
  deriving stock (Eq, Show, Generic)

-- | A single removal step describing how to reverse one effect of a module.
data RemovalStep = RemovalStep
  { action :: RemovalAction,
    dest :: Text,
    src :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Removal specification for a module.
data Removal = Removal
  { removalSteps :: [RemovalStep],
    removalCommands :: [Command]
  }
  deriving stock (Eq, Show, Generic)

-- | A module definition: the fundamental unit of composition.
data Module = Module
  { name :: ModuleName,
    version :: Maybe Text,
    description :: Maybe Text,
    vars :: [VarDecl],
    exports :: [VarExport],
    prompts :: [Prompt],
    steps :: [Step],
    commands :: [Command],
    dependencies :: [Dependency],
    removal :: Maybe Removal,
    migrations :: [Migration]
  }
  deriving stock (Eq, Show, Generic)

-- | A recipe identifier such as @"haskell-library"@.
-- Shares the same @[a-z][a-z0-9-]*@ namespace as 'ModuleName'.
newtype RecipeName = RecipeName {unRecipeName :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

-- | A recipe: a named, reusable composition of modules with optional
-- pre-configured variable bindings.
data Recipe = Recipe
  { name :: RecipeName,
    version :: Maybe Text,
    description :: Maybe Text,
    modules :: [Dependency],
    vars :: [VarDecl],
    prompts :: [Prompt]
  }
  deriving stock (Eq, Show, Generic)

-- | The result of name-based discovery: either a module or a recipe.
data Runnable
  = RunnableModule Module FilePath
  | RunnableRecipe Recipe FilePath
  deriving stock (Show)

-- | Convert a 'RecipeName' to a 'ModuleName' (they share a namespace).
recipeNameToModuleName :: RecipeName -> ModuleName
recipeNameToModuleName (RecipeName t) = ModuleName t

-- | Filesystem operations produced by the generation engine.
data Operation
  = WriteFileOp
      { dest :: FilePath,
        content :: Text,
        strategy :: Strategy
      }
  | CreateDirOp
      { path :: FilePath
      }
  | CopyFileOp
      { src :: FilePath,
        dest :: FilePath
      }
  | RunCommandOp
      { command :: Text,
        workDir :: Maybe FilePath
      }
  | PatchFileOp
      { dest :: FilePath,
        content :: Text,
        op :: PatchOp,
        strategy :: Strategy,
        moduleName :: ModuleName
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
  | RegistryEvalError Text Text
  deriving stock (Eq, Show, Generic)

-- | Tracks where a variable's value came from (for provenance / @--explain@).
data VarSource
  = FromCLI
  | FromEnv Text
  | FromLocalConfig
  | FromNamespaceConfig Text
  | FromContextConfig Text
  | FromGlobalConfig
  | FromParent ModuleName
  | FromDefault
  | FromPrompt
  deriving stock (Eq, Show, Generic)

-- | A variable that has been resolved to a concrete value with provenance.
data ResolvedVar = ResolvedVar
  { value :: VarValue,
    source :: VarSource,
    decl :: VarDecl
  }
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur during variable resolution.
data VarError
  = MissingRequiredVar VarName
  | TypeMismatch VarName VarType VarValue
  | ValidationFailed VarName Text
  | CoercionFailed VarName VarType Text
  deriving stock (Eq, Show, Generic)

-- | Errors that can occur during template placeholder substitution
-- and conditional-block expansion.
data PlaceholderError
  = UnresolvedPlaceholder VarName Int
  | MalformedPlaceholder Text Int
  | -- | @{{#if …}}@ with no matching @{{/if}}@; line is the opener.
    UnterminatedIf Int
  | -- | @{{/if}}@ or @{{#else}}@ encountered outside any @{{#if}}@.
    OrphanBlockToken Text Int
  | -- | The expression inside a @{{#if …}}@ failed to parse;
    --   fields are the raw expression, the opener's line, and the parser error.
    MalformedIfExpression Text Int Text
  deriving stock (Eq, Show, Generic)

-- | Tracks the state of generated files for incremental re-generation
-- and conflict detection. Stored at @.seihou/manifest.json@.
data Manifest = Manifest
  { version :: Int,
    genAt :: UTCTime,
    modules :: [AppliedModule],
    vars :: Map VarName Text,
    files :: Map FilePath FileRecord,
    recipe :: Maybe AppliedRecipe
  }
  deriving stock (Eq, Show, Generic)

-- | Recipe provenance recorded in the manifest when a recipe is used.
data AppliedRecipe = AppliedRecipe
  { name :: RecipeName,
    recipeVersion :: Maybe Text,
    appliedAt :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

-- | A module that has been applied to generate files.
--
-- The @parentVars@ field disambiguates multiple invocations of the same
-- module within a single composition: two 'AppliedModule' entries with
-- the same @name@ and different @parentVars@ represent two legitimate
-- instances. Manifests produced before schema version 2 decode with
-- @parentVars = 'emptyParentVars'@.
data AppliedModule = AppliedModule
  { name :: ModuleName,
    parentVars :: ParentVars,
    source :: FilePath,
    moduleVersion :: Maybe Text,
    appliedAt :: UTCTime,
    removal :: Maybe Removal
  }
  deriving stock (Eq, Show, Generic)

-- | A record of a generated file, stored in the manifest.
data FileRecord = FileRecord
  { hash :: SHA256,
    moduleName :: ModuleName,
    strategy :: Strategy,
    generatedAt :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

-- | A SHA256 content hash, stored as a hex-encoded text string.
newtype SHA256 = SHA256 {unSHA256 :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

-- | Result of the three-state diff: manifest vs plan vs disk.
data DiffResult = DiffResult
  { new :: [PlannedFile],
    modified :: [ModifiedFile],
    unchanged :: [FilePath],
    conflicts :: [ConflictFile],
    orphaned :: [OrphanedFile]
  }
  deriving stock (Eq, Show, Generic)

-- | A file that exists in the plan but not in the manifest or on disk.
data PlannedFile = PlannedFile
  { path :: FilePath,
    moduleName :: ModuleName,
    content :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file that has changed between the manifest and the plan,
-- but the user has not modified the disk copy.
data ModifiedFile = ModifiedFile
  { path :: FilePath,
    moduleName :: ModuleName,
    oldHash :: SHA256,
    newContent :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file where the user has modified the disk copy since it was generated.
data ConflictFile = ConflictFile
  { path :: FilePath,
    moduleName :: ModuleName,
    manifestHash :: SHA256,
    diskHash :: SHA256,
    planContent :: Text
  }
  deriving stock (Eq, Show, Generic)

-- | A file that exists in the manifest but not in the current plan
-- (the module that generated it was removed or no longer produces it).
data OrphanedFile = OrphanedFile
  { path :: FilePath,
    moduleName :: ModuleName
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

-- | Controls the verbosity of diagnostic output.
-- 'LogQuiet' shows only errors, 'LogNormal' shows warnings and errors,
-- 'LogVerbose' shows all messages including info and debug.
-- The derived 'Ord' instance gives @LogQuiet < LogNormal < LogVerbose@,
-- which the Logger interpreters use for filtering.
data LogLevel = LogQuiet | LogNormal | LogVerbose
  deriving stock (Eq, Ord, Show, Generic)

-- | Which config scope to read from or write to.
data ConfigScope
  = ScopeLocal
  | ScopeNamespace Text
  | ScopeContext Text
  | ScopeGlobal
  deriving stock (Eq, Show, Generic)

-- | Warnings emitted during multi-module composition.
-- 'FileOverwritten' records that a file produced by one module was
-- overwritten by a later module in execution order (last-writer-wins).
data CompositionWarning
  = FileOverwritten FilePath ModuleName ModuleName
  | ContentMerged FilePath ModuleName ModuleName
  deriving stock (Eq, Show, Generic)

-- | Status of a tracked file relative to its manifest hash.
-- Used by 'seihou status' to classify files by comparing manifest vs disk.
data TrackedFileStatus
  = -- | Disk hash matches manifest hash
    TfsUnchanged
  | -- | Disk hash differs from manifest hash
    TfsModified
  | -- | File not present on disk
    TfsDeleted
  deriving stock (Eq, Show, Generic)

-- | A tracked file with its path, originating module, and disk status.
data TrackedFile = TrackedFile
  { path :: FilePath,
    moduleName :: ModuleName,
    status :: TrackedFileStatus
  }
  deriving stock (Eq, Show, Generic)
