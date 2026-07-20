module Seihou.CLI.Commands
  ( Command (..),
    RunOpts (..),
    UpdateOpts (..),
    RemoveOpts (..),
    VarsOpts (..),
    InstallOpts (..),
    NewModuleOpts (..),
    NewRecipeOpts (..),
    NewBlueprintOpts (..),
    NewPromptOpts (..),
    ValidateOpts (..),
    ValidateBlueprintOpts (..),
    ValidatePromptOpts (..),
    ConfigOpts (..),
    ConfigAction (..),
    ContextAction (..),
    ListOpts (..),
    StatusOpts (..),
    BrowseOpts (..),
    OutdatedOpts (..),
    UpgradeOpts (..),
    MigrateOpts (..),
    SchemaUpgradeOpts (..),
    AgentOpts (..),
    AgentModelsOpts (..),
    AgentCommand (..),
    AssistOpts (..),
    BootstrapOpts (..),
    SetupOpts (..),
    BlueprintRunOpts (..),
    PromptCommand (..),
    PromptRunOpts (..),
    CompletionsCommand (..),
    ExtensionCommand (..),
    HelpCommand (..),
    KitCommand (..),
    RegistryCommand (..),
    SyncVersionsOpts (..),
    ValidateRegistryOpts (..),
    commandParser,
    opts,
  )
where

import Data.Text qualified as T
import GHC.Generics (Generic)
import Options.Applicative
import Options.Applicative.Help.Pretty (Doc, indent, line, pretty, vsep)
import Seihou.CLI.Extension (ExtensionRunOpts (..))
import Seihou.CLI.Help (HelpCommand, helpCommandParser)
import Seihou.CLI.Kit (KitCommand, kitCommandParser)
import Seihou.CLI.Migrate (MigrateOpts (..))
import Seihou.CLI.Registry (RegistryCommand (..))
import Seihou.CLI.Registry.Sync (SyncVersionsOpts (..))
import Seihou.CLI.Registry.Validate (ValidateRegistryOpts (..))
import Seihou.CLI.Version (seihouVersionWithGit)
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude

data Command
  = Init
  | Run RunOpts
  | Update UpdateOpts
  | Remove RemoveOpts
  | Vars VarsOpts
  | Install InstallOpts
  | Status StatusOpts
  | Diff
  | List ListOpts
  | NewModule NewModuleOpts
  | NewRecipe NewRecipeOpts
  | NewBlueprint NewBlueprintOpts
  | NewPrompt NewPromptOpts
  | ValidateModule ValidateOpts
  | ValidateBlueprint ValidateBlueprintOpts
  | ValidatePrompt ValidatePromptOpts
  | Config ConfigOpts
  | Context ContextAction
  | Browse BrowseOpts
  | Outdated OutdatedOpts
  | Upgrade UpgradeOpts
  | Migrate MigrateOpts
  | SchemaUpgrade SchemaUpgradeOpts
  | Registry RegistryCommand
  | Kit KitCommand
  | Agent AgentOpts
  | Prompt PromptCommand
  | Extension ExtensionCommand
  | HelpCmd HelpCommand
  | Completions CompletionsCommand
  deriving stock (Eq, Show, Generic)

data ExtensionCommand
  = ExtensionRun ExtensionRunOpts
  deriving stock (Eq, Show, Generic)

data CompletionsCommand
  = CompletionsBash
  | CompletionsZsh
  | CompletionsFish
  deriving stock (Eq, Show, Generic)

data AgentOpts = AgentOpts
  { agentDebug :: Bool,
    agentProvider :: Maybe Text,
    agentModel :: Maybe Text,
    agentCommand :: AgentCommand
  }
  deriving stock (Eq, Show, Generic)

data AgentModelsOpts = AgentModelsOpts
  { modelsProvider :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data AgentCommand
  = AgentAssist AssistOpts
  | AgentBootstrap BootstrapOpts
  | AgentSetup SetupOpts
  | AgentRun BlueprintRunOpts
  | AgentModels AgentModelsOpts
  | AgentConfigShow
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
    runCommitMessage :: Maybe Text,
    -- | When 'True', a pre-flight pending-migration check that finds
    -- any chain for one of the composed modules will apply that chain
    -- to the project (and the manifest) before the run plan is
    -- computed. When 'False' (the default), pending chains cause
    -- 'seihou run' to refuse with an actionable message and a
    -- non-zero exit, so a user never silently writes new templates
    -- into paths a migration would have moved.
    runWithMigrations :: Bool
  }
  deriving stock (Eq, Show, Generic)

