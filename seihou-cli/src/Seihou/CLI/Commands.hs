module Seihou.CLI.Commands
  ( Command (..),
    RunOpts (..),
    RemoveOpts (..),
    VarsOpts (..),
    InstallOpts (..),
    NewModuleOpts (..),
    NewRecipeOpts (..),
    ValidateOpts (..),
    ConfigOpts (..),
    ConfigAction (..),
    ContextAction (..),
    ListOpts (..),
    StatusOpts (..),
    BrowseOpts (..),
    OutdatedOpts (..),
    UpgradeOpts (..),
    SchemaUpgradeOpts (..),
    AgentOpts (..),
    AgentCommand (..),
    AssistOpts (..),
    BootstrapOpts (..),
    SetupOpts (..),
    CompletionsCommand (..),
    HelpCommand (..),
    KitCommand (..),
    commandParser,
    opts,
  )
where

import Data.Text qualified as T
import GHC.Generics (Generic)
import Options.Applicative
import Options.Applicative.Help.Pretty (Doc, indent, line, pretty, vsep)
import Seihou.CLI.Help (HelpCommand, helpCommandParser)
import Seihou.CLI.Kit (KitCommand, kitCommandParser)
import Seihou.CLI.Version (seihouVersionWithGit)
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude

data Command
  = Init
  | Run RunOpts
  | Remove RemoveOpts
  | Vars VarsOpts
  | Install InstallOpts
  | Status StatusOpts
  | Diff
  | List ListOpts
  | NewModule NewModuleOpts
  | NewRecipe NewRecipeOpts
  | ValidateModule ValidateOpts
  | Config ConfigOpts
  | Context ContextAction
  | Browse BrowseOpts
  | Outdated OutdatedOpts
  | Upgrade UpgradeOpts
  | SchemaUpgrade SchemaUpgradeOpts
  | Kit KitCommand
  | Agent AgentOpts
  | HelpCmd HelpCommand
  | Completions CompletionsCommand
  deriving stock (Eq, Show, Generic)

data CompletionsCommand
  = CompletionsBash
  | CompletionsZsh
  | CompletionsFish
  deriving stock (Eq, Show, Generic)

data AgentOpts = AgentOpts
  { agentDebug :: Bool,
    agentCommand :: AgentCommand
  }
  deriving stock (Eq, Show, Generic)

data AgentCommand
  = AgentAssist AssistOpts
  | AgentBootstrap BootstrapOpts
  | AgentSetup SetupOpts
  deriving stock (Eq, Show, Generic)

