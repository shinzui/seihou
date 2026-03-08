# Add variable interpolation to command strings

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Module authors can already use `{{var}}` placeholders in template files, destination
paths, and Dhall source files. But the `run` and `workDir` fields of commands are
passed through verbatim — a command like `echo "Generated {{project.name}}"` or
`cd {{project.name}} && cabal build` executes literally with the `{{...}}` text
still present.

After this change, `{{var}}` placeholders in command `run` strings and `workDir`
fields are substituted with resolved variable values at plan-compilation time, using
the same `renderTemplate` engine that already powers file templates. Module authors
can write:

```dhall
commands =
  [ { run = "cd {{project.name}} && cabal init"
    , workDir = None Text
    , when = None Text
    }
  ]
```

and have `{{project.name}}` replaced with the resolved value before the shell
executes the command.

**Security note**: Because commands are already arbitrary shell strings authored by
the module creator (not end-user input), variable interpolation here carries no new
injection risk beyond what already exists. The module author controls both the
command template and the variable declarations (including validation patterns). This
is analogous to how destination paths already support `{{var}}` interpolation.


## Progress

- [x] Add `renderCommand` function to `Seihou.Engine.Template` module (2026-03-07)
- [x] Update `compileCommands` in `Seihou.Engine.Plan` to interpolate `run` and `workDir` (2026-03-07)
- [x] Propagate interpolation errors as compilation errors (2026-03-07)
- [x] Update preview to show interpolated command text (2026-03-07 — no changes needed; preview already displays RunCommandOp text which is now interpolated)
- [x] Add unit tests for command interpolation in `TemplateSpec` (2026-03-07)
- [x] Add plan-level tests for command interpolation in `PlanSpec` (2026-03-07)
- [x] Update the `command-test` fixture to exercise interpolation (2026-03-07)
- [x] Verify existing tests still pass (2026-03-07 — all 556 tests pass)


## Surprises & Discoveries

- The "update preview" step required no code changes. The preview and dry-run paths
  (`opToPreview`, `dryRunPlan`) already display the `RunCommandOp` text verbatim.
  Since interpolation now happens at compile time, the preview automatically shows
  the interpolated command. No extra work needed.


## Decision Log

- Decision: Reuse `renderTemplate` for command interpolation rather than writing a new parser.
  Rationale: The `{{var}}` syntax and substitution logic are identical. The existing engine
  already handles escaping (`\{{`), whitespace trimming, error reporting with context, and
  all `VarValue` type coercions. No reason to duplicate.
  Date: 2026-03-07

- Decision: Interpolate at plan-compilation time (in `compileCommands`), not at execution time.
  Rationale: This matches how destination paths and template content are handled — all
  substitution happens during `compilePlan`, and the resulting `RunCommandOp` contains the
  final text. This keeps the execution layer simple and makes dry-run previews show the
  actual commands that will run.
  Date: 2026-03-07

- Decision: Fail the entire plan compilation if a command contains an unresolvable placeholder.
  Rationale: Silently passing through `{{missing}}` to the shell would cause confusing
  errors. This matches the behavior for template files and destination paths.
  Date: 2026-03-07

- Decision: Interpolate `workDir` as well as `run`.
  Rationale: A `workDir` like `{{project.name}}` is a natural use case (run a command
  inside the generated project directory). Destination paths already support this.
  Date: 2026-03-07


## Outcomes & Retrospective

All acceptance criteria met. The implementation was straightforward — the plan's
predicted changes matched the actual edits exactly. Key outcomes:

- `renderCommand` added as a thin alias of `renderTemplate` (call-site clarity)
- `compileCommands` now returns `Either [Text] [Operation]`, interpolating both
  `run` and `workDir` fields
- All 556 tests pass, including 4 new `TemplateSpec` tests and 3 new `PlanSpec` tests
- Full workspace builds cleanly (`cabal build all`)
- No changes needed to preview, execution, CLI, Dhall schema, or effect layers


## Context and Orientation

### Key types

**`Command`** — defined at `seihou-core/src/Seihou/Core/Types.hs:149-154`:
```haskell
data Command = Command
  { run :: Text,           -- Shell command string (currently passed verbatim)
    workDir :: Maybe Text, -- Optional working directory (currently passed verbatim)
    condition :: Maybe Expr -- Optional "when" condition
  }
```

