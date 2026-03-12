# Add help topics subcommand

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can run `seihou help` to see a list of conceptual help topics and `seihou help <topic>` to read detailed guidance on a specific concept. This is different from `--help` flags on individual commands: help topics explain cross-cutting concepts like modules, variables, contexts, and the generation pipeline that span multiple commands. The topics are plain-text files embedded into the binary at compile time via `file-embed`, so they ship with every build and require no runtime file access.

A user who types `seihou help` will see something like:

    HELP TOPICS

      modules      How Seihou modules work
      variables    Variable declaration, resolution, and overrides
      contexts     Using contexts for environment-specific config

    Use 'seihou help <topic>' for details.

And `seihou help modules` will print the full topic content directly to the terminal.


## Progress

- [x] Create the `seihou-cli/help/` directory with initial topic files (2026-03-12)
- [x] Create `seihou-cli/src/Seihou/CLI/Help.hs` with topic registry, parser, and handler (2026-03-12)
- [x] Add `HelpCmd` constructor to the `Command` ADT in `Commands.hs` (2026-03-12)
- [x] Add `HelpCommand` type and `helpCommandParser` to `Commands.hs` exports (2026-03-12)
- [x] Wire `help` subcommand into `commandParser` in `Commands.hs` (2026-03-12)
- [x] Add `HelpCmd` dispatch case in `Main.hs` (2026-03-12)
- [x] Register `Seihou.CLI.Help` in `seihou-cli.cabal` under `other-modules` (2026-03-12)
- [x] Build and verify `seihou help` lists topics (2026-03-12)
- [x] Build and verify `seihou help modules` prints topic content (2026-03-12)
- [x] Build and verify `seihou help unknown-topic` shows an error with available topics (2026-03-12)


## Surprises & Discoveries

- The `NoFieldSelectors` default extension means record field names like `topicName` cannot be used as standalone functions. The initial code from the cookbook pattern used `topicName t` style access. Fixed by using `t.topicName` (OverloadedRecordDot) and `(.topicName)` for `map`. Also needed an explicit `import Data.Foldable (forM_)` since `Seihou.Prelude` does not re-export it.


## Decision Log

- Decision: Use `embedStringFile` (returns `String`) instead of `embedFile` (returns `ByteString`) as the cookbook recommends, because the topic content is plain text and `embedStringFile` works directly with `IsString` instances including `Text` via `OverloadedStrings`.
  Rationale: The existing agent prompt embedding uses `embedFile` + `TE.decodeUtf8`, but for plain-text help content, `embedStringFile` is simpler and matches the cookbook pattern. Either approach works; this one avoids the `Data.Text.Encoding` import.
  Date: 2026-03-12

- Decision: Place topic files in `seihou-cli/help/` (at the package root, next to `src/` and `data/`), not inside `src/`.
  Rationale: `embedStringFile` resolves paths relative to the package root (where `seihou-cli.cabal` lives). Keeping content files outside `src/` follows the same pattern as `data/assist-prompt.md` and `data/bootstrap-prompt.md`. A dedicated `help/` directory is clearer than mixing them into `data/`.
  Date: 2026-03-12

- Decision: Start with three initial topics: `modules`, `variables`, `contexts`. More can be added later by following the "Adding a new topic" recipe.
  Rationale: These three concepts are the most cross-cutting and least obvious from `--help` flags alone. They cover the core mental model a new user needs.
  Date: 2026-03-12

- Decision: Name the `Command` constructor `HelpCmd` (not `Help`) to avoid clashing with optparse-applicative's `helper` and `Help` type.
  Rationale: The name `Help` is already prominent in the optparse-applicative namespace and could cause confusion. `HelpCmd` is unambiguous.
  Date: 2026-03-12


## Outcomes & Retrospective

All acceptance criteria met. The `seihou help` command lists topics, `seihou help <topic>` prints embedded content, unknown topics show an error with available names, and `seihou help --help` shows optparse-applicative auto-generated help. The build is clean with no warnings from the new module.

The cookbook pattern adapted cleanly to seihou's codebase. The only adjustments needed were for `NoFieldSelectors` (use `.field` syntax) and an explicit `forM_` import. The `embedStringFile` approach worked as expected with `OverloadedStrings` to produce `Text` directly.