data RunOpts = RunOpts
  { runModule :: Maybe ModuleName,
    runAdditional :: [ModuleName],
    runVars :: [(Text, Text)],
    runDryRun :: Bool,
    runDiff :: Bool,
    runForce :: Bool,
    runNoCommands :: Bool,
    runNamespace :: Maybe Text,
    runContext :: Maybe Text,
    runVerbose :: Bool,
    runSavePrompted :: Maybe Bool,
    runConfirmDefaults :: Bool,
    runCommit :: Bool,
    runCommitMessage :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data RemoveOpts = RemoveOpts
  { removeModule :: ModuleName,
    removeDryRun :: Bool,
    removeForce :: Bool,
    removeVerbose :: Bool
  }
  deriving stock (Eq, Show, Generic)

data VarsOpts = VarsOpts
  { varsModule :: Maybe ModuleName,
    varsExplain :: Bool,
    varsVars :: [(Text, Text)],
    varsNamespace :: Maybe Text,
    varsContext :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data InstallOpts = InstallOpts
  { installSource :: Maybe Text,
    installName :: Maybe Text,
    installModules :: [Text],
    installAll :: Bool
  }
  deriving stock (Eq, Show, Generic)

data NewModuleOpts = NewModuleOpts
  { newModuleName :: Text,
    newModulePath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

data NewRecipeOpts = NewRecipeOpts
  { newRecipeName :: Text,
    newRecipeModules :: [Text],
    newRecipePath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

data ValidateOpts = ValidateOpts
  { validatePath :: Maybe FilePath,
    validateLint :: Bool
  }
  deriving stock (Eq, Show, Generic)

data ConfigAction
  = ConfigSet Text Text
  | ConfigGet Text
  | ConfigUnset Text
  | ConfigList
  deriving stock (Eq, Show, Generic)

data ConfigOpts = ConfigOpts
  { configAction :: ConfigAction,
    configGlobal :: Bool,
    configNamespace :: Maybe Text,
    configContext :: Maybe Text,
    configEffective :: Bool
  }
  deriving stock (Eq, Show, Generic)

data ContextAction
  = ContextSet (Maybe Text)
  | ContextDefault Text
  | ContextShow
  | ContextClear
  | ContextClearDefault
  deriving stock (Eq, Show, Generic)

data ListOpts = ListOpts
  { listRepo :: Maybe Text,
    listTag :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data BrowseOpts = BrowseOpts
  { browseSource :: Text,
    browseTag :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data StatusOpts = StatusOpts
  { statusCheckUpdates :: Bool
  }
  deriving stock (Eq, Show, Generic)

data OutdatedOpts = OutdatedOpts
  { outdatedJson :: Bool
  }
  deriving stock (Eq, Show, Generic)

data UpgradeOpts = UpgradeOpts
  { upgradeModules :: [Text],
    upgradeDryRun :: Bool,
    upgradeJson :: Bool,
    upgradeSkipUnversioned :: Bool
  }
  deriving stock (Eq, Show, Generic)

data SchemaUpgradeOpts = SchemaUpgradeOpts
  { schemaUpgradePath :: Maybe FilePath,
    schemaUpgradeDryRun :: Bool,
    schemaUpgradeAll :: Bool
  }
  deriving stock (Eq, Show, Generic)

data AssistOpts = AssistOpts
  { assistPrompt :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data BootstrapOpts = BootstrapOpts
  { bootstrapPrompt :: Maybe Text,
    bootstrapRepo :: Bool
  }
  deriving stock (Eq, Show, Generic)

data SetupOpts = SetupOpts
  { setupPrompt :: Maybe Text
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
    version = infoOption (T.unpack seihouVersionWithGit) (long "version" <> help "Show version")

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
  hsubparser
    ( command "init" initInfo
        <> command "run" runInfo
        <> command "remove" removeInfo
        <> command "status" statusInfo
        <> command "diff" diffInfo
    )
    <|> hsubparser
      ( command "list" listInfo
          <> command "install" installInfo
          <> command "browse" browseInfo
          <> command "outdated" outdatedInfo
          <> command "upgrade" upgradeInfo
          <> commandGroup "Module management:"
          <> hidden
      )
    <|> hsubparser
      ( command "new-module" newModuleInfo
          <> command "new-recipe" newRecipeInfo
          <> command "validate-module" validateInfo
          <> command "vars" varsInfo
          <> command "schema-upgrade" schemaUpgradeInfo
          <> commandGroup "Authoring:"
          <> hidden
      )
    <|> hsubparser
      ( command "config" configInfo
          <> command "context" contextInfo
          <> commandGroup "Configuration:"
          <> hidden
      )
    <|> hsubparser
      ( command "agent" agentInfo
          <> command "kit" kitInfo
          <> commandGroup "AI agent:"
          <> hidden
      )
    <|> hsubparser
      ( command "help" helpCmdInfo
          <> command "completions" completionsInfo
          <> commandGroup "Help & shell integration:"
          <> hidden
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
                  indent 2 $
                    vsep
                      [ pretty ("seihou run haskell-base --var project.name=my-app" :: String),
                        pretty ("seihou run haskell-base -m nix-flake --dry-run" :: String),
                        pretty ("seihou run my-module --diff" :: String),
                        pretty ("seihou run haskell-base --confirm-defaults   # review and override default values" :: String)
                      ]
                ]
          )
    )

removeInfo :: ParserInfo Command
removeInfo =
  info
    (removeParser <**> helper)
    ( fullDesc
        <> progDesc "Remove an applied module and delete its generated files"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Removes a module that was previously applied via 'seihou run' and" :: String),
                  pretty ("reverses its effects. Only modules with a 'removal' section" :: String),
                  pretty ("in their module.dhall can be removed." :: String),
                  line,
                  pretty ("Files that have been modified since generation are treated as" :: String),
                  pretty ("conflicts. Use --force to delete them without prompting, or" :: String),
                  pretty ("respond interactively to keep or delete each one." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou remove haskell-base" :: String),
                        pretty ("seihou remove haskell-base --dry-run" :: String),
                        pretty ("seihou remove haskell-base --force" :: String)
                      ]
                ]
          )
    )

removeParser :: Parser Command
removeParser =
  fmap Remove $
    RemoveOpts
      <$> argument moduleNameReader (metavar "MODULE" <> help "Module to remove")
      <*> switch (long "dry-run" <> help "Show removal plan without executing")
      <*> switch (long "force" <> help "Delete conflicted files without prompting")
      <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")

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
        <> progDesc "Install module(s) from git"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Clones the git repository and installs modules to" :: String),
                  pretty ("~/.config/seihou/installed/<name>/." :: String),
                  line,
                  pretty ("If the repository contains a seihou-registry.dhall file, it is" :: String),
                  pretty ("treated as a multi-module registry. Use --module to pick specific" :: String),
                  pretty ("modules or --all to install everything. Without either flag, you" :: String),
                  pretty ("will be prompted to choose interactively." :: String),
                  line,
                  pretty ("For single-module repositories (just a root module.dhall), the" :: String),
                  pretty ("module name defaults to the repository name. Use --name to override." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou install https://github.com/user/haskell-module.git" :: String),
                        pretty ("seihou install https://github.com/user/templates.git --all" :: String),
                        pretty ("seihou install https://github.com/user/templates.git --module haskell-base" :: String)
                      ]
                ]
          )
    )

statusInfo :: ParserInfo Command
statusInfo =
  info
    (statusParser <**> helper)
    ( fullDesc
        <> progDesc "Show manifest state"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reads .seihou/manifest.json in the current directory and displays" :: String),
                  pretty ("applied modules, tracked files, and resolved variable values." :: String),
                  pretty ("If no manifest exists, reports that and exits successfully." :: String),
                  line,
                  pretty ("Use --check-updates to also report which applied modules have newer" :: String),
                  pretty ("versions available from their source repository. This requires network" :: String),
                  pretty ("access and will clone each source repo shallowly." :: String)
                ]
          )
    )

