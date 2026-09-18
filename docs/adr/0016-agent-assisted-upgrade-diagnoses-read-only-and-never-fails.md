# ADR 0016 — Agent-assisted upgrade diagnoses read-only and never fails

- Status: Accepted
- Date: 2026-09-18

## Context

Upgrading a module in a project is two commands: `seihou upgrade <module>` refreshes the
installed copy, and `seihou update <module>` reconciles the project with it. In real
projects the second command kept failing. The cause was rarely the module. It was the
state of `.seihou/manifest.json`: a schema older than current, a shared file whose
shared-write mode nobody recorded (ADR 0012, ADR 0014), a co-owner whose recorded
version was no longer installed, or an origin recorded as a path on some laptop
(ADR 0001). Each failure had a documented remedy and a stable error code. Finding the
right remedy, in the right order, still cost users an afternoon. Each new failure shape
had been answered with another enhancement.

`seihou update` refuses correctly in each of these cases, and its output is scripted
against (`--json`, `error.code`). Weakening a refusal to make an upgrade "just work"
would trade a visible problem for a silent one (ADR 0003, ADR 0006).

## Decision

**`seihou agent upgrade MODULE` diagnoses, and an agent repairs.** The command gathers
the facts a repair needs and writes them into an *upgrade brief*: the current state, each
failure with its error code, a repair playbook keyed by those codes, safety rules, and a
definition of done. It then starts an interactive coding-agent session with the brief as
its system prompt. It is part of the `seihou agent` group, so provider, model, `--debug`,
and launch handling are shared with the other agent commands.

**Diagnosis is read-only.** It writes nothing under the project, the install cache, or the
manifest. Every probe is a read, a pure computation over the decoded manifest, or a dry
run (`seihou manifest upgrade --dry-run`, `seihou update MODULE --dry-run`) whose clones
go to a temporary directory. Planning an update would first recover an interrupted
transaction, and recovery writes. So when `pendingUpdateRecovery` finds a transaction
directory, the update probe is skipped and the brief says why. The agent then performs
the recovery in the open with `seihou update --dry-run`.

**The command never fails because of what it finds.** Every probe runs guarded, and each
probe that can reach the network is bounded (180 seconds) on a worker thread. The update
planner catches exceptions internally, so an interrupting timeout would be swallowed. A
missing manifest, a corrupt one, an unknown module, a timeout, a missing `claude` binary,
or an invalid agent configuration becomes a finding in the brief, not an exit status. The
brief is always written, and its path printed, outside the project under
`$XDG_STATE_HOME/seihou/agent-upgrade/`, with the temporary directory as a fallback.
It holds machine-local paths, so ADR 0001 keeps it out of anything checked in. When no
session can start, the command explains how to use the brief and exits 0. The only
non-zero exits are command-line syntax errors and the interactive session's own exit
code, passed through as `agent setup` and `agent run` do.

**Readiness is the checks behind a plain `seihou update MODULE`, exposed as a command.**
There are eight checks: `manifest-readable`, `manifest-schema-current`,
`no-interrupted-update`, `target-recorded`, `installed-copy-trusted`, `origins-portable`,
`shared-evidence-known`, and `update-plans-cleanly`. `seihou agent upgrade MODULE --check`
prints them and always exits 0. Its last line, `Upgrade readiness: ready` or
`Upgrade readiness: not ready (N ...)`, is the verdict for the agent, the user, scripts,
and tests alike. A check that could not be determined counts as not ready. The same
report is printed after an interactive session ends.

**The agent repairs through seihou's commands.** A manual edit of the manifest is a last
resort, only after a backup into the brief's directory. The brief states the invariants
as rules. Never invent an origin. Never mark a path `additive-only` without reading every
owner's operations. Never delete records to get past a gate. Never lower a recorded
version. Never change the install cache by hand. Never pass `--force` or
`--allow-downgrade` without the user's consent. Each session ends with a repair report
that names any seihou command that could not express a fix. That tells maintainers which
failure shape to automate next, as `seihou manifest repair-origins` and recorded-release
fetching were automated.

Every human `seihou update` failure ends with a line pointing at
`seihou agent upgrade <target>`. JSON output is unchanged.

## Consequences

- A failed upgrade has one next step that always works: run `seihou agent upgrade`.
  Before, the user had to find the right documentation page.
- The diagnosis can be run anywhere, any number of times, including in CI through
  `--check`, because it cannot change anything.
- The playbook in `seihou-cli/data/upgrade-prompt.md` must gain an entry whenever
  `seihou update` gains an error code.
- A failure shape that recurs in repair reports belongs in seihou itself, not in the
  playbook. Plans 97 and 98 are the model for that.

Rejected alternatives:

- **A `--repair` mode inside `seihou update`.** It would blur deterministic, scriptable
  refusals into best-effort fixes, and the remaining repairs need judgment: which remote is
  right, whether to broaden a selection, how to resolve a conflict.
- **Automatic repair without an agent.** The mechanical repairs already exist as commands
  (`seihou manifest upgrade`, `seihou manifest repair-origins`, fetching recorded
  releases). What remains needs judgment and consent.
- **Storing the brief in `.seihou/`.** It records machine-local paths, and `.seihou/`
  sits beside the checked-in manifest (ADR 0001).

## References

- `docs/plans/96-add-seihou-agent-upgrade-for-agent-assisted-module-upgrades-that-repair-manifest-state.md`
- `seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs`, `seihou-cli/src-exe/Seihou/CLI/AgentUpgrade.hs`,
  `seihou-cli/data/upgrade-prompt.md`
- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md),
  [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md),
  [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md),
  [ADR 0012](0012-an-additive-co-write-is-not-a-shared-path-conflict.md),
  [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md),
  [ADR 0015](0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
- `docs/cli/agent.md` (section `agent upgrade`)