## Context and Orientation

Seihou is a composable project scaffolding CLI written in Haskell. The CLI is built with optparse-applicative and lives in the `seihou-cli` package. The key files involved in this change are:

`seihou-cli/src/Seihou/CLI/Commands.hs` defines the `Command` ADT (currently 13 constructors: `Init`, `Run`, `Vars`, `Install`, `Status`, `Diff`, `List`, `NewModule`, `ValidateModule`, `Config`, `Context`, `Browse`, `Agent`) and all parsers. The top-level parser `commandParser` uses `subparser` to dispatch. Each command has a `ParserInfo` block and a parser function.

`seihou-cli/src/Main.hs` pattern-matches on the `Command` ADT and calls the appropriate handler. It imports each handler module and uses `execParser opts` to run the parser.

`seihou-cli/seihou-cli.cabal` lists all modules under the `executable seihou` section in `other-modules`. The `file-embed` dependency is already present (`>=0.0.15 && <1`). The `TemplateHaskell` extension is not listed as a default extension but is used via `{-# LANGUAGE TemplateHaskell #-}` pragmas in individual files (see `Assist.hs`, `Bootstrap.hs`).

The project uses `embedFile` from `Data.FileEmbed` in two existing files (`Assist.hs` and `Bootstrap.hs`) to embed prompt templates from `seihou-cli/data/`. Those files use `embedFile` (which returns `ByteString`) and then `TE.decodeUtf8`. The cookbook pattern uses `embedStringFile` instead, which returns a `String`-compatible value and works with `OverloadedStrings` to produce `Text` directly.

The project uses GHC2024 as the default language and has `OverloadedStrings` as a default extension. The `Seihou.Prelude` module is used across the codebase and re-exports common types including `Text`.

Topic files are plain text with ALL-CAPS section headers (not rendered Markdown). They are printed directly to the terminal. The format uses 2-space indentation for content under headers.


## Plan of Work

The work has one milestone because the scope is small and self-contained.

### Milestone 1: Help command with embedded topics

This milestone delivers the complete `seihou help [TOPIC]` subcommand. At the end, three topic files exist in `seihou-cli/help/`, a new `Help.hs` module contains the topic registry and handler, the `Command` ADT has a `HelpCmd` constructor, and `Main.hs` dispatches to the handler. The user can run `seihou help` to list topics and `seihou help <topic>` to read one.

First, create the topic content files. Each file lives in `seihou-cli/help/` and uses the plain-text format described in the cookbook: ALL-CAPS section headers, 2-space indentation for content, no Markdown rendering. Start with three files: `modules.md`, `variables.md`, and `contexts.md`.

Second, create `seihou-cli/src/Seihou/CLI/Help.hs`. This module defines a `HelpTopic` record type with `topicName`, `topicDescription`, and `topicContent` fields (all `Text`). It defines a `helpTopics` list containing all topics with their embedded content. It defines a `HelpCommand` type (`ListTopics | ShowTopic Text`), a parser `helpCommandParser`, and a handler `handleHelpCommand`. The handler prints the topic index for `ListTopics` and the topic content for `ShowTopic`, with case-insensitive lookup. If a topic is not found, it prints an error with the list of available topic names.

Third, modify `seihou-cli/src/Seihou/CLI/Commands.hs` to add a `HelpCmd HelpCommand` constructor to the `Command` ADT. Import the `HelpCommand` type and `helpCommandParser` from `Help.hs`. Add a `help` entry in `commandParser`'s `subparser` block, with a `ParserInfo` that has a `progDesc` of "Show help for commands and topics". Add `HelpCommand(..)` to the module exports.

Fourth, modify `seihou-cli/src/Main.hs` to import `handleHelpCommand` from `Seihou.CLI.Help` and add a `HelpCmd helpCmd -> handleHelpCommand helpCmd` case to the dispatch.

Fifth, add `Seihou.CLI.Help` to the `other-modules` list in `seihou-cli.cabal` under the `executable seihou` section.

