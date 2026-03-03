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
import Options.Applicative.Help.Pretty (Doc, indent, line, pretty, vsep)
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
    runNoCommands :: Bool,
    runNamespace :: Maybe Text,
    runVerbose :: Bool
  }
  deriving stock (Eq, Show, Generic)

data VarsOpts = VarsOpts
  { varsModule :: ModuleName,
    varsExplain :: Bool,
    varsVars :: [(Text, Text)],
    varsNamespace :: Maybe Text
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
  { validatePath :: Maybe FilePath,
    validateLint :: Bool
  }
  deriving stock (Eq, Show, Generic)

opts :: ParserInfo Command
opts =
  info
    (commandParser <**> helper <**> version)
    ( fullDesc
        <> progDesc "Composable, type-safe project scaffolding"
        <> header "seihou - composable project scaffolding"
        <> footerDoc (Just topLevelFooter)
    )
  where
    version = infoOption "seihou 0.1.0.0" (long "version" <> help "Show version")

topLevelFooter :: Doc
topLevelFooter =
  vsep
    [ pretty ("Getting started:" :: String),
      mempty,
      indent 2 $ vsep [pretty ("seihou init" :: String), pretty ("seihou run <module> --var project.name=my-app" :: String), pretty ("seihou status" :: String)],
      mempty,
      pretty ("Run 'seihou COMMAND --help' for details on a specific command." :: String)
    ]

commandParser :: Parser Command
commandParser =
  subparser
    ( command "init" initInfo
        <> command "run" runInfo
        <> command "vars" varsInfo
        <> command "install" installInfo
        <> command "status" statusInfo
        <> command "new-module" newModuleInfo
        <> command "validate-module" validateInfo
    )

-- Command info blocks

initInfo :: ParserInfo Command
initInfo =
  info
    (pure Init <**> helper)
    ( fullDesc
        <> progDesc "Initialize Seihou configuration"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Creates the Seihou configuration directory at ~/.config/seihou/ with" :: String),
                  pretty ("subdirectories for user modules and installed modules. Also writes a" :: String),
                  pretty ("default config.dhall. Safe to run multiple times; existing files are" :: String),
                  pretty ("left untouched." :: String)
                ]
          )
    )

runInfo :: ParserInfo Command
runInfo =
  info
    (runParser <**> helper)
    ( fullDesc
        <> progDesc "Run modules to generate a project"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Loads the specified module and its dependencies, resolves all variables," :: String),
                  pretty ("compiles a generation plan, and executes it in the current directory." :: String),
                  line,
                  pretty ("Compose multiple modules with -m/--module (repeatable). Override" :: String),
                  pretty ("variables with --var KEY=VALUE (repeatable). Use --dry-run to preview" :: String),
                  pretty ("the plan without writing files, or --diff to compare against disk." :: String),
                  line,
                  pretty ("When re-running, Seihou uses the .seihou/manifest.json to detect" :: String),
                  pretty ("new, modified, unchanged, and conflicting files. Conflicts are" :: String),
                  pretty ("reported and block execution unless --force is used." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $ vsep [pretty ("seihou run haskell-base --var project.name=my-app" :: String), pretty ("seihou run haskell-base -m nix-flake --dry-run" :: String), pretty ("seihou run my-module --diff" :: String)]
                ]
          )
    )

varsInfo :: ParserInfo Command
varsInfo =
  info
    (varsParser <**> helper)
    ( fullDesc
        <> progDesc "Inspect resolved variables"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("By default, lists all variable declarations for the module with their" :: String),
                  pretty ("types, defaults, and descriptions." :: String),
                  line,
                  pretty ("With --explain, resolves variables and shows the provenance of each" :: String),
                  pretty ("value (default, CLI override, environment variable, or export from a" :: String),
                  pretty ("dependency). Use --var KEY=VALUE to supply context for resolution." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $ vsep [pretty ("seihou vars haskell-base" :: String), pretty ("seihou vars haskell-base --explain --var project.name=my-app" :: String)]
                ]
          )
    )

