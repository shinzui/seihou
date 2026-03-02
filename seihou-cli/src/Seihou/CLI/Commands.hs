module Seihou.CLI.Commands
  ( Command (..),
    RunOpts (..),
    VarsOpts (..),
    InstallOpts (..),
    NewModuleOpts (..),
    ValidateOpts (..),
    commandParser,
    opts,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Options.Applicative
import Seihou.Core.Types (ModuleName (..))

data Command
  = Init
  | Run RunOpts
  | Vars VarsOpts
  | Install InstallOpts
  | Status
  | NewModule NewModuleOpts
  | ValidateModule ValidateOpts
  deriving stock (Eq, Show, Generic)

data RunOpts = RunOpts
  { runModule :: ModuleName,
    runAdditional :: [ModuleName],
    runVars :: [(Text, Text)],
    runDryRun :: Bool,
    runDiff :: Bool,
    runForce :: Bool,
    runNoCommands :: Bool
  }
  deriving stock (Eq, Show, Generic)

data VarsOpts = VarsOpts
  { varsModule :: ModuleName,
    varsExplain :: Bool,
    varsVars :: [(Text, Text)]
  }
  deriving stock (Eq, Show, Generic)

data InstallOpts = InstallOpts
  { installSource :: Text,
    installName :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data NewModuleOpts = NewModuleOpts
  { newModuleName :: Text,
    newModulePath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

data ValidateOpts = ValidateOpts
  { validatePath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

opts :: ParserInfo Command
opts =
  info
    (commandParser <**> helper <**> version)
    ( fullDesc
        <> progDesc "Composable, type-safe project scaffolding"
        <> header "seihou - composable project scaffolding"
    )
  where
    version = infoOption "seihou 0.1.0.0" (long "version" <> help "Show version")

commandParser :: Parser Command
commandParser =
  subparser
    ( command "init" (info (pure Init) (progDesc "Initialize Seihou configuration"))
        <> command "run" (info runParser (progDesc "Run modules to generate a project"))
        <> command "vars" (info varsParser (progDesc "Inspect resolved variables"))
        <> command "install" (info installParser (progDesc "Install a module from git"))
        <> command "status" (info (pure Status) (progDesc "Show manifest state"))
        <> command "new-module" (info newModuleParser (progDesc "Scaffold a new module"))
        <> command "validate-module" (info validateParser (progDesc "Validate a module"))
    )

runParser :: Parser Command
runParser =
  fmap Run $
    RunOpts
      <$> argument moduleNameReader (metavar "MODULE")
      <*> many
        ( option
            moduleNameReader
            (long "module" <> short 'm' <> metavar "MODULE" <> help "Additional module to compose")
        )
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Variable override")
        )
      <*> switch (long "dry-run" <> help "Show plan without executing")
      <*> switch (long "diff" <> help "Show diff against disk")
      <*> switch (long "force" <> help "Auto-resolve conflicts")
      <*> switch (long "no-commands" <> help "Skip shell command steps")

varsParser :: Parser Command
varsParser =
  fmap Vars $
    VarsOpts
      <$> argument moduleNameReader (metavar "MODULE")
      <*> switch (long "explain" <> help "Show provenance for each value")
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Provide values for resolution context")
        )

installParser :: Parser Command
installParser =
  fmap Install $
    InstallOpts
      <$> argument (T.pack <$> str) (metavar "GIT-URL")
      <*> optional (option (T.pack <$> str) (long "name" <> metavar "NAME" <> help "Override module name"))

newModuleParser :: Parser Command
newModuleParser =
  fmap NewModule $
    NewModuleOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory"))

validateParser :: Parser Command
validateParser =
  fmap ValidateModule $
    ValidateOpts
      <$> optional (argument str (metavar "PATH"))

moduleNameReader :: ReadM ModuleName
moduleNameReader = ModuleName . T.pack <$> str

varPair :: ReadM (Text, Text)
varPair = eitherReader $ \s ->
  case T.breakOn "=" (T.pack s) of
    (k, v)
      | T.null k -> Left "variable name cannot be empty"
      | T.null v -> Left "expected KEY=VALUE format"
      | otherwise -> Right (k, T.drop 1 v)