data UpdateOpts = UpdateOpts
  { updateTargets :: [Text],
    updateVars :: [(Text, Text)],
    updateDryRun :: Bool,
    updateJson :: Bool,
    updateReconfigure :: Bool,
    updateForce :: Bool,
    updateRunAllCommands :: Bool,
    updateNoCommands :: Bool,
    updateCommit :: Bool,
    updateCommitMessage :: Maybe Text
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

data NewBlueprintOpts = NewBlueprintOpts
  { newBlueprintName :: Text,
    newBlueprintPath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

data NewPromptOpts = NewPromptOpts
  { newPromptName :: Text,
    newPromptPath :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

data ValidateOpts = ValidateOpts
  { validatePath :: Maybe FilePath,
    validateLint :: Bool
  }
  deriving stock (Eq, Show, Generic)

data ValidateBlueprintOpts = ValidateBlueprintOpts
  { validateBlueprintPath :: Maybe FilePath,
    validateBlueprintLint :: Bool
  }
  deriving stock (Eq, Show, Generic)

data ValidatePromptOpts = ValidatePromptOpts
  { validatePromptPath :: Maybe FilePath,
    validatePromptLint :: Bool
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
    listTag :: Maybe Text,
    listModulesOnly :: Bool,
    listRecipesOnly :: Bool,
    listBlueprintsOnly :: Bool,
    listPromptsOnly :: Bool
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
    upgradeSkipUnversioned :: Bool,
    -- | If 'True', after each successful per-module upgrade, also run
    -- 'Seihou.CLI.Migrate.runMigrate' against the *current project*
    -- (cwd), if and only if that module is applied locally. Default
    -- 'False'; the unset path emits a one-line advisory pointing the
    -- user at @seihou update@ when migrations would be pending.
    upgradeWithMigrations :: Bool
  }
  deriving stock (Eq, Show, Generic)

data SchemaUpgradeOpts = SchemaUpgradeOpts
  { schemaUpgradePath :: Maybe FilePath,
    schemaUpgradeDryRun :: Bool,
    schemaUpgradeAll :: Bool
  }
  deriving stock (Eq, Show, Generic)

data AssistOpts = AssistOpts
  { assistPrompt :: Maybe Text,
    assistProvider :: Maybe Text,
    assistModel :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data BootstrapOpts = BootstrapOpts
  { bootstrapPrompt :: Maybe Text,
    bootstrapRepo :: Bool,
    bootstrapProvider :: Maybe Text,
    bootstrapModel :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data SetupOpts = SetupOpts
  { setupPrompt :: Maybe Text,
    setupProvider :: Maybe Text,
    setupModel :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data BlueprintRunOpts = BlueprintRunOpts
  { runBlueprintName :: ModuleName,
    runBlueprintPrompt :: Maybe Text,
    runBlueprintVars :: [(Text, Text)],
    runBlueprintNoBaseline :: Bool,
    runBlueprintNamespace :: Maybe Text,
    runBlueprintContext :: Maybe Text,
    runBlueprintVerbose :: Bool,
    runBlueprintForce :: Bool,
    runBlueprintProvider :: Maybe Text,
    runBlueprintModel :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

data PromptCommand
  = PromptRun PromptRunOpts
  deriving stock (Eq, Show, Generic)

data PromptRunOpts = PromptRunOpts
  { runPromptName :: ModuleName,
    runPromptPrompt :: Maybe Text,
    runPromptVars :: [(Text, Text)],
    runPromptNamespace :: Maybe Text,
    runPromptContext :: Maybe Text,
    runPromptVerbose :: Bool,
    runPromptDebug :: Bool,
    runPromptProvider :: Maybe Text,
    runPromptModel :: Maybe Text
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
      pretty ("Learn more:" :: String),
      mempty,
      indent 2 $
        vsep
          [ pretty ("seihou help          # list all help topics" :: String),
            pretty ("seihou help modules  # how modules work" :: String),
            pretty ("seihou help update   # safely update recorded project applications" :: String),
            pretty ("seihou help migrations  # apply author-declared migrations between versions" :: String)
          ],
      mempty,
      pretty ("Run 'seihou COMMAND --help' for details on a specific command." :: String)
    ]

commandParser :: Parser Command
commandParser =
  hsubparser
    ( command "init" initInfo
        <> command "run" runInfo
        <> command "update" updateInfo
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
          <> command "migrate" migrateInfo
          <> commandGroup "Module management:"
          <> hidden
      )
    <|> hsubparser
      ( command "new-module" newModuleInfo
          <> command "new-recipe" newRecipeInfo
          <> command "new-blueprint" newBlueprintInfo
          <> command "new-prompt" newPromptInfo
          <> command "validate-module" validateInfo
          <> command "validate-blueprint" validateBlueprintInfo
          <> command "validate-prompt" validatePromptInfo
          <> command "vars" varsInfo
          <> command "schema-upgrade" schemaUpgradeInfo
          <> command "registry" registryInfo
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
          <> command "prompt" promptInfo
          <> command "kit" kitInfo
          <> commandGroup "AI agent:"
          <> hidden
      )
    <|> hsubparser
      ( command "help" helpCmdInfo
          <> command "completions" completionsInfo
          <> command "extension" extensionInfo
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
        <> progDesc "Apply a module initially or reconfigure it explicitly"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Applies the specified module for the first time, or deliberately" :: String),
                  pretty ("reconfigures it. Variables are resolved and a generation plan executes" :: String),
                  pretty ("in the current directory." :: String),
                  line,
                  pretty ("Compose multiple modules with -m/--module (repeatable). Override" :: String),
                  pretty ("variables with --var KEY=VALUE (repeatable). Use --dry-run to preview" :: String),
                  pretty ("the plan without writing files, or --diff to compare against disk." :: String),
                  line,
                  pretty ("When re-running, Seihou uses the .seihou/manifest.json to detect" :: String),
                  pretty ("new, modified, unchanged, and conflicting files. Conflicts are" :: String),
                  pretty ("reported and block execution unless --force is used." :: String),
                  line,
                  pretty ("If an applied module's installed copy has advanced past the manifest's" :: String),
                  pretty ("recorded version and ships migrations that move project files," :: String),
                  pretty ("'seihou run' refuses to proceed (so it never writes new templates into" :: String),
                  pretty ("paths a migration would have moved). For routine source updates, run" :: String),
                  pretty ("'seihou update <target>'. Use migrate or --with-migrations for focused" :: String),
                  pretty ("recovery and explicit reconfiguration." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou run haskell-base --var project.name=my-app" :: String),
                        pretty ("seihou run haskell-base -m nix-flake --dry-run" :: String),
                        pretty ("seihou run my-module --diff" :: String),
                        pretty ("seihou run haskell-base --confirm-defaults   # review and override default values" :: String),
                        pretty ("seihou run haskell-base --with-migrations    # apply pending migrations before regenerating" :: String)
                      ]
                ]
          )
    )

updateInfo :: ParserInfo Command
updateInfo =
  info
    (updateParser <**> helper)
    ( fullDesc
        <> progDesc "Update recorded project applications safely"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reconciles recorded module and recipe applications with newer source" :: String),
                  pretty ("content. Saved inputs are reused, migrations are included automatically," :: String),
                  pretty ("user edits are three-way merged, and unchanged commands are skipped." :: String),
                  line,
                  pretty ("With no TARGET, updates every recorded application in manifest order." :: String),
                  pretty ("Use --dry-run to preview or --json for a non-interactive machine result." :: String),
                  pretty ("--force accepts generated conflict content but retains edited orphans." :: String),
                  line,
                  indent 2 $
                    vsep
                      [ pretty ("seihou update" :: String),
                        pretty ("seihou update master-plan --dry-run" :: String),
                        pretty ("seihou update master-plan --force --commit" :: String)
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
        <> progDesc "Install module(s), recipe(s), blueprint(s), or prompt(s) from git"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Clones the git repository and installs modules, recipes," :: String),
                  pretty ("blueprints, or prompts to ~/.config/seihou/installed/<name>/." :: String),
                  line,
                  pretty ("If the repository contains a seihou-registry.dhall file, it is" :: String),
                  pretty ("treated as a multi-module registry. Use --module to pick specific" :: String),
                  pretty ("entries or --all to install everything. Without either flag, you" :: String),
                  pretty ("will be prompted to choose interactively." :: String),
                  line,
                  pretty ("For single-artifact repositories (a root module.dhall, recipe.dhall," :: String),
                  pretty ("blueprint.dhall, or prompt.dhall), the artifact name defaults to the repository" :: String),
                  pretty ("name. Use --name to override." :: String),
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
                  pretty ("access and will clone each source repo shallowly." :: String),
                  line,
                  pretty ("When an applied module's installed copy has advanced past the manifest's" :: String),
                  pretty ("recorded version, status reports the pending migration count under that" :: String),
                  pretty ("module's line. Recorded applications recommend 'seihou update <target>';" :: String),
                  pretty ("manual 'seihou migrate <module>' remains available for focused recovery." :: String)
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
        <> progDesc "List available modules, recipes, blueprints, and prompts"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Scans all search paths and lists every available runnable artifact" :: String),
                  pretty ("(modules, recipes, blueprints, prompts) with its name, kind, description, and" :: String),
                  pretty ("source location (project, user, or installed). Entries that fail to" :: String),
                  pretty ("load are shown with an error indicator." :: String),
                  line,
                  pretty ("Use --repo and --tag to filter the output." :: String),
                  pretty ("Use --modules, --recipes, --blueprints, and --prompts to restrict by kind" :: String),
                  pretty ("(combine them to show several kinds; omit all to show every kind)." :: String)
                ]
          )
    )

listParser :: Parser Command
listParser =
  fmap List $
    ListOpts
      <$> optional (option (T.pack <$> str) (long "repo" <> metavar "REPO" <> help "Filter by repository name"))
      <*> optional (option (T.pack <$> str) (long "tag" <> metavar "TAG" <> help "Filter by tag"))
      <*> switch (long "modules" <> help "Show only modules")
      <*> switch (long "recipes" <> help "Show only recipes")
      <*> switch (long "blueprints" <> help "Show only blueprints")
      <*> switch (long "prompts" <> help "Show only prompts")

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
      <*> switch
        ( long "with-migrations"
            <> help "Apply any pending module migrations before the run plan; without this, 'seihou run' refuses when migrations are pending"
        )

updateParser :: Parser Command
updateParser =
  fmap Update $
    makeUpdateOpts
      <$> many (argument (T.pack <$> str) (metavar "TARGET" <> help "Recorded application target or contained module (repeatable; default: all)"))
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Variable override (repeatable)")
        )
      <*> switch (long "dry-run" <> help "Show the complete update plan without modifying managed state")
      <*> switch (long "json" <> help "Emit one JSON document and disable prompts")
      <*> switch (long "reconfigure" <> help "Ignore saved inputs and resolve them again")
      <*> switch (long "force" <> help "Use generated content for safe conflicts and retain edited orphans")
      <*> updateCommandFlags
      <*> switch (long "commit" <> help "Commit successfully updated managed paths")
      <*> optional (option (T.pack <$> str) (long "commit-message" <> metavar "MSG" <> help "Custom commit message (implies --commit)"))
  where
    makeUpdateOpts targets vars dryRun json reconfigure force (runAll, noCommands) commit commitMessage =
      UpdateOpts
        { updateTargets = targets,
          updateVars = vars,
          updateDryRun = dryRun,
          updateJson = json,
          updateReconfigure = reconfigure,
          updateForce = force,
          updateRunAllCommands = runAll,
          updateNoCommands = noCommands,
          updateCommit = commit,
          updateCommitMessage = commitMessage
        }
    updateCommandFlags =
      flag' (True, False) (long "run-all-commands" <> help "Run every generated command, including unchanged ones")
        <|> flag' (False, True) (long "no-commands" <> help "Skip every generated command")
        <|> pure (False, False)

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
      <*> many (option (T.pack <$> str) (long "module" <> metavar "MODULE" <> help "Module, recipe, blueprint, or prompt name from the registry to install (repeatable)"))
      <*> switch (long "all" <> help "Install every module, recipe, blueprint, and prompt listed in the registry")

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

newBlueprintInfo :: ParserInfo Command
newBlueprintInfo =
  info
    (newBlueprintParser <**> helper)
    ( fullDesc
        <> progDesc "Scaffold a new agent-driven blueprint"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Creates a new blueprint directory containing three artifacts:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("blueprint.dhall   the blueprint record (imports the schema)" :: String),
                        pretty ("prompt.md         the Markdown body the agent runner consumes" :: String),
                        pretty ("files/            empty reference directory for snippets, templates" :: String)
                      ],
                  line,
                  pretty ("The output directory defaults to ./<name>/ in the current directory." :: String),
                  line,
                  pretty ("Blueprint names must match [a-z][a-z0-9-]* (lowercase, hyphens allowed," :: String),
                  pretty ("must start with a letter)." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou new-blueprint payments-service" :: String)
                ]
          )
    )

newBlueprintParser :: Parser Command
newBlueprintParser =
  fmap NewBlueprint $
    NewBlueprintOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

newPromptInfo :: ParserInfo Command
newPromptInfo =
  info
    (newPromptParser <**> helper)
    ( fullDesc
        <> progDesc "Scaffold a new agent-session prompt"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Creates a new prompt directory containing three artifacts:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("prompt.dhall   the prompt record" :: String),
                        pretty ("prompt.md      the Markdown body rendered before launch" :: String),
                        pretty ("files/         empty reference directory for snippets and docs" :: String)
                      ],
                  line,
                  pretty ("The output directory defaults to ./<name>/ in the current directory." :: String),
                  line,
                  pretty ("Prompt names must match [a-z][a-z0-9-]* (lowercase, hyphens allowed," :: String),
                  pretty ("must start with a letter)." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou new-prompt review-changes" :: String)
                ]
          )
    )

