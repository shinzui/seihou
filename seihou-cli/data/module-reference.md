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
`append-section`, `replace-section`, `append-file`, `prepend-file`, or
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
restore links with `seihou sync`, without installed modules or shell commands.
Do not implement this with `ln -s` commands or command receipts.
For existing applications, `seihou sync` discovers missing declarations and
previews the necessary adoption, fetching dependencies and reusing saved inputs.
The same command restores already-declared links offline. Its preview can propose untracking
unchanged matching symlinks while retaining working links; do not manipulate the
index manually for normal adoption. Commit the manifest, source and ignore rules,
and any accepted tracked-link removals. See `seihou help sync`.

The schema also accepts `lifecycle = Some "seed"` for whole-file copy, template,
or dhall-text steps without patches, and schema 8 introduces seed receipts.
Create-once handoff behavior is not implemented yet: do not promise that seed
files will be preserved on reruns/updates or recommend seeds for that purpose.

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
Without a removal declaration, `seihou remove NAME` refuses. Preview with
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
