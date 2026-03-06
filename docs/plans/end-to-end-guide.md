# Create End-to-End Usage Guide

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a new user discovering Seihou for the first time can follow a single guide document that walks them through every step of the workflow: initializing Seihou, creating a module from scratch, running it to generate a project, inspecting the results, making changes, and composing multiple modules together. The guide lives at `docs/user/getting-started.md` and uses a concrete, reproducible example (a Haskell project) that the reader types along with. A companion module-authoring reference at `docs/user/module-authoring.md` covers the Dhall module format, all four generation strategies, variable types, conditionals, and composition patterns.

The guide is user-facing prose, not developer documentation. It assumes no prior knowledge of Seihou or Dhall. After following it, the reader should be able to create their own modules and use every CLI command confidently.


## Progress

- [x] M1-1: Create `docs/user/` directory (2026-03-06)
- [x] M1-2: Write `docs/user/getting-started.md` — the end-to-end walkthrough (2026-03-06)
- [x] M1-3: Write `docs/user/module-authoring.md` — the module format reference (2026-03-06)
- [x] M1-4: Update `README.md` to link to the new guides and add missing command docs (diff, list, config) (2026-03-06)
- [x] M1-5: Review both guides for accuracy against actual CLI output — verified all help text, flags, command names, and module.dhall format against live CLI and source (2026-03-06)
- [x] M1-6: Commit — `8968c4a` (2026-03-06)


## Surprises & Discoveries

- The README was missing documentation for three CLI commands: `diff`, `list`, and `config`. Added them as part of the README update.
  Date: 2026-03-06

- The `commands` field in `module.dhall` scaffold includes a `when` field (`{ run : Text, workDir : Optional Text, when : Optional Text }`) that was not in the original product spec's command type. The implementation supports conditional commands, which is documented in the module-authoring reference.
  Date: 2026-03-06


## Decision Log

- Decision: Create two documents — a narrative getting-started guide and a reference module-authoring guide — rather than one monolithic document.
  Rationale: The getting-started guide tells a story (do this, then this, observe that) while the module-authoring guide is reference material (all strategies, all variable types, all options). Combining them would create a document too long to follow linearly and too narrative to use as a reference. Two complementary documents serve both needs.
  Date: 2026-03-06

- Decision: Place guides in `docs/user/` rather than `docs/guides/` or the repository root.
  Rationale: The existing `docs/` tree separates concerns: `docs/dev/` for developer docs, `docs/product-specs/` for specs, `docs/plans/` for execution plans. A `docs/user/` directory parallels this structure and clearly signals audience. The directory already exists (empty) in the repository.
  Date: 2026-03-06

- Decision: Use the `haskell-base` test fixture as the running example rather than inventing a new module.
  Rationale: The `haskell-base` fixture at `seihou-core/test/fixtures/haskell-base/` is a complete, working module with all three generation strategies (copy, template, dhall-text), conditional steps, variable exports, prompts, and a shell command. It demonstrates every major feature in a realistic context. Using it means the guide's examples are grounded in tested code.
  Date: 2026-03-06

- Decision: The guide will show commands and expected output but not require the reader to have modules installed — the new-module scaffolding workflow is self-contained.
  Rationale: A getting-started guide that requires pre-existing modules would have a chicken-and-egg problem. The guide walks the reader through creating a module from scratch, so they can follow along with nothing pre-installed.
  Date: 2026-03-06


## Outcomes & Retrospective

Implementation complete. Two user-facing documentation files created:

- **`docs/user/getting-started.md`** (~300 lines) — Narrative walkthrough covering the complete workflow: init, new-module, customize, validate, dry-run, run, status, diff, config, list, install, and composition. Uses a concrete Haskell project example.

- **`docs/user/module-authoring.md`** (~350 lines) — Complete reference covering module structure, module.dhall format, all five variable types, prompts, all four generation strategies (copy, template, dhall-text, structured), variable exports, commands, dependencies and composition, configuration scopes, environment variable mapping, expression language, module search paths, validation, and best practices.