statusParser :: Parser Command
statusParser =
  fmap Status $
    StatusOpts
      <$> switch
        ( long "check-updates"
            <> short 'u'
            <> help "Check installed modules for available updates (requires network)"
        )

diffInfo :: ParserInfo Command
diffInfo =
  info
    (pure Diff <**> helper)
    ( fullDesc
        <> progDesc "Show changes since last generation"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Compares tracked files in .seihou/manifest.json against the current" :: String),
                  pretty ("disk state. Shows files that have been modified or deleted since the" :: String),
                  pretty ("last 'seihou run'. Does not load modules or resolve variables." :: String)
                ]
          )
    )

listInfo :: ParserInfo Command
listInfo =
  info
    (listParser <**> helper)
    ( fullDesc
        <> progDesc "List available modules"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Scans all module search paths and lists every available module with" :: String),
                  pretty ("its name, description, and source location (project, user, or installed)." :: String),
                  pretty ("Modules that fail to load are shown with an error indicator." :: String),
                  line,
                  pretty ("Use --repo and --tag to filter the output." :: String)
                ]
          )
    )

listParser :: Parser Command
listParser =
  fmap List $
    ListOpts
      <$> optional (option (T.pack <$> str) (long "repo" <> metavar "REPO" <> help "Filter by repository name"))
      <*> optional (option (T.pack <$> str) (long "tag" <> metavar "TAG" <> help "Filter by tag"))

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

configInfo :: ParserInfo Command
configInfo =
  info
    (configParser <**> helper)
    ( fullDesc
        <> progDesc "Read and write config values"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Manage config values across local, namespace, and global scopes." :: String),
                  pretty ("Default scope is local (.seihou/config.dhall). Use --global or" :: String),
                  pretty ("--namespace NS for other scopes." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou config set project.name my-app" :: String),
                        pretty ("seihou config get project.name" :: String),
                        pretty ("seihou config list" :: String),
                        pretty ("seihou config set license MIT --global" :: String),
                        pretty ("seihou config unset license --global" :: String),
                        pretty ("seihou config list --namespace haskell" :: String)
                      ]
                ]
          )
    )