newPromptParser :: Parser Command
newPromptParser =
  fmap NewPrompt $
    NewPromptOpts
      <$> argument (T.pack <$> str) (metavar "NAME")
      <*> optional (option str (long "path" <> metavar "DIR" <> help "Output directory (default: ./<name>/)"))

validateBlueprintInfo :: ParserInfo Command
validateBlueprintInfo =
  info
    (validateBlueprintParser <**> helper)
    ( fullDesc
        <> progDesc "Validate a blueprint"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Checks that a blueprint directory is well-formed: blueprint.dhall" :: String),
                  pretty ("evaluates, the blueprint name is valid, the prompt body is non-empty," :: String),
                  pretty ("variable names are unique, prompts reference declared variables," :: String),
                  pretty ("every entry in the files list resolves under files/, and base modules" :: String),
                  pretty ("are not themselves blueprints." :: String),
                  line,
                  pretty ("PATH defaults to the current directory if not specified." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou validate-blueprint ./payments-service" :: String)
                ]
          )
    )

validateBlueprintParser :: Parser Command
validateBlueprintParser =
  fmap ValidateBlueprint $
    ValidateBlueprintOpts
      <$> optional (argument str (metavar "PATH"))
      <*> switch (long "lint" <> help "Include advisory lint warnings")

