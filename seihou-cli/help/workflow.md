WORKFLOW

Use `seihou --help` for commands, `seihou COMMAND --help` for exact options,
and `seihou help` for the full topic index. Help topics explain workflows;
they are not a second command parser.

FIRST USE

  seihou init
  seihou install GIT-URL --module NAME
  seihou vars NAME
  seihou run NAME --dry-run --var project.name=my-app
  seihou run NAME --var project.name=my-app
  seihou status

  Init creates user configuration safely. Project-local artifacts can be run
  without installing them. Modules and recipes use run; blueprints use agent
  run; reusable prompts use prompt run. Only supply variables they declare.
  See modules, recipes, blueprints, prompts, variables and git-repository.

EXISTING PROJECTS

  seihou update TARGET

  Update fetches recorded remote sources/dependencies, reuses accepted inputs,
  includes migrations and previews changes before confirmation. No prior install,
  upgrade or migrate sequence is needed. With no TARGET, it selects all recorded
  applications. `--dry-run` gives a separate preview. See update and migrations.

  seihou sync

  At the Git working-tree root, sync restores declared ignored directory links
  from the committed manifest, including in fresh clones and linked worktrees.
  It also executes explicitly repeatable checkout commands. No producer installation
  is needed. No declarations means zero recorded work. A maintainer adopts changed
  specs through ordinary update and commits them before teammates sync.

INSPECTION AND RECOVERY

  seihou status                 Applied artifacts, pending migrations and local links
  seihou status --full-prompt   Include stored blueprint prompts without truncation
  seihou diff                   Compare tracked managed files with disk
  seihou agent upgrade TARGET --check
                                Diagnose update readiness without repairs

  Use `seihou agent upgrade TARGET` for assistance when ordinary update is
  blocked. Older machine-specific manifests need explicit manifest upgrade;
  path-shaped origins may need manifest repair-origins. See manifest and agent.
  Preserve local edits; read a refusal's exact next action before using force.

REMOVAL AND COMMITS

  seihou remove NAME --dry-run
  seihou remove NAME

  Managed-file removal follows the module's removal declaration and protects
  conflicts. Recorded checkout-only owners can be removed without a custom spec.
  Review changes and commit portable manifest/config, real source directories
  and ignore rules. Accepted link adoption can stage tracked-link removals.
  Ignore discovery links and transient caches/traces. See modules and sync.

SHELL COMPLETIONS

  seihou completions bash
  seihou completions zsh
  seihou completions fish

  These print shell setup scripts; inspect `seihou completions --help` for
  installation examples. Extensions have independent help; see extensions.
