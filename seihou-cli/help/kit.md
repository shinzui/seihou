KIT — MANAGE CLAUDE CODE SKILLS AND SUBAGENTS

Seihou Kit lets you install, update, and remove Claude Code skills and
subagents from a remote repository (seihou-kit). Installed content is
automatically available in agent sessions (seihou agent assist, etc.).

COMMANDS

  seihou kit list                     List available skills and agents
  seihou kit install NAME             Install to user scope (global)
  seihou kit install NAME --project   Install to project scope (local)
  seihou kit update                   Pull latest and re-install all
  seihou kit update NAME              Pull latest and re-install one
  seihou kit uninstall NAME           Remove from user scope
  seihou kit uninstall NAME --project Remove from project scope
  seihou kit status                   Show installed items with scope

SCOPES

  User scope (default):
    ~/.config/seihou/agents/.claude/skills/<name>/
    ~/.config/seihou/agents/.claude/agents/<name>.md
    Available across all projects.

  Project scope (--project):
    .seihou/agents/.claude/skills/<name>/
    .seihou/agents/.claude/agents/<name>.md
    Scoped to the current project. Can be version-controlled.

HOW IT WORKS

  The kit repository is shallow-cloned to ~/.cache/seihou/kit/ on first
  use. Subsequent operations pull updates with git pull --ff-only.

  A kit.json manifest at the repo root enumerates all available skills
  and agents. The install command copies files from the cache to the
  target scope directory.

  When you run seihou agent assist (or bootstrap, setup), installed
  scope directories are passed to Claude Code via --add-dir flags.
  Claude Code discovers .claude/skills/ and .claude/agents/ within
  each add-dir automatically.

  The cache is disposable — delete ~/.cache/seihou/kit/ and it will
  be re-cloned on next use. If the network is unavailable but cached
  data exists, commands continue with cached data.