installInfo :: ParserInfo Command
installInfo =
  info
    (installParser <**> helper)
    ( fullDesc
        <> progDesc "Install a module from git"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Clones the git repository, validates that it contains a valid" :: String),
                  pretty ("module.dhall, and copies it to ~/.config/seihou/installed/<name>/." :: String),
                  pretty ("The module name defaults to the repository name (last path segment" :: String),
                  pretty ("without .git). Use --name to override." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou install https://github.com/user/haskell-nix-module.git" :: String)
                ]
          )
    )

statusInfo :: ParserInfo Command
statusInfo =
  info
    (pure Status <**> helper)
    ( fullDesc
        <> progDesc "Show manifest state"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reads .seihou/manifest.json in the current directory and displays" :: String),
                  pretty ("applied modules, tracked files, and resolved variable values." :: String),
                  pretty ("If no manifest exists, reports that and exits successfully." :: String)
                ]
          )
    )

newModuleInfo :: ParserInfo Command
newModuleInfo =
  info
    (newModuleParser <**> helper)
    ( fullDesc
        <> progDesc "Scaffold a new module"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Creates a new module directory with a boilerplate module.dhall and an" :: String),
                  pretty ("example template file at files/README.md.tpl. The output directory" :: String),
                  pretty ("defaults to ./<name>/ in the current directory." :: String),
                  line,
                  pretty ("Module names must match [a-z][a-z0-9-]* (lowercase, hyphens allowed," :: String),
                  pretty ("must start with a letter)." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou new-module my-template --path ~/modules/my-template" :: String)
                ]
          )
    )

validateInfo :: ParserInfo Command
validateInfo =
  info
    (validateParser <**> helper)
    ( fullDesc
        <> progDesc "Validate a module"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Checks that a module directory is well-formed: module.dhall exists and" :: String),
                  pretty ("evaluates, the module name is valid, variable names are unique, prompts" :: String),
                  pretty ("reference declared variables, step source files exist, and exports" :: String),
                  pretty ("reference declared variables." :: String),
                  line,
                  pretty ("PATH defaults to the current directory if not specified." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou validate-module ./my-module" :: String)
                ]
          )
    )

-- Subparsers

runParser :: Parser Command
runParser =
  fmap Run $
    RunOpts
      <$> argument moduleNameReader (metavar "MODULE")
      <*> many
        ( option
            moduleNameReader
            (long "module" <> short 'm' <> metavar "MODULE" <> help "Additional module to compose (repeatable)")
        )
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Variable override (repeatable)")
        )
      <*> switch (long "dry-run" <> help "Show plan without executing")
      <*> switch (long "diff" <> help "Show diff against current disk state")
      <*> switch (long "force" <> help "Auto-resolve conflicts (accept new files)")
      <*> switch (long "no-commands" <> help "Skip shell command steps")
      <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))
      <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")

varsParser :: Parser Command
varsParser =
  fmap Vars $
    VarsOpts
      <$> argument moduleNameReader (metavar "MODULE")
      <*> switch (long "explain" <> help "Show resolved values with provenance")
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Provide variable values for resolution (repeatable)")
        )
      <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))

installParser :: Parser Command
installParser =
  fmap Install $
    InstallOpts
      <$> argument (T.pack <$> str) (metavar "GIT-URL")
      <*> optional (option (T.pack <$> str) (long "name" <> metavar "NAME" <> help "Override installed module name"))

newModuleParser :: Parser Command
newModuleParser =
  fmap NewModule $
    NewModuleOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

validateParser :: Parser Command
validateParser =
  fmap ValidateModule $
    ValidateOpts
      <$> optional (argument str (metavar "PATH"))
      <*> switch (long "lint" <> help "Include advisory lint warnings")

-- Helpers

moduleNameReader :: ReadM ModuleName
moduleNameReader = ModuleName . T.pack <$> str

varPair :: ReadM (Text, Text)
varPair = eitherReader $ \s ->
  case T.breakOn "=" (T.pack s) of
    (k, v)
      | T.null k -> Left "variable name cannot be empty"
      | T.null v -> Left "expected KEY=VALUE format"
      | otherwise -> Right (k, T.drop 1 v)