validatePromptInfo :: ParserInfo Command
validatePromptInfo =
  info
    (validatePromptParser <**> helper)
    ( fullDesc
        <> progDesc "Validate a prompt"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Checks that a prompt directory is well-formed: prompt.dhall" :: String),
                  pretty ("evaluates, the prompt name is valid, the prompt body is non-empty," :: String),
                  pretty ("variable names are unique, prompts reference declared variables," :: String),
                  pretty ("command variables are well-formed, and every entry in files resolves" :: String),
                  pretty ("under files/." :: String),
                  line,
                  pretty ("PATH defaults to the current directory if not specified." :: String),
                  line,
                  pretty ("Example:" :: String),
                  indent 2 $ pretty ("seihou validate-prompt ./review-changes" :: String)
                ]
          )
    )

validatePromptParser :: Parser Command
validatePromptParser =
  fmap ValidatePrompt $
    ValidatePromptOpts
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
        <> progDesc "Browse modules, recipes, blueprints, and prompts in a git repository"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Clones the repository and shows available modules, recipes," :: String),
                  pretty ("blueprints, and prompts without installing anything. For multi-artifact repos" :: String),
                  pretty ("with a seihou-registry.dhall, displays all entries with descriptions," :: String),
                  pretty ("kind labels, and tags. Use --tag to filter by tag." :: String),
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
                  indent 2 $ pretty ("seihou outdated" :: String),
                  line,
                  pretty ("Run 'seihou update' in an applied project to fetch and reconcile" :: String),
                  pretty ("available versions. Use 'seihou upgrade' only to refresh the shared" :: String),
                  pretty ("installed cache, or 'seihou migrate <module>' for focused recovery." :: String)
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
        <> progDesc "Refresh shared installed-cache sources only"
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
      <*> switch
        ( long "with-migrations"
            <> help "After each upgrade, also run 'seihou migrate' against the current project for that module"
        )