**`Operation`** — the `RunCommandOp` variant at `seihou-core/src/Seihou/Core/Types.hs:183-186`:
```haskell
  | RunCommandOp
      { command :: Text,       -- The shell command to execute
        workDir :: Maybe FilePath
      }
```

**`renderTemplate`** — at `seihou-core/src/Seihou/Engine/Template.hs:24`:
```haskell
renderTemplate :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
```

### The gap

`compileCommands` at `seihou-core/src/Seihou/Engine/Plan.hs:46-55` passes `cmd.run`
and `cmd.workDir` through without interpolation:

```haskell
compileCommands :: Map VarName VarValue -> [Command] -> [Operation]
compileCommands vars = concatMap compileCommand
  where
    compileCommand cmd =
      let shouldRun = case cmd.condition of
            Nothing -> True
            Just expr -> evalExpr vars expr
       in if shouldRun
            then [RunCommandOp cmd.run (fmap T.unpack cmd.workDir)]
            else []
```

Notice `cmd.run` is used directly. Compare with `compileTemplateStep` (same file,
line ~101) which calls `renderTemplate` on both the source content and destination
path.

### Downstream consumers

- `executeCommand` in `seihou-cli/src/Seihou/CLI/Run.hs:324` receives the
  `RunCommandOp` text and passes it to `sh -c`. After this change it will receive
  the already-interpolated string.
- `opToPreview` in `seihou-core/src/Seihou/Engine/Preview.hs:74` renders
  `CommandPreview cmd` for dry-run display. After this change it will show the
  interpolated command.
- `dryRunPlan` in `seihou-core/src/Seihou/Engine/Execute.hs:101` formats
  `RunCommandOp cmd _` as `"  run   " <> cmd`. Same benefit.

### Test infrastructure

- `seihou-core/test/Seihou/Engine/TemplateSpec.hs` — unit tests for `renderTemplate`
- `seihou-core/test/Seihou/Engine/PlanSpec.hs` — integration tests for `compilePlan`
- `seihou-core/test/fixtures/command-test/module.dhall` — fixture with commands
- Tests use `tasty` + `hspec`. Run with `cabal test seihou-core`.


## Plan of Work

This is a small, focused change. One milestone.

### Milestone 1: Interpolate command strings during plan compilation

**Scope**: Modify `compileCommands` to run `renderTemplate` on `cmd.run` and
`cmd.workDir`, collect errors, and add tests.

**What exists at the end**: Commands with `{{var}}` placeholders are resolved before
execution. Dry-run previews show the final interpolated commands. Unresolvable
placeholders fail the plan.

**Acceptance criteria**:
1. A module with `run = "echo {{project.name}}"` and `project.name = "my-app"`
   produces `RunCommandOp "echo my-app" Nothing`.
2. A module with `workDir = Some "{{project.name}}"` produces
   `RunCommandOp ... (Just "my-app")`.
3. A module with `run = "echo {{missing}}"` where `missing` is not in vars produces
   a compilation error.
4. Escape sequences work: `run = "echo \\{{literal}}"` produces
   `RunCommandOp "echo {{literal}}" Nothing`.
5. All existing tests pass unchanged.

#### File changes

**1. `seihou-core/src/Seihou/Engine/Template.hs`** — export a convenience alias.

Add to the export list:
```haskell
renderCommand,
```

Add after `renderDestPath`:
```haskell
-- | Render placeholders in a shell command string.
-- Same substitution as 'renderTemplate' but named for clarity at call sites.
renderCommand :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderCommand = renderTemplate
```

This is a thin alias. Its purpose is call-site readability in `Plan.hs`.

**2. `seihou-core/src/Seihou/Engine/Plan.hs`** — interpolate in `compileCommands`.

The current `compileCommands` is pure and returns `[Operation]`. Because
interpolation can fail, the return type must change to
`Either [Text] [Operation]` and the caller must collect errors.

Replace `compileCommands` (lines 46-55) with:

```haskell
-- | Compile commands into 'RunCommandOp' operations, interpolating
-- @{{var}}@ placeholders in the @run@ and @workDir@ fields.
-- Commands whose @when@ condition evaluates to False are skipped.
compileCommands :: Map VarName VarValue -> [Command] -> Either [Text] [Operation]
compileCommands vars = foldl' go (Right [])
  where
    go (Left errs) cmd = Left (errs ++ compileErrors cmd)
    go (Right ops) cmd =
      let shouldRun = case cmd.condition of
            Nothing -> True
            Just expr -> evalExpr vars expr
       in if shouldRun
            then case compileOneCommand vars cmd of
              Left cmdErrs -> Left cmdErrs
              Right op -> Right (ops ++ [op])
            else Right ops

    compileErrors cmd = case compileOneCommand vars cmd of
      Left es -> es
      Right _ -> []

compileOneCommand :: Map VarName VarValue -> Command -> Either [Text] Operation
compileOneCommand vars cmd =
  let runResult = renderCommand cmd.run vars
      wdResult = case cmd.workDir of
        Nothing -> Right Nothing
        Just wd -> Just <$> renderCommand wd vars
      collectErrors = case (runResult, wdResult) of
        (Left e1, Left e2) -> Left (map formatPlaceholderError (e1 ++ e2))
        (Left e1, _) -> Left (map formatPlaceholderError e1)
        (_, Left e2) -> Left (map formatPlaceholderError e2)
        (Right r, Right w) -> Right (RunCommandOp r (fmap T.unpack w))
   in collectErrors
```

Update the caller in `compilePlan` (line 41). Currently:

```haskell
then Right <$> pure (deduplicateDirs (concat allOps) ++ compileCommands vars modul.commands)
```

Change to:

```haskell
then case compileCommands vars modul.commands of
  Left cmdErrs -> pure (Left cmdErrs)
  Right cmdOps -> Right <$> pure (deduplicateDirs (concat allOps) ++ cmdOps)
```

Add `renderCommand` to the import of `Seihou.Engine.Template`.

**3. `seihou-core/test/Seihou/Engine/TemplateSpec.hs`** — add command-interpolation tests.

Add a `describe "renderCommand"` block with tests for:
- Simple variable substitution in a command string
- Multiple placeholders
- Escape sequence (`\{{`)
- Unresolved placeholder produces error

**4. `seihou-core/test/Seihou/Engine/PlanSpec.hs`** — add plan-level tests.

Add tests:
- "interpolates {{var}} in command run field"
- "interpolates {{var}} in command workDir field"
- "fails compilation when command has unresolved placeholder"
- "handles escape sequence in command"

**5. `seihou-core/test/fixtures/command-test/module.dhall`** — update fixture.

Change the first command from `"echo hello"` to `"echo {{project.name}}"` so the
integration test exercises interpolation.


## Concrete Steps

All commands run from the repository root:
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1**: Edit `seihou-core/src/Seihou/Engine/Template.hs`
- Add `renderCommand` to export list (line 4)
- Add `renderCommand` function after `renderDestPath` (after line 35)

**Step 2**: Edit `seihou-core/src/Seihou/Engine/Plan.hs`
- Add `renderCommand` to the `Seihou.Engine.Template` import
- Replace `compileCommands` (lines 46-55) with the interpolating version
- Add `compileOneCommand` helper
- Update the caller at line 41

**Step 3**: Build and verify compilation:
```sh
cabal build seihou-core
```
Expected: builds successfully with no errors.

**Step 4**: Add tests to `seihou-core/test/Seihou/Engine/TemplateSpec.hs`:
```haskell
describe "renderCommand" $ do
  it "substitutes variables in a command string" $ do
    let vars = Map.fromList [("project.name", VText "my-app")]
    renderCommand "echo {{project.name}}" vars
      `shouldBe` Right "echo my-app"

  it "substitutes multiple placeholders" $ do
    let vars = Map.fromList [("name", VText "app"), ("ver", VText "1.0")]
    renderCommand "echo {{name}}-{{ver}}" vars
      `shouldBe` Right "echo app-1.0"

  it "handles escape sequence" $ do
    let vars = Map.empty
    renderCommand "echo \\{{literal}}" vars
      `shouldBe` Right "echo {{literal}}"

  it "reports unresolved placeholder" $ do
    let vars = Map.empty
    case renderCommand "echo {{missing}}" vars of
      Left errs -> length errs `shouldBe` 1
      Right _ -> expectationFailure "Expected Left"
```