Finally, build and test all three usage modes: listing topics, showing a valid topic, and showing an error for an unknown topic.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`.

Create the help directory and topic files:

    mkdir -p seihou-cli/help

Create `seihou-cli/help/modules.md`, `seihou-cli/help/variables.md`, and `seihou-cli/help/contexts.md` with plain-text content (see topic content below in the Interfaces section).

Create `seihou-cli/src/Seihou/CLI/Help.hs` with the topic registry, parser, and handler.

Edit `seihou-cli/src/Seihou/CLI/Commands.hs`:
- Add `HelpCommand (..)` to the module export list.
- Import `Seihou.CLI.Help (HelpCommand, helpCommandParser)`.
- Add `| HelpCmd HelpCommand` to the `Command` data type.
- Add `command "help" helpInfo` to the `commandParser` subparser block.
- Add a `helpInfo :: ParserInfo Command` definition.

Edit `seihou-cli/src/Main.hs`:
- Add `import Seihou.CLI.Help (handleHelpCommand)`.
- Add `HelpCmd helpCmd -> handleHelpCommand helpCmd` to the case expression.

Edit `seihou-cli/seihou-cli.cabal`:
- Add `Seihou.CLI.Help` to `other-modules` under `executable seihou` (alphabetically, between `Seihou.CLI.Diff` and `Seihou.CLI.Init`).

Build:

    nix develop --command cabal build seihou

Expected: clean build with no errors.

Test listing topics:

    nix develop --command cabal run seihou -- help

Expected output similar to:

    HELP TOPICS

      modules      How Seihou modules work
      variables    Variable declaration, resolution, and overrides
      contexts     Using contexts for environment-specific config

    Use 'seihou help <topic>' for details.

Test showing a topic:

    nix develop --command cabal run seihou -- help modules

Expected: prints the full content of `seihou-cli/help/modules.md`.

Test unknown topic:

    nix develop --command cabal run seihou -- help nonexistent

Expected output:

    Unknown topic: nonexistent
    Available: modules, variables, contexts

Test `--help` on the help command itself:

    nix develop --command cabal run seihou -- help --help

Expected: shows the optparse-applicative generated help for the `help` subcommand, including the list of available topic names in the TOPIC metavar help text.


## Validation and Acceptance

The change is accepted when all four test commands above produce the expected output. Specifically:

1. `seihou help` with no arguments prints a formatted topic index and exits successfully.
2. `seihou help modules` prints the embedded topic content verbatim and exits successfully.
3. `seihou help NONEXISTENT` prints an error message naming the unknown topic and listing available topics, then exits (non-zero exit code is acceptable but not required; the cookbook uses a simple print-and-exit approach).
4. `seihou help --help` shows optparse-applicative's auto-generated help for the command.
5. The project builds cleanly with `cabal build seihou` — no warnings from the new module.


## Idempotence and Recovery

All steps are additive. Creating the `help/` directory and files is idempotent (mkdir -p, file writes). If the build fails after partial edits, the changes are confined to five files (`Help.hs`, `Commands.hs`, `Main.hs`, `seihou-cli.cabal`, and the topic files) and can be reverted with `git checkout` on those files.

The `embedStringFile` Template Haskell splice runs at compile time. If a topic file path is wrong, GHC will report a compile-time error with the missing path, which is straightforward to fix.


## Interfaces and Dependencies

**Libraries used:**

- `file-embed` (already in `seihou-cli.cabal`): provides `embedStringFile` for compile-time file embedding.
- `optparse-applicative` (already in `seihou-cli.cabal`): parser combinators for the `help [TOPIC]` argument.

**New module — `seihou-cli/src/Seihou/CLI/Help.hs`:**

    {-# LANGUAGE TemplateHaskell #-}

    module Seihou.CLI.Help
      ( HelpCommand (..),
        helpCommandParser,
        handleHelpCommand,
      )
    where

    import Data.FileEmbed (embedStringFile)
    import Data.List (find)
    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import Options.Applicative
    import Seihou.Prelude

    data HelpTopic = HelpTopic
      { topicName :: !Text,
        topicDescription :: !Text,
        topicContent :: !Text
      }

    data HelpCommand
      = ListTopics
      | ShowTopic !Text
      deriving stock (Eq, Show)

    helpTopics :: [HelpTopic]
    helpTopics =
      [ HelpTopic "modules" "How Seihou modules work" modulesContent,
        HelpTopic "variables" "Variable declaration, resolution, and overrides" variablesContent,
        HelpTopic "contexts" "Using contexts for environment-specific config" contextsContent
      ]

    modulesContent :: Text
    modulesContent = $(embedStringFile "help/modules.md")

    variablesContent :: Text
    variablesContent = $(embedStringFile "help/variables.md")

    contextsContent :: Text
    contextsContent = $(embedStringFile "help/contexts.md")

    helpCommandParser :: Parser HelpCommand
    helpCommandParser =
      showTopicParser <|> pure ListTopics

    showTopicParser :: Parser HelpCommand
    showTopicParser =
      ShowTopic
        <$> strArgument
          ( metavar "TOPIC"
              <> help ("Help topic: " <> T.unpack topicList)
          )
      where
        topicList = T.intercalate ", " (map topicName helpTopics)

    handleHelpCommand :: HelpCommand -> IO ()
    handleHelpCommand = \case
      ListTopics -> listTopics
      ShowTopic name -> showTopic name

    listTopics :: IO ()
    listTopics = do
      TIO.putStrLn "HELP TOPICS\n"
      forM_ helpTopics $ \t ->
        TIO.putStrLn $ "  " <> padRight 13 (topicName t) <> topicDescription t
      TIO.putStrLn "\nUse 'seihou help <topic>' for details."

    padRight :: Int -> Text -> Text
    padRight n t = t <> T.replicate (max 0 (n - T.length t)) " "

    showTopic :: Text -> IO ()
    showTopic name =
      case find (\t -> topicName t == T.toLower name) helpTopics of
        Just t -> TIO.putStrLn (topicContent t)
        Nothing -> do
          TIO.putStrLn $ "Unknown topic: " <> name
          TIO.putStrLn $ "Available: " <> T.intercalate ", " (map topicName helpTopics)

**Modified type in `Commands.hs`:**

    data Command
      = Init
      | Run RunOpts
      | ...
      | HelpCmd HelpCommand      -- new constructor
      deriving stock (Eq, Show, Generic)

**New parser info in `Commands.hs`:**

    helpInfo :: ParserInfo Command
    helpInfo =
      info
        (HelpCmd <$> helpCommandParser <**> helper)
        ( fullDesc
            <> progDesc "Show help for commands and topics"
        )

**Topic file format (example — `seihou-cli/help/modules.md`):**

Topic files use plain text with ALL-CAPS section headers and 2-space indented content. They are printed directly to the terminal with no rendering. Each file should cover what the concept is, how it works in seihou, and common usage patterns. Suggested content for the three initial topics:

`seihou-cli/help/modules.md` should cover: what a module is (a directory with `module.dhall`), the module search path (project `.seihou/modules/`, user `~/.config/seihou/modules/`, installed `~/.config/seihou/installed/`), module structure (module.dhall, files/, templates), generation strategies (Copy, Template, DhallText, Structured), dependencies, and how to create/install modules.

`seihou-cli/help/variables.md` should cover: what variables are, declaration in module.dhall (name, type, default, description), resolution order (CLI `--var` overrides, config values, environment variables, defaults), exports for cross-module scoping, the `--explain` flag on `seihou vars`, and variable namespacing.

`seihou-cli/help/contexts.md` should cover: what contexts are (named config scopes like "work" or "personal"), where context configs live (`~/.config/seihou/contexts/<name>/config.dhall`), how to set/clear contexts, the resolution chain (project context > global default > none), and typical use cases (different git emails for work vs personal).

**Adding a new topic later (recipe):**

1. Create `seihou-cli/help/<topic-name>.md` with the content.
2. In `Help.hs`, add an embedding binding: `myTopicContent :: Text` / `myTopicContent = $(embedStringFile "help/<topic-name>.md")`.
3. Append to the `helpTopics` list: `HelpTopic "<topic-name>" "Short description" myTopicContent`.
4. Rebuild. No cabal changes needed.