upgradeFooter :: Doc
upgradeFooter =
  vsep
    [ pretty ("Refreshes installed-cache modules to the latest version available from their" :: String),
      pretty ("source repository. Only modules installed via 'seihou install' are checked." :: String),
      pretty ("It does not reconcile the current project; use 'seihou update' for that." :: String),
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
            pretty ("seihou upgrade --skip-unversioned     # skip unversioned modules" :: String),
            pretty ("seihou upgrade --with-migrations      # also run 'seihou migrate' for each upgrade" :: String)
          ],
      line,
      pretty ("Migrations:" :: String),
      indent 2 $
        vsep
          [ pretty ("Newer module versions may declare migrations that move project files" :: String),
            pretty ("when applied. By default 'seihou upgrade' does not run them — it only" :: String),
            pretty ("prints an advisory pointing project users at 'seihou update'. Pass" :: String),
            pretty ("--with-migrations to run them as part of the upgrade." :: String)
          ]
    ]

migrateInfo :: ParserInfo Command
migrateInfo =
  info
    (migrateParser <**> helper)
    ( fullDesc
        <> progDesc "Apply module-declared migrations to the current project"
        <> footerDoc (Just migrateFooter)
    )

migrateParser :: Parser Command
migrateParser =
  fmap Migrate $
    MigrateOpts
      <$> argument (ModuleName . T.pack <$> str) (metavar "MODULE" <> help "The applied module to migrate")
      <*> optional
        ( option
            (T.pack <$> str)
            ( long "to"
                <> metavar "VERSION"
                <> help "Target version (default: installed module's current version)"
            )
        )
      <*> switch (long "dry-run" <> help "Show the migration plan without modifying any files")
      <*> switch (long "force" <> help "Proceed even when files have been edited since generation")
      <*> switch (long "json" <> help "Emit the plan as JSON instead of human-readable text")
      <*> switch (long "verbose" <> short 'v' <> help "Print extra detail about each operation")
      <*> switch (long "no-fetch" <> help "Skip the remote fetch; use only the locally installed copy")
      <*> switch (long "commit" <> help "Commit migrated files to git after execution (uses AI-generated message)")
      <*> optional (option (T.pack <$> str) (long "commit-message" <> metavar "MSG" <> help "Custom commit message (implies --commit)"))

migrateFooter :: Doc
migrateFooter =
  vsep
    [ pretty ("Applies the migrations declared on a module's module.dhall file to the" :: String),
      pretty ("current project's working tree and manifest at .seihou/manifest.json." :: String),
      pretty ("The chain that runs is determined by the manifest's recorded version" :: String),
      pretty ("of the applied module (the 'from') and either the installed copy's" :: String),
      pretty ("current version or a --to override (the 'to')." :: String),
      line,
      pretty ("Available migration operations:" :: String),
      indent 2 $
        vsep
          [ pretty ("MoveFile    rename a single tracked file" :: String),
            pretty ("MoveDir     rename a directory; rewrites every contained manifest entry" :: String),
            pretty ("DeleteFile  remove a tracked file" :: String),
            pretty ("DeleteDir   recursively remove a directory" :: String),
            pretty ("RunCommand  run a shell command (escape hatch; manifest is not auto-updated)" :: String)
          ],
      line,
      pretty ("Conflict semantics mirror 'seihou remove': files whose disk hash differs" :: String),
      pretty ("from the manifest are flagged. Without --force the engine refuses to" :: String),
      pretty ("overwrite them and exits non-zero. With --force, the migration proceeds." :: String),
      line,
      pretty ("Examples:" :: String),
      indent 2 $
        vsep
          [ pretty ("seihou migrate haskell-base                # plan + apply" :: String),
            pretty ("seihou migrate haskell-base --dry-run      # preview only" :: String),
            pretty ("seihou migrate haskell-base --to 1.5.0     # stop at intermediate version" :: String),
            pretty ("seihou migrate haskell-base --force        # overwrite conflicted files" :: String),
            pretty ("seihou migrate haskell-base --json         # machine-readable plan" :: String),
            pretty ("seihou migrate haskell-base --commit       # auto-commit after migrate" :: String)
          ],
      line,
      pretty ("See also: seihou help migrations" :: String)
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
        <> progDesc "Manage Claude Code and Codex skills and subagents"
    )