- **`README.md`** updated with Documentation section linking both guides, plus added missing command documentation for `diff`, `list`, and `config`.

All CLI flags, command names, and module.dhall format verified against live `seihou --help` output and source code. Both guides cross-reference each other. The getting-started guide is self-contained — a reader with no prior Seihou knowledge can follow it from start to finish.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. Users define reusable "modules" — directories containing a `module.dhall` definition and template files — then run `seihou run <module>` to generate projects. The system resolves variables from multiple sources (CLI flags, environment, config files, prompts), compiles a generation plan, diffs against existing state, and writes files to disk.

The codebase lives in a multi-package Cabal workspace:

- `seihou-core/` — the library: module loading, Dhall evaluation, variable resolution, plan compilation, execution, manifest tracking
- `seihou-cli/` — the executable: 10 CLI commands (`init`, `run`, `vars`, `install`, `status`, `diff`, `list`, `new-module`, `validate-module`, `config`)

Currently, the only user-facing documentation is `README.md` at the repository root, which provides a quick-start snippet and brief command descriptions. The `docs/dev/` tree contains detailed design specifications, but these are developer-focused and assume familiarity with the codebase. There is no tutorial-style guide that walks a new user through the complete workflow.

The `docs/user/` directory exists but is empty.

### Key CLI commands the guide will cover

All commands are invoked via `seihou <command>`. The executable is built from `seihou-cli/src/Main.hs` and dispatches to handler modules in `seihou-cli/src/Seihou/CLI/`.

1. `seihou init` — Creates `~/.config/seihou/` with `config.dhall`, `modules/`, and `installed/` subdirectories. Idempotent.
2. `seihou new-module NAME` — Scaffolds a module directory with `module.dhall`, `schema/Module.dhall`, and `files/README.md.tpl`.
3. `seihou validate-module [PATH]` — Validates a module: Dhall evaluation, variable uniqueness, prompt references, step source files, export references.
4. `seihou run MODULE [--var KEY=VALUE...] [--dry-run] [--diff] [--force]` — Loads module, resolves variables, compiles plan, executes.
5. `seihou vars MODULE [--explain]` — Shows variable declarations or resolved values with provenance.
6. `seihou status` — Shows applied modules, tracked files, and their states from `.seihou/manifest.json`.
7. `seihou diff` — Shows files that changed since last generation (modified, deleted).
8. `seihou list` — Lists all available modules across search paths.
9. `seihou config set|get|unset|list` — Manages configuration values at local, namespace, or global scope.
10. `seihou install GIT-URL` — Clones and installs a module from a git repository.

### Module structure

A module is a directory containing:

    my-module/
    ├── module.dhall          # Required: declares name, vars, steps, etc.
    └── files/                # Source artifacts referenced by steps
        ├── README.md.tpl     # Template strategy: {{var}} placeholders
        ├── LICENSE            # Copy strategy: verbatim copy
        └── config.dhall      # DhallText strategy: Dhall evaluates to text

The `module.dhall` file is a Dhall record with fields: `name`, `description`, `vars`, `exports`, `prompts`, `steps`, `commands`, `dependencies`.

### Generation strategies

1. **Copy** (`strategy = "copy"`) — Copies the source file verbatim to the destination.
2. **Template** (`strategy = "template"`) — Replaces `{{variable.name}}` placeholders with resolved values.
3. **DhallText** (`strategy = "dhall-text"`) — Injects variables as Dhall `let` bindings, evaluates to Text.
4. **Structured** (`strategy = "structured"`) — Evaluates Dhall to a record, serializes as JSON or YAML.

### Variable resolution precedence (first match wins)

1. CLI flags (`--var key=value`)
2. Environment variables (`SEIHOU_VAR_KEY`)
3. Local project config (`.seihou/config.dhall`)
4. Namespace config (`~/.config/seihou/namespaces/<ns>/config.dhall`)
5. Global config (`~/.config/seihou/config.dhall`)
6. Module defaults (`default = Some "value"` in `module.dhall`)