-- Subparsers

runParser :: Parser Command
runParser =
  fmap Run $
    RunOpts
      <$> optional (argument moduleNameReader (metavar "MODULE"))
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
      <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Override context for config lookup"))
      <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")
      <*> optional
        ( flag' True (long "save-prompted" <> help "Save prompted values to local config without asking")
            <|> flag' False (long "no-save-prompted" <> help "Do not offer to save prompted values")
        )
      <*> switch (long "confirm-defaults" <> help "Step through default values and confirm or override each one")
      <*> switch (long "commit" <> help "Commit generated files to git after execution (uses AI-generated message)")
      <*> optional (option (T.pack <$> str) (long "commit-message" <> metavar "MSG" <> help "Custom commit message (implies --commit)"))

varsParser :: Parser Command
varsParser =
  fmap Vars $
    VarsOpts
      <$> optional (argument moduleNameReader (metavar "MODULE"))
      <*> switch (long "explain" <> help "Show resolved values with provenance")
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Provide variable values for resolution (repeatable)")
        )
      <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))
      <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Override context for config lookup"))

installParser :: Parser Command
installParser =
  fmap Install $
    InstallOpts
      <$> optional (argument (T.pack <$> str) (metavar "GIT-URL"))
      <*> optional (option (T.pack <$> str) (long "name" <> metavar "NAME" <> help "Override installed module name"))
      <*> many (option (T.pack <$> str) (long "module" <> metavar "MODULE" <> help "Install specific module from registry (repeatable)"))
      <*> switch (long "all" <> help "Install all modules from registry")

newModuleParser :: Parser Command
newModuleParser =
  fmap NewModule $
    NewModuleOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

newRecipeInfo :: ParserInfo Command
newRecipeInfo =
  info
    (newRecipeParser <**> helper)
    ( fullDesc
        <> progDesc "Scaffold a new recipe"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Creates a new recipe directory with a boilerplate recipe.dhall." :: String),
                  pretty ("The output directory defaults to ./<name>/ in the current directory." :: String),
                  line,
                  pretty ("Recipe names must match [a-z][a-z0-9-]* (lowercase, hyphens allowed," :: String),
                  pretty ("must start with a letter)." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou new-recipe haskell-library --module nix-flake --module cabal-ghc" :: String)
                ]
          )
    )

newRecipeParser :: Parser Command
newRecipeParser =
  fmap NewRecipe $
    NewRecipeOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> many (option (T.pack <$> str) (long "module" <> short 'm' <> metavar "MODULE" <> help "Module to include in the recipe"))
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

validateParser :: Parser Command
validateParser =
  fmap ValidateModule $
    ValidateOpts
      <$> optional (argument str (metavar "PATH"))
      <*> switch (long "lint" <> help "Include advisory lint warnings")

configParser :: Parser Command
configParser =
  fmap Config $
    ConfigOpts
      <$> configActionParser
      <*> switch (long "global" <> short 'g' <> help "Use global scope (~/.config/seihou/config.dhall)")
      <*> optional (option (T.pack <$> str) (long "namespace" <> short 'n' <> metavar "NS" <> help "Use namespace scope"))
      <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Use context scope"))
      <*> switch (long "effective" <> short 'e' <> help "Show merged config across all scopes (with list)")

configActionParser :: Parser ConfigAction
configActionParser =
  subparser
    ( command "set" (info configSetParser (progDesc "Set a config value"))
        <> command "get" (info configGetParser (progDesc "Get a config value"))
        <> command "unset" (info configUnsetParser (progDesc "Remove a config value"))
        <> command "list" (info (pure ConfigList) (progDesc "List config values"))
    )

configSetParser :: Parser ConfigAction
configSetParser =
  ConfigSet
    <$> argument (T.pack <$> str) (metavar "KEY")
    <*> argument (T.pack <$> str) (metavar "VALUE")

configGetParser :: Parser ConfigAction
configGetParser = ConfigGet <$> argument (T.pack <$> str) (metavar "KEY")