registryInfo :: ParserInfo Command
registryInfo =
  info
    (Registry <$> registryCommandParser <**> helper)
    ( fullDesc
        <> progDesc "Manage seihou-registry.dhall files"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Authoring-time operations on a multi-artifact repository's" :: String),
                  pretty ("seihou-registry.dhall. Run against a writable checkout." :: String),
                  line,
                  pretty ("Current subcommands:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("sync-versions   Copy each entry's declared version into the registry" :: String),
                        pretty ("validate        Check that registry entries match their on-disk artifacts" :: String)
                      ],
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou registry sync-versions" :: String),
                        pretty ("seihou registry sync-versions --dry-run" :: String),
                        pretty ("seihou registry sync-versions --check" :: String),
                        pretty ("seihou registry validate" :: String)
                      ]
                ]
          )
    )

registryCommandParser :: Parser RegistryCommand
registryCommandParser =
  hsubparser
    ( command "sync-versions" syncVersionsInfo
        <> command "validate" validateRegistryInfo
    )

syncVersionsInfo :: ParserInfo RegistryCommand
syncVersionsInfo =
  info
    (syncVersionsParser <**> helper)
    ( fullDesc
        <> progDesc "Populate registry entry versions from each module/recipe/blueprint/prompt"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reads every entry's module.dhall, recipe.dhall, blueprint.dhall, or prompt.dhall," :: String),
                  pretty ("copies the declared version into the registry, and rewrites" :: String),
                  pretty ("seihou-registry.dhall. Hand-written comments and formatting are lost." :: String),
                  line,
                  pretty ("With --dry-run the diff is printed but the file is left untouched." :: String),
                  pretty ("With --check the command exits 1 if any entry is out of sync — suitable" :: String),
                  pretty ("for CI. --check takes precedence over --dry-run if both are given." :: String)
                ]
          )
    )

syncVersionsParser :: Parser RegistryCommand
syncVersionsParser =
  fmap RegistrySyncVersions $
    SyncVersionsOpts
      <$> optional
        ( option
            str
            ( long "dir"
                <> metavar "PATH"
                <> help "Registry repo root (default: current directory)"
            )
        )
      <*> switch (long "dry-run" <> help "Show diff without writing the registry file")
      <*> switch (long "check" <> help "Exit 1 if any entry is out of sync; do not write")

validateRegistryInfo :: ParserInfo RegistryCommand
validateRegistryInfo =
  info
    (validateRegistryParser <**> helper)
    ( fullDesc
        <> progDesc "Check that registry entries match their on-disk artifacts"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Validates a multi-artifact repository's seihou-registry.dhall:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("- every entry path resolves to a module.dhall, recipe.dhall, blueprint.dhall, or prompt.dhall" :: String),
                        pretty ("- entry names match [a-z][a-z0-9-]*" :: String),
                        pretty ("- no name collisions between modules, recipes, blueprints, and prompts" :: String),
                        pretty ("- entry paths are relative and contain no '..'" :: String),
                        pretty ("- each entry's `version` matches the underlying module/recipe/blueprint/prompt" :: String)
                      ],
                  line,
                  pretty ("Exits 1 on any failure. Run from a writable checkout of the registry repo." :: String)
                ]
          )
    )

validateRegistryParser :: Parser RegistryCommand
validateRegistryParser =
  fmap RegistryValidate $
    ValidateRegistryOpts
      <$> optional
        ( option
            str
            ( long "dir"
                <> metavar "PATH"
                <> help "Registry repo root (default: current directory)"
            )
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
                  pretty ("configurable CLI or API providers. Use --provider to select claude-cli, codex-cli," :: String),
                  pretty ("anthropic, or openai, and --model for a provider-specific model." :: String),
                  pretty ("Run 'seihou agent models' to list known model choices." :: String),
                  line,
                  pretty ("Use --debug with any subcommand to print the resolved system" :: String),
                  pretty ("prompt without contacting the configured provider." :: String),
                  line,
                  pretty ("Available subcommands:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("assist      AI-assisted template authoring prompt" :: String),
                        pretty ("bootstrap   Bootstrap a new module or multi-module repo" :: String),
                        pretty ("setup       Guided project setup: configure, run, and commit" :: String),
                        pretty ("run         Run an agent-driven blueprint" :: String),
                        pretty ("models      List known agent models" :: String)
                      ]
                ]
          )
    )

agentParser :: Parser Command
agentParser =
  fmap Agent $
    AgentOpts
      <$> switch (long "debug" <> help "Print the resolved system prompt and exit")
      <*> optional
        ( option
            (T.pack <$> str)
            ( long "provider"
                <> metavar "PROVIDER"
                <> help "Agent provider: claude-cli, codex-cli, anthropic, or openai"
            )
        )
      <*> optional
        ( option
            (T.pack <$> str)
            ( long "model"
                <> metavar "MODEL"
                <> help "Agent model name or provider-specific alias; 'seihou agent models' lists known choices"
            )
        )
      <*> agentCommandParser