### Test fixtures (for reference)

The `seihou-core/test/fixtures/` directory contains complete working modules:

- `haskell-base/` — Haskell project with template, copy, and dhall-text strategies; 3 variables, 1 prompt, 5 steps, 1 command, variable exports
- `haskell-with-nix/` — Depends on `haskell-base` and `nix-flake`; demonstrates composition
- `nix-flake/` — Depends on `nix-base`; Nix flake generation
- `nix-base/` — Base Nix module
- `command-test/` — Shell command execution
- `structured-merge-a/`, `structured-merge-b/` — Structured strategy with record merging


## Plan of Work

### Milestone 1: Write the guides and update README

This milestone produces two new documentation files and updates the README. At the end, `docs/user/getting-started.md` and `docs/user/module-authoring.md` exist with complete, accurate content, and `README.md` links to them.

**Step 1** (M1-1): Create the `docs/user/` directory (it may already exist but be empty).

**Step 2** (M1-2): Write `docs/user/getting-started.md`. This is the core deliverable — a narrative walkthrough that takes the reader from zero to a working project. The guide follows this arc:

1. **Introduction** — What Seihou is, what the reader will build (a Haskell project from a custom module), what commands they will learn.

2. **Prerequisites** — Seihou must be installed (or built from source with `cabal run seihou`). No other dependencies.

3. **Step 1: Initialize Seihou** — Run `seihou init`. Show expected output. Explain what was created (config directory, modules directory, installed directory).

4. **Step 2: Create your first module** — Run `seihou new-module my-haskell`. Show the scaffolded directory structure. Open `module.dhall` and explain each field. The generated boilerplate has one variable (`project.name`), one prompt, and one template step.

5. **Step 3: Customize the module** — Edit `module.dhall` to add a second variable (`project.version` with a default), a conditional LICENSE step, and a DhallText step. Edit the template file. Create additional files. This section teaches the module format by building on the scaffold.

6. **Step 4: Validate the module** — Run `seihou validate-module ./my-haskell`. Show expected output (all checks pass). Then intentionally break something (remove a referenced source file) and show the validation error.

7. **Step 5: Preview the generation plan** — Run `seihou run my-haskell --dry-run --var project.name=demo-app`. Show the plan output. Explain what each line means (strategy, source module, file path).

8. **Step 6: Generate the project** — Run `seihou run my-haskell --var project.name=demo-app` in an empty directory. Show the prompt for `project.name` if not passed via `--var`. Show the files created. Inspect the generated files to verify placeholder substitution.

9. **Step 7: Check status** — Run `seihou status`. Show applied modules, tracked files, variable values.

10. **Step 8: Detect changes** — Manually edit a generated file. Run `seihou diff`. Show the modified file indicator.

11. **Step 9: Configure defaults** — Run `seihou config set project.version 1.0.0 --global`. Run `seihou vars my-haskell --explain` to see the config value appear in provenance.

12. **Step 10: List and discover** — Run `seihou list` to see the module. Mention search paths.

13. **Next steps** — Point to `module-authoring.md` for the full reference. Mention composition, installation from git, and the other commands.

**Step 3** (M1-3): Write `docs/user/module-authoring.md`. This is a reference document organized by topic:

1. **Module structure** — Directory layout, required files, `files/` directory.

2. **The module.dhall format** — Complete field-by-field reference with examples. Show the Dhall type. Explain each field.

3. **Variables** — Types (`text`, `bool`, `int`, `list`, `choice`), `required` vs optional, `default` values, `validation` patterns, `description`.

4. **Prompts** — Interactive prompts, `when` conditions, `choices` for selection prompts.

