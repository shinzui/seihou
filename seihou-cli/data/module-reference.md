## Module Schema Reference

Start with `seihou new-module NAME` and edit the generated `module.dhall`.
Preserve its pinned schema import and integrity hash; use record completion
(`S.Module::{ ... }`, `S.Step::{ ... }`) so optional fields get current defaults.
For an older module, preview `seihou schema-upgrade PATH --dry-run`, then apply
`seihou schema-upgrade PATH`. Do not invent a schema commit or hash.
Module names match `[a-z][a-z0-9-]*`.

With `S` bound to the generated schema import, the module body can be:

```dhall
S.Module::{
  name = "my-module",
  version = Some "1.0.0",
  description = Some "What this module does",
  vars = [ S.VarDecl::{ name = "project.name", type = "text", required = True } ],
  prompts = [ S.Prompt::{ var = "project.name", text = "Project name?" } ],
  steps = [ S.Step::{ strategy = "template", src = "README.md.tpl", dest = "README.md" } ],
  dependencies = [ S.Dependency::{ module = "nix-base" } ]
}
```

### Steps and lifecycles

Ordinary file steps read `src` from the module's `files/` directory and write
`dest` in the consuming project. Strategies are `copy`, `template`, `dhall-text`
(Text output), and `structured` (Dhall record to JSON/YAML with composition).
The strategy field selects processing; filename extensions are conventions.
`when : Optional Text` gates a step. `patch : Optional Text` selects
`append-section`, `append-file`, `prepend-file`, or
`append-line-if-absent`. The default `lifecycle = None Text` means managed.

For ignored directory links, use `strategy = "symlink"` with
`lifecycle = Some "checkout"` and no patch:

```dhall
S.Step::{ strategy = "symlink", src = "agents/skills/my-skill",
          dest = ".agents/skills/my-skill", lifecycle = Some "checkout" }
```

Here `src` is a real directory in the consuming project, not in the installed
module. Source and destination must be safe, non-overlapping project-relative
paths; `.git` and `.seihou` components are reserved. The destination must be
ignored and untracked. Declare an ignore rule as a managed step when needed.
Run/update records portable intent in the manifest; fresh clones and worktrees
restore links with `seihou sync`, without installed modules. Use typed links for
observable directory wiring rather than shell `ln` commands or command receipts.
For existing applications, a maintainer runs ordinary `seihou update ROOT` for the
recorded application, accepts the preview, and commits manifest, baselines, source
assets, ignore rules and any previewed tracked-link adoption. Teammates receive
that commit and run sync. Sync never fetches or updates specifications.

### Commands and execution lifecycle

The current schema uses a tagged action; new runtimes also accept pinned legacy
`{ run, workDir, when }` records as ordinary application commands.

```dhall
commands =
  [ S.Command::{ action = S.Command.Action.Apply "echo applied" }
  , S.Command::{ action = S.Command.Action.Checkout "mkdir -p .local; echo ready > .local/setup" }
  ]
```

Application commands use successful receipts during update; checkout commands are
explicitly repeatable local setup. Run and accepted actionable update execute both
in declaration/dependency order, while `--no-commands` suppresses both and retains
checkout declarations. A true no-op update executes neither. Sync executes only the
resolved checkout subset stored in manifest schema 10, without module/configuration
resolution or receipts. Repeated sync reruns all of it. Commit scripts needed by
these commands as project assets; never depend on a producer cache path.

Checkout working directories must be real project-relative directories already
present in a receiving clone, with no symlink ancestors. Sync preflights all links
and working directories, creates links first, then executes commands sequentially.
A first failure stops the phase and reports the completed prefix and unrun tail;
retry with sync after correcting it. Arbitrary shell runs with user permissions,
may use the network and external tools, and cannot be undone by Seihou. Authors
must keep it repeatable and keep intended writes outside managed/tracked state.
Removal commands accept only application actions. Removing a checkout declaration
stops future execution and does not invent an inverse shell action.

`lifecycle = Some "seed"` on a whole-file copy, template or dhall-text step
creates an absent file once and hands it to the project. No patches, structured
merges or symlinks are allowed. Existing regular files are kept. Manifest receipts
remember settlement and exact owning instances without hashes/baselines; edits
and deliberate deletion stay with the project through rerun, force, update,
status, diff and removal. Last-claim retirement forgets settlement, preserving disk.
An ordinary `seihou update TARGET` fetches producers/dependencies and previews
`release to project` for managed-to-seed transitions; no install or file-by-file
release prompts are needed. Reverse adoption requires explicit interactive
keep/accept consent, even with force. Declarative migrations/removal cannot mutate
seeds; arbitrary shell commands are unsandboxed and authors must keep them away.
Seed-producing modules require Seihou 0.11.0.0 or newer. Older binaries can
ignore lifecycle and overwrite content; users must update the runtime first.
For example:

```dhall
S.Step::{ strategy = "template", src = "README.md.tpl",
          dest = "README.md", lifecycle = Some "seed" }
```

### Variables and dependencies

Declare `text`, `bool`, `int`, `list text`, or `choice` variables. Text lists use
comma-separated values. The decoder also recognizes `list bool` and `list int`,
but CLI coercion of those lists is not implemented. Choices come from a prompt's
`choices` list. Optional declarations include `default`, `description`,
`required`, and `validation`. Use `seihou vars NAME --explain` to inspect values.

Initial resolution: CLI `--var`, `SEIHOU_VAR_*` environment, local config,
namespace config, context config, global config, parent dependency bindings,
then defaults; interactive prompts fill missing values. Ordinary updates reuse
saved application values immediately after CLI overrides. `--reconfigure`
intentionally resolves afresh. Agent provider settings use a separate chain;
inspect it with `seihou agent config` and `seihou help agent`.

Parameterized dependencies use
`S.Dependency::{ module = "nix-flake", vars = [ { name = "nix.system", value = "aarch64-darwin" } ] }`.
Exports use `{ var : Text, alias : Optional Text }`. For a named composition
without new generation logic, use `seihou new-recipe NAME --module MODULE`
(repeat `--module`), then `seihou run NAME`; see `seihou help recipes`.

### Removal

```dhall
removal = Some S.Removal::{ steps =
  [ S.RemovalStep::{ action = "remove-file", dest = "README.md" }
  , S.RemovalStep::{ action = "remove-section", dest = ".gitignore" }
  ] }
```

Removal steps use `action`, `dest`, and optional `src` (a Dhall rewrite function
under `files/` for `rewrite-file`). `S.Removal` also has `commands`.
Managed-file removal requires a removal declaration. Recorded checkout-only and
seed-only owners can be removed without one. Seed retirement keeps project files;
checkout retirement removes only the expected link and stops future setup, without
inventing inverse shell. Preview with
`seihou remove NAME --dry-run`; review conflicts before using `--force`.

### Versioning and migrations

Set an explicit module version. Declare layout changes with `S.Migration` and
`S.MigrationOp.MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, or `RunCommand`.
Edges run in ascending `from` order within the requested version window; gaps
are allowed, duplicate starts are invalid, and overlaps/overshoots are skipped.
Content-only changes normally need no migration: `seihou update TARGET`
reconciles generated content with user edits. It owns fetching, migrations,
inputs and cache publication in one preview/confirmation workflow.
Use `seihou migrate` for deliberate lower-level recovery or intermediate targets;
`seihou upgrade` only refreshes the installed cache. For blocked updates, inspect
`seihou agent upgrade TARGET --check` before requesting an agent repair.
See `seihou help update`, `seihou help migrations`, and `seihou help manifest`.