agentCommandParser :: Parser AgentCommand
agentCommandParser =
  subparser
    ( command "assist" agentAssistInfo
        <> command "bootstrap" agentBootstrapInfo
        <> command "setup" agentSetupInfo
        <> command "run" agentRunInfo
        <> command "models" agentModelsInfo
        <> command "config" agentConfigInfo
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
                [ pretty ("Renders a Seihou-aware prompt for creating and modifying" :: String),
                  pretty ("modules, then starts the configured provider." :: String),
                  pretty ("The prompt gathers context" :: String),
                  pretty ("about your current directory (existing modules, manifest state," :: String),
                  pretty ("available modules) and includes the Seihou" :: String),
                  pretty ("module schema." :: String),
                  line,
                  pretty ("CLI providers open interactive Claude Code or Codex sessions;" :: String),
                  pretty ("API providers run one-shot text completions." :: String),
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
      <*> providerOption
      <*> modelOption

agentBootstrapInfo :: ParserInfo AgentCommand
agentBootstrapInfo =
  info
    (agentBootstrapParser <**> helper)
    ( fullDesc
        <> progDesc "Bootstrap a new module or multi-module repository"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Renders a Seihou-aware prompt for creating a complete module" :: String),
                  pretty ("from scratch: defining variables," :: String),
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
      <*> providerOption
      <*> modelOption

agentSetupInfo :: ParserInfo AgentCommand
agentSetupInfo =
  info
    (agentSetupParser <**> helper)
    ( fullDesc
        <> progDesc "Guided project setup: configure, run, and commit"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Renders a Seihou-aware prompt for using a module: selecting" :: String),
                  pretty ("a module, configuring variables and" :: String),
                  pretty ("context, running the module to generate files, verifying the output," :: String),
                  pretty ("and committing the changes to git." :: String),
                  line,
                  pretty ("The rendered prompt is sent to the configured provider;" :: String),
                  pretty ("--debug prints it without contacting that provider." :: String),
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
      <*> providerOption
      <*> modelOption

agentRunInfo :: ParserInfo AgentCommand
agentRunInfo =
  info
    (agentRunParser <**> helper)
    ( fullDesc
        <> progDesc "Run an agent-driven blueprint"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Resolves the named blueprint, prompts for any required variables," :: String),
                  pretty ("optionally applies the blueprint's baseModules as a starting scaffold," :: String),
                  pretty ("renders the prompt template, and starts the configured" :: String),
                  pretty ("provider." :: String),
                  line,
                  pretty ("Variable resolution follows the same precedence as 'seihou run':" :: String),
                  pretty ("CLI overrides > env > local config > namespace > context > global > defaults" :: String),
                  pretty ("> interactive prompts." :: String),
                  line,
                  pretty ("Pass --no-baseline to skip baseline application; --debug (on the parent" :: String),
                  pretty ("'seihou agent --debug') prints the resolved system prompt without" :: String),
                  pretty ("contacting the configured provider." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent run my-blueprint" :: String),
                        pretty ("seihou agent run my-blueprint \"set this up for billing\"" :: String),
                        pretty ("seihou agent run my-blueprint --var service.name=billing" :: String),
                        pretty ("seihou agent run my-blueprint --no-baseline" :: String),
                        pretty ("seihou agent --debug run my-blueprint" :: String)
                      ]
                ]
          )
    )

agentRunParser :: Parser AgentCommand
agentRunParser =
  fmap AgentRun $
    BlueprintRunOpts
      <$> argument moduleNameReader (metavar "BLUEPRINT" <> help "Name of the blueprint to run")
      <*> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Optional initial user prompt"))
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Variable override (repeatable)")
        )
      <*> switch (long "no-baseline" <> help "Skip applying the blueprint's baseModules before rendering the prompt")
      <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))
      <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Override context for config lookup"))
      <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")
      <*> switch (long "force" <> help "Auto-resolve baseline conflicts (accept new files)")
      <*> providerOption
      <*> modelOption

agentModelsInfo :: ParserInfo AgentCommand
agentModelsInfo =
  info
    (agentModelsParser <**> helper)
    ( fullDesc
        <> progDesc "List known agent models"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Lists the Anthropic and OpenAI models in Seihou's compiled Baikai catalog." :: String),
                  pretty ("Use --provider to filter by an API or compatible local CLI provider." :: String),
                  line,
                  pretty ("The catalog is a discovery aid, not validation. Provider-native aliases" :: String),
                  pretty ("and custom model identifiers remain accepted by --model." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent models" :: String),
                        pretty ("seihou agent models --provider openai" :: String),
                        pretty ("seihou agent --provider claude-cli models" :: String)
                      ]
                ]
          )
    )

agentModelsParser :: Parser AgentCommand
agentModelsParser =
  AgentModels . AgentModelsOpts <$> providerOption