**Step 5**: Add tests to `seihou-core/test/Seihou/Engine/PlanSpec.hs`:
```haskell
it "interpolates {{var}} in command run field" $ do
  withFixture [("data.txt", "content")] $ \baseDir -> do
    let modul = Module
          { name = "test", description = Nothing, vars = [], exports = []
          , prompts = [], steps = [Step Copy "data.txt" "data.txt" Nothing Nothing]
          , commands = [Command "echo {{name}}" Nothing Nothing]
          , dependencies = []
          }
        vars = Map.fromList [("name", VText "my-app")]
    result <- compilePlan baseDir modul vars
    case result of
      Right ops -> do
        let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
        length cmdOps `shouldBe` 1
        (cmdOps !! 0).command `shouldBe` "echo my-app"
      Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

it "interpolates {{var}} in command workDir field" $ do
  withFixture [("data.txt", "content")] $ \baseDir -> do
    let modul = Module
          { name = "test", description = Nothing, vars = [], exports = []
          , prompts = [], steps = [Step Copy "data.txt" "data.txt" Nothing Nothing]
          , commands = [Command "cabal build" (Just "{{name}}") Nothing]
          , dependencies = []
          }
        vars = Map.fromList [("name", VText "my-app")]
    result <- compilePlan baseDir modul vars
    case result of
      Right ops -> do
        let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
        length cmdOps `shouldBe` 1
        (cmdOps !! 0).workDir `shouldBe` Just "my-app"
      Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

it "fails compilation when command has unresolved placeholder" $ do
  withFixture [("data.txt", "content")] $ \baseDir -> do
    let modul = Module
          { name = "test", description = Nothing, vars = [], exports = []
          , prompts = [], steps = [Step Copy "data.txt" "data.txt" Nothing Nothing]
          , commands = [Command "echo {{missing}}" Nothing Nothing]
          , dependencies = []
          }
        vars = Map.empty
    result <- compilePlan baseDir modul vars
    case result of
      Left errs -> do
        length errs `shouldSatisfy` (>= 1)
        T.isInfixOf "missing" (errs !! 0) `shouldBe` True
      Right _ -> expectationFailure "Expected Left"
```

**Step 6**: Update `seihou-core/test/fixtures/command-test/module.dhall`:
Change line 23 from `"echo hello"` to `"echo {{project.name}}"`.

**Step 7**: Run all tests:
```sh
cabal test seihou-core
```
Expected: all tests pass, including the new ones and all existing ones.

**Step 8**: Build the full workspace:
```sh
cabal build all
```
Expected: clean build.


## Validation and Acceptance

1. **Unit test**: `renderCommand "echo {{project.name}}" (Map.fromList [("project.name", VText "my-app")])` returns `Right "echo my-app"`.

2. **Plan test**: A module with `commands = [Command "echo {{name}}" Nothing Nothing]` and `vars = Map.fromList [("name", VText "my-app")]` produces `[..., RunCommandOp "echo my-app" Nothing]`.

3. **Error test**: A module with `commands = [Command "echo {{missing}}" Nothing Nothing]` and `vars = Map.empty` produces `Left [...]` containing "missing".

4. **workDir test**: `Command "build" (Just "{{name}}") Nothing` with `name = "my-app"` produces `RunCommandOp "build" (Just "my-app")`.

5. **Regression**: All existing tests in `cabal test seihou-core` continue to pass. The existing command tests (e.g., "compiles unconditional command to RunCommandOp") still work because commands without placeholders pass through unchanged.

6. **Dry-run preview**: After implementation, a `seihou run --dry-run` on a module with `run = "echo {{project.name}}"` will display `run    echo my-app` in the preview, not `run    echo {{project.name}}`.


## Idempotence and Recovery

All changes are to source files under version control. If any step fails:
- `git checkout -- seihou-core/src seihou-core/test` restores the original state.
- Each step can be re-applied safely; edits are idempotent.
- No database, network, or external service operations are involved.


## Interfaces and Dependencies

**No new dependencies.** This change uses only modules already imported by `Plan.hs`:

- `Seihou.Engine.Template` (already imported) — add `renderCommand` to import list
- `Seihou.Core.Types` (already imported) — `PlaceholderError`, `formatPlaceholderError`

**New export from `Seihou.Engine.Template`**:
```haskell
renderCommand :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
```

**Changed signature in `Seihou.Engine.Plan`** (internal, not exported):
```haskell
-- Before:
compileCommands :: Map VarName VarValue -> [Command] -> [Operation]
-- After:
compileCommands :: Map VarName VarValue -> [Command] -> Either [Text] [Operation]
```

**New internal function in `Seihou.Engine.Plan`**:
```haskell
compileOneCommand :: Map VarName VarValue -> Command -> Either [Text] Operation
```

No changes to Dhall schemas, CLI parsers, effect types, or public API types.