configUnsetParser :: Parser ConfigAction
configUnsetParser = ConfigUnset <$> argument (T.pack <$> str) (metavar "KEY")

contextInfo :: ParserInfo Command
contextInfo =
  info
    (contextParser <**> helper)
    ( fullDesc
        <> progDesc "Manage the active context (work, personal, etc.)"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Contexts allow variables like user.email to resolve differently" :: String),
                  pretty ("depending on whether you're working in a 'work' or 'personal'" :: String),
                  pretty ("context. Context config files live at" :: String),
                  pretty ("~/.config/seihou/contexts/<name>/config.dhall." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou context show                # show active context" :: String),
                        pretty ("seihou context set work            # set project context" :: String),
                        pretty ("seihou context default personal    # set global default" :: String),
                        pretty ("seihou context clear               # remove project context" :: String),
                        pretty ("seihou context clear-default       # remove global default" :: String)
                      ]
                ]
          )
    )

contextParser :: Parser Command
contextParser =
  fmap Context $
    subparser
      ( command "show" (info (pure ContextShow) (progDesc "Show the active context and its source"))
          <> command "set" (info (ContextSet <$> optional (argument (T.pack <$> str) (metavar "NAME"))) (progDesc "Set the project context (.seihou/context)"))
          <> command "default" (info (ContextDefault <$> argument (T.pack <$> str) (metavar "NAME")) (progDesc "Set the global default context (~/.config/seihou/default-context)"))
          <> command "clear" (info (pure ContextClear) (progDesc "Remove the project context file"))
          <> command "clear-default" (info (pure ContextClearDefault) (progDesc "Remove the global default context"))
      )

browseInfo :: ParserInfo Command
browseInfo =
  info
    (browseParser <**> helper)
    ( fullDesc
        <> progDesc "Browse modules in a git repository"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Clones the repository and shows available modules without" :: String),
                  pretty ("installing anything. For multi-module repos with a" :: String),
                  pretty ("seihou-registry.dhall, displays all modules with descriptions" :: String),
                  pretty ("and tags. Use --tag to filter by tag." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou browse https://github.com/user/templates.git" :: String),
                        pretty ("seihou browse https://github.com/user/templates.git --tag haskell" :: String)
                      ]
                ]
          )
    )

browseParser :: Parser Command
browseParser =
  fmap Browse $
    BrowseOpts
      <$> argument (T.pack <$> str) (metavar "GIT-URL")
      <*> optional (option (T.pack <$> str) (long "tag" <> metavar "TAG" <> help "Filter modules by tag"))

outdatedInfo :: ParserInfo Command
outdatedInfo =
  info
    (outdatedParser <**> helper)
    ( fullDesc
        <> progDesc "Check installed modules for newer versions"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Checks each installed module's source registry for a newer version." :: String),
                  pretty ("Modules without version information are shown as 'unversioned'." :: String),
                  pretty ("Only modules installed via 'seihou install' are checked." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou outdated" :: String)
                ]
          )
    )

outdatedParser :: Parser Command
outdatedParser =
  fmap Outdated $
    OutdatedOpts
      <$> switch (long "json" <> help "Output as JSON")

upgradeInfo :: ParserInfo Command
upgradeInfo =
  info
    (upgradeParser <**> helper)
    ( fullDesc
        <> progDesc "Upgrade installed modules to latest versions"
        <> footerDoc (Just upgradeFooter)
    )

upgradeParser :: Parser Command
upgradeParser =
  fmap Upgrade $
    UpgradeOpts
      <$> many (argument (T.pack <$> str) (metavar "MODULE" <> help "Module(s) to upgrade (default: all)"))
      <*> switch (long "dry-run" <> help "Show what would be upgraded without making changes")
      <*> switch (long "json" <> help "Output as JSON")
      <*> switch (long "skip-unversioned" <> help "Skip modules without version information")