5. **Steps and strategies** — Each of the four strategies with examples: Copy (verbatim), Template (`{{var}}` syntax, escaping with `\{{`), DhallText (Dhall `let` bindings, evaluates to Text), Structured (Dhall record to JSON/YAML). Conditional steps with `when`.

6. **Variable exports** — Cross-module variable sharing, `alias` field, how exports interact with composition.

7. **Commands** — Post-generation shell commands, `workDir`, conditional execution.

8. **Dependencies and composition** — How modules declare dependencies, topological sort, how variables flow between modules, how files from multiple modules merge (section markers for text, deep merge for structured).

9. **Configuration scopes** — Local, namespace, global. Precedence chain. Environment variable mapping (`SEIHOU_VAR_` prefix).

10. **Expression language** — `Eq`, `IsSet`, `true`, `false`, `&&`, `||`, `!`. Used in `when` fields.

11. **Best practices** — Small focused modules, meaningful variable names, validate before sharing, use exports for composition.

**Step 4** (M1-4): Update `README.md` to add a "Documentation" section after the "Module Authoring" section, linking to both guides:

    ## Documentation

    - [Getting Started Guide](docs/user/getting-started.md) — End-to-end walkthrough
    - [Module Authoring Reference](docs/user/module-authoring.md) — Complete module format reference

**Step 5** (M1-5): Review both guides against actual CLI behavior. Run `seihou --help`, `seihou init --help`, `seihou run --help`, etc. and verify the guide's command examples and flags are accurate. Check that the module.dhall format described matches the actual Dhall type used by the evaluator.

**Step 6** (M1-6): Commit all changes.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1-1): Verify `docs/user/` exists:

    ls docs/user/

If empty or missing, create it.

**Step 2** (M1-2): Create `docs/user/getting-started.md` with the full narrative walkthrough described in the Plan of Work. The guide should be approximately 300-500 lines of Markdown.

**Step 3** (M1-3): Create `docs/user/module-authoring.md` with the complete reference. Approximately 400-600 lines.

**Step 4** (M1-4): Edit `README.md` to add a Documentation section with links.

**Step 5** (M1-5): Verify accuracy:

    cabal run seihou -- --help
    cabal run seihou -- init --help
    cabal run seihou -- run --help
    cabal run seihou -- vars --help
    cabal run seihou -- new-module --help
    cabal run seihou -- validate-module --help
    cabal run seihou -- config --help
    cabal run seihou -- list --help
    cabal run seihou -- diff --help
    cabal run seihou -- status --help
    cabal run seihou -- install --help

Compare output against the guide. Also verify the module.dhall format by reading the Dhall type definition in `seihou-core/test/fixtures/haskell-base/schema/Module.dhall` (if it exists) or by checking the evaluator's expected fields in `seihou-core/src/Seihou/Dhall/Eval.hs`.

**Step 6** (M1-6): Commit:

    git add docs/user/getting-started.md docs/user/module-authoring.md README.md
    git commit -m "Add end-to-end getting started guide and module authoring reference"


## Validation and Acceptance

This plan produces documentation, not code, so validation is primarily about accuracy and completeness.

**Accuracy check**: Every command shown in the guide must match the actual CLI. Run each `seihou <command> --help` and verify flags, argument names, and descriptions match the guide.

**Completeness check**: The getting-started guide must cover all 10 commands (at least briefly). The module-authoring guide must cover all four generation strategies, all five variable types, the expression language, exports, composition, and configuration scopes.

**Link check**: The README links to both guides. Both guides cross-reference each other.

**Readability check**: A reader with no Seihou knowledge should be able to follow the getting-started guide from top to bottom without needing to consult other documents.


## Idempotence and Recovery

All steps are safe to repeat. Writing documentation files is idempotent. If the guide needs revision, edit and re-commit.


## Interfaces and Dependencies

No code changes. No new library dependencies. The only files created or modified are:

- `docs/user/getting-started.md` (new)
- `docs/user/module-authoring.md` (new)
- `README.md` (modified — add Documentation section)
