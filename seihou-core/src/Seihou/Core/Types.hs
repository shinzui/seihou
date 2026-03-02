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
  )
where

import Data.String (IsString)
import Data.Text (Text)
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
        opContent :: Text
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

-- | Placeholder manifest type. Will be expanded in M5 with file records,
-- hashes, and timestamps.
data Manifest = Manifest
  deriving stock (Eq, Show, Generic)