upgradeFooter :: Doc
upgradeFooter =
  vsep
    [ pretty ("Upgrades installed modules to the latest version available from their" :: String),
      pretty ("source repository. Only modules installed via 'seihou install' are checked." :: String),
      pretty ("Modules without version information are upgraded by default." :: String),
      pretty ("Use --skip-unversioned to skip them." :: String),
      line,
      pretty ("With no arguments, checks all installed modules. Pass module names to" :: String),
      pretty ("upgrade specific modules only." :: String),
      line,
      pretty ("Examples:" :: String),
      indent 2 $
        vsep
          [ pretty ("seihou upgrade                       # upgrade all installed modules" :: String),
            pretty ("seihou upgrade haskell-base           # upgrade a specific module" :: String),
            pretty ("seihou upgrade --dry-run              # preview without changes" :: String),
            pretty ("seihou upgrade --skip-unversioned     # skip unversioned modules" :: String)
          ]
    ]

schemaUpgradeInfo :: ParserInfo Command
schemaUpgradeInfo =
  info
    (schemaUpgradeParser <**> helper)
    ( fullDesc
        <> progDesc "Upgrade module.dhall files to the current schema"
        <> footerDoc (Just schemaUpgradeFooter)
    )

schemaUpgradeParser :: Parser Command
schemaUpgradeParser =
  fmap SchemaUpgrade $
    SchemaUpgradeOpts
      <$> optional (argument str (metavar "PATH" <> help "Module directory (default: current directory)"))
      <*> switch (long "dry-run" <> help "Show what would change without modifying files")
      <*> switch (long "all" <> help "Upgrade all discovered modules")

schemaUpgradeFooter :: Doc
schemaUpgradeFooter =
  vsep
    [ pretty ("Detects missing or outdated fields in module.dhall files and" :: String),
      pretty ("rewrites them to match the current schema. Handles:" :: String),
      line,
      indent 2 $
        vsep
          [ pretty ("- Missing 'version' field" :: String),
            pretty ("- Missing 'patch' field on steps" :: String),
            pretty ("- Missing 'commands' field" :: String),
            pretty ("- Bare string dependencies (converts to record form)" :: String),
            pretty ("- 'List Text' dependency type annotation" :: String)
          ],
      line,
      pretty ("Examples:" :: String),
      indent 2 $
        vsep
          [ pretty ("seihou schema-upgrade                  # upgrade ./module.dhall" :: String),
            pretty ("seihou schema-upgrade ./my-module       # upgrade specific module" :: String),
            pretty ("seihou schema-upgrade --dry-run         # preview changes" :: String),
            pretty ("seihou schema-upgrade --all             # upgrade all modules" :: String)
          ]
    ]

kitInfo :: ParserInfo Command
kitInfo =
  info
    (Kit <$> kitCommandParser <**> helper)
    ( fullDesc
        <> progDesc "Manage Claude Code skills and subagents"
    )

agentInfo :: ParserInfo Command
agentInfo =
  info
    (agentParser <**> helper)
    ( fullDesc
        <> progDesc "AI-powered agent commands"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Agent subcommands provide AI-assisted workflows powered by" :: String),
                  pretty ("Claude Code. Requires the 'claude' CLI to be installed." :: String),
                  line,
                  pretty ("Use --debug with any subcommand to print the resolved system" :: String),
                  pretty ("prompt instead of launching Claude." :: String),
                  line,
                  pretty ("Available subcommands:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("assist      Interactive template authoring session" :: String),
                        pretty ("bootstrap   Bootstrap a new module or multi-module repo" :: String),
                        pretty ("setup       Guided project setup: configure, run, and commit" :: String)
                      ]
                ]
          )
    )

agentParser :: Parser Command
agentParser =
  fmap Agent $
    AgentOpts
      <$> switch (long "debug" <> help "Print the resolved system prompt and exit")
      <*> agentCommandParser

agentCommandParser :: Parser AgentCommand
agentCommandParser =
  subparser
    ( command "assist" agentAssistInfo
        <> command "bootstrap" agentBootstrapInfo
        <> command "setup" agentSetupInfo
    )

agentAssistInfo :: ParserInfo AgentCommand
agentAssistInfo =
  info
    (agentAssistParser <**> helper)
    ( fullDesc
        <> progDesc "Launch AI-assisted template authoring session"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Launches an interactive Claude Code session pre-configured for" :: String),
                  pretty ("creating and modifying Seihou modules. The agent gathers context" :: String),
                  pretty ("about your current directory (existing modules, manifest state," :: String),
                  pretty ("available modules) and starts with full knowledge of the Seihou" :: String),
                  pretty ("module schema." :: String),
                  line,
                  pretty ("The agent can run seihou commands (new-module, validate-module," :: String),
                  pretty ("run --dry-run, vars, list), git commands, and read/write files." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent assist" :: String),
                        pretty ("seihou agent assist \"create a rust project template\"" :: String),
                        pretty ("seihou agent assist \"add a LICENSE step to my-module\"" :: String)
                      ]
                ]
          )
    )