agentConfigInfo :: ParserInfo AgentCommand
agentConfigInfo =
  info
    (pure AgentConfigShow <**> helper)
    ( fullDesc
        <> progDesc "Show the resolved provider and model for each agent command"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Prints the provider and model that each agent command resolves to," :: String),
                  pretty ("labelling the source of every value: a config scope and key, an" :: String),
                  pretty ("environment variable, or the built-in default. Read-only; set values" :: String),
                  pretty ("with `seihou config set agent.<command>.model ...`." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou agent config" :: String),
                        pretty ("seihou config set agent.assist.model gpt-5-mini --global" :: String),
                        pretty ("seihou config set agent.run.model claude-opus-4-8" :: String)
                      ]
                ]
          )
    )

promptInfo :: ParserInfo Command
promptInfo =
  info
    (promptParser <**> helper)
    ( fullDesc
        <> progDesc "Run first-class agent-session prompts"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Prompt subcommands render reusable prompt.dhall artifacts and" :: String),
                  pretty ("start the configured provider. Use 'prompt run --debug' to print" :: String),
                  pretty ("the fully rendered prompt without contacting a provider." :: String),
                  line,
                  pretty ("Available subcommands:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("run   Resolve, render, and launch a prompt" :: String)
                      ]
                ]
          )
    )

promptParser :: Parser Command
promptParser =
  fmap Prompt $
    subparser
      (command "run" promptRunInfo)

promptRunInfo :: ParserInfo PromptCommand
promptRunInfo =
  info
    (promptRunParser <**> helper)
    ( fullDesc
        <> progDesc "Run an agent-session prompt"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Resolves the named prompt, prompts for any required variables," :: String),
                  pretty ("runs command-derived variables, renders the prompt body, and" :: String),
                  pretty ("starts the configured provider." :: String),
                  line,
                  pretty ("Variable resolution follows the same precedence as 'seihou run':" :: String),
                  pretty ("CLI overrides > env > local config > namespace > context > global > defaults" :: String),
                  pretty ("> interactive prompts. Command-derived variables fill any remaining" :: String),
                  pretty ("prompt variables after that chain resolves." :: String),
                  line,
                  pretty ("CLI providers open interactive Claude Code or Codex sessions;" :: String),
                  pretty ("API providers run one-shot text completions. Use --debug to print" :: String),
                  pretty ("the rendered prompt and skip provider launch." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou prompt run review-changes" :: String),
                        pretty ("seihou prompt run review-changes \"focus on API changes\"" :: String),
                        pretty ("seihou prompt run review-changes --var project.name=demo" :: String),
                        pretty ("seihou prompt run review-changes --debug" :: String)
                      ]
                ]
          )
    )

promptRunParser :: Parser PromptCommand
promptRunParser =
  fmap PromptRun $
    PromptRunOpts
      <$> argument moduleNameReader (metavar "PROMPT" <> help "Name of the prompt to run")
      <*> optional (argument (T.pack <$> str) (metavar "USER-PROMPT" <> help "Optional initial user prompt"))
      <*> many
        ( option
            varPair
            (long "var" <> metavar "KEY=VALUE" <> help "Variable override (repeatable)")
        )
      <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))
      <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Override context for config lookup"))
      <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")
      <*> switch (long "debug" <> help "Print the rendered prompt and exit")
      <*> providerOption
      <*> modelOption

helpCmdInfo :: ParserInfo Command
helpCmdInfo =
  info
    (HelpCmd <$> helpCommandParser <**> helper)
    ( fullDesc
        <> progDesc "Show help for commands and topics"
    )

extensionInfo :: ParserInfo Command
extensionInfo =
  info
    (Extension <$> extensionParser <**> helper)
    ( fullDesc
        <> progDesc "Run external seihou extensions"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Extensions are external executables named seihou-<name>-extension." :: String),
                  pretty ("Everything after '--' is forwarded unchanged to the extension process." :: String),
                  line,
                  pretty ("Examples:" :: String),
                  indent 2 $
                    vsep
                      [ pretty ("seihou extension run okf -- --help" :: String),
                        pretty ("seihou extension run okf -- docs --dir . --out okf-docs" :: String)
                      ]
                ]
          )
    )

extensionParser :: Parser ExtensionCommand
extensionParser =
  hsubparser
    (command "run" extensionRunInfo)

extensionRunInfo :: ParserInfo ExtensionCommand
extensionRunInfo =
  info
    (extensionRunParser <**> helper)
    ( fullDesc
        <> progDesc "Run an extension executable from PATH"
    )

extensionRunParser :: Parser ExtensionCommand
extensionRunParser =
  fmap ExtensionRun $
    ExtensionRunOpts
      <$> argument (T.pack <$> str) (metavar "NAME" <> help "Extension name")
      <*> many (strArgument (metavar "ARGS..."))

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

providerOption :: Parser (Maybe Text)
providerOption =
  optional $
    option
      (T.pack <$> str)
      ( long "provider"
          <> metavar "PROVIDER"
          <> help "Agent provider: claude-cli, codex-cli, anthropic, or openai"
      )

modelOption :: Parser (Maybe Text)
modelOption =
  optional $
    option
      (T.pack <$> str)
      ( long "model"
          <> metavar "MODEL"
          <> help "Agent model name or provider-specific alias; 'seihou agent models' lists known choices"
      )