agentAssistParser :: Parser AgentCommand
agentAssistParser =
  fmap AgentAssist $
    AssistOpts
      <$> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Initial prompt describing what you want to do"))

agentBootstrapInfo :: ParserInfo AgentCommand
agentBootstrapInfo =
  info
    (agentBootstrapParser <**> helper)
    ( fullDesc
        <> progDesc "Bootstrap a new module or multi-module repository"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Launches an interactive Claude Code session that guides you through" :: String),
                  pretty ("creating a complete Seihou module from scratch — defining variables," :: String),
                  pretty ("writing templates, setting up prompts, and validating the result." :: String),
                  line,
                  pretty ("Use --repo to bootstrap a multi-module repository with a" :: String),
                  pretty ("seihou-registry.dhall and multiple module directories." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent bootstrap" :: String),
                        pretty ("seihou agent bootstrap \"a haskell project template\"" :: String),
                        pretty ("seihou agent bootstrap --repo" :: String),
                        pretty ("seihou agent bootstrap --repo \"team templates for rust projects\"" :: String)
                      ]
                ]
          )
    )

agentBootstrapParser :: Parser AgentCommand
agentBootstrapParser =
  fmap AgentBootstrap $
    BootstrapOpts
      <$> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Description of what to bootstrap"))
      <*> switch (long "repo" <> help "Bootstrap a multi-module repository with registry")

agentSetupInfo :: ParserInfo AgentCommand
agentSetupInfo =
  info
    (agentSetupParser <**> helper)
    ( fullDesc
        <> progDesc "Guided project setup: configure, run, and commit"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Launches an interactive Claude Code session that guides you through" :: String),
                  pretty ("using a Seihou module: selecting a module, configuring variables and" :: String),
                  pretty ("context, running the module to generate files, verifying the output," :: String),
                  pretty ("and committing the changes to git." :: String),
                  line,
                  pretty ("The agent can run all seihou commands (run, config, context, vars," :: String),
                  pretty ("status, diff, list, install), git commands, and read/write files." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent setup" :: String),
                        pretty ("seihou agent setup \"set up a haskell project with nix\"" :: String),
                        pretty ("seihou agent setup \"add nix-flake module to this project\"" :: String)
                      ]
                ]
          )
    )

agentSetupParser :: Parser AgentCommand
agentSetupParser =
  fmap AgentSetup $
    SetupOpts
      <$> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Description of what you want to set up"))

helpCmdInfo :: ParserInfo Command
helpCmdInfo =
  info
    (HelpCmd <$> helpCommandParser <**> helper)
    ( fullDesc
        <> progDesc "Show help for commands and topics"
    )

completionsInfo :: ParserInfo Command
completionsInfo =
  info
    (completionsParser <**> helper)
    ( fullDesc
        <> progDesc "Generate shell completion scripts"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Outputs a completion script for the specified shell. Source the" :: String),
                  pretty ("script in your shell profile to enable Tab completion for all" :: String),
                  pretty ("seihou commands, subcommands, and flags." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou completions bash > ~/.local/share/bash-completion/completions/seihou" :: String),
                        pretty ("seihou completions zsh  > ~/.zfunc/_seihou" :: String),
                        pretty ("seihou completions fish > ~/.config/fish/completions/seihou.fish" :: String)
                      ]
                ]
          )
    )

completionsParser :: Parser Command
completionsParser =
  fmap Completions $
    subparser
      ( command "bash" (info (pure CompletionsBash) (progDesc "Generate Bash completion script"))
          <> command "zsh" (info (pure CompletionsZsh) (progDesc "Generate Zsh completion script"))
          <> command "fish" (info (pure CompletionsFish) (progDesc "Generate Fish completion script"))
      )

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
