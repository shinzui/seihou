# Changelog

User-facing release notes for Seihou. This is a curated summary of
user-visible changes; the [full engineering changelog](../../CHANGELOG.md) at
the repository root records every change, including internal refactors and
packaging.

Versions follow the Haskell [PVP](https://pvp.haskell.org/) (`A.B.C.D`). All
packages in the workspace share a single version.

## Unreleased

## [0.8.0.0] - 2026-09-10

### Added

- **You can now tell Seihou about an upgrade you did yourself.** Plenty of people
  upgrade a library by hand: they read the release notes, make the changes, and never
  run `seihou agent migrate` at all. Until now there was no way to say so. The edge had
  no receipt, so every later run planned it again, and the workarounds were all bad —
  hand-editing `.seihou/manifest.json` meant guessing the blueprint's origin, and
  guessing wrong produced a receipt that matched nothing; running the migration anyway
  spent a real provider session to discover there was nothing to do.

  `seihou agent migrate <blueprint> --mark-applied` records a receipt for every pending
  edge in the window without starting a session:

  ```text
  Marking 2 blueprint migration(s) as already applied, without running them:
    kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
    keiro-upgrade 2.4.0 -> 3.0.0

  Recorded 2 receipt(s). No agent session was started and no file was changed.
  ```

  No provider is contacted and no file in your working tree is read or written. The
  window is resolved exactly as for a real run, so `--from` and `--to` narrow it the
  same way, and edges owned by other blueprints that the window reaches through
  `entails` are marked under their own blueprint — which means a marked entailed edge
  suppresses a later direct run of that blueprint too. Edges that already have a receipt
  are skipped rather than restamped, so marking the same window twice is a no-op.

  A marked receipt is an ordinary applied receipt; nothing downstream can tell the
  difference, and `--rerun` is the correction if you mark something by mistake. The flag
  is refused alongside `--rerun` or `--debug`, both of which it contradicts, before
  anything is read or written.

- **Registry documentation now describes what your registry actually declares.**
  `seihou-okf-extension docs` used to show a module's dependencies, a bare list of its
  variable names, and its exports — so you could add a migration edge, a removal
  procedure, an interactive prompt or an agent launch preference and see none of it
  appear on the page.

  Every artifact feature now reaches the generated documentation. A module page lists
  each variable with its declared type, whether it is required, its default, its
  validation rule and its description; its export aliases; its interactive prompts with
  their choices and the condition that gates them; its generation steps with strategy,
  destination, patch operation and condition; its shell commands; its removal procedure;
  and each migration edge with the operations it performs. Recipes and blueprints show
  the variable bindings they preconfigure for each module they compose. Blueprints add
  their tool allowlist, agent launch preferences, version-probe command and migration
  edges. Agent prompts add their command-derived variables and guidance blocks. A section
  your artifact declares nothing for is left out rather than printed empty.

  Conditions read the way you wrote them, for example ``when `Eq nix.treefmt true` ``.

- **An entailed migration edge is a link when you can follow it.** If a blueprint edge
  entails an edge of another blueprint that the same registry publishes, the page links
  to that blueprint's page. If the entailed blueprint lives in another repository — the
  usual case — it is shown as labelled text ending `(declared outside this registry)`,
  since there is no page here to link to.

- **A page for the registry itself.** The bundle now includes one document naming the
  registry, its description, and every artifact it publishes grouped by kind, so there is
  a single place to start reading and `okf graph` has a root.

- **The bundle is checkable.** It is now an OKF v0.2 bundle: the root `index.md` declares
  the version, every subdirectory has a section index, and every page records the
  generator that produced it, so `okf trust okf-docs` reports a trust tier per page
  instead of nothing. The generator also writes the house profile it checked itself
  against to `okf-docs/profile.dhall`, so you can re-run the same check:

  ```bash
  okf validate okf-docs --strict
  okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
  ```

  Both checks run inside the generator too, *before* it writes anything — a bundle that
  would fail them is never written, and a failing run leaves your output directory alone.

- **New options on `seihou-okf-extension docs`**: `--generated-at DATE` stamps a
  generation date on every page (left off by default, so regenerating an unchanged
  registry produces byte-identical output and diffs cleanly in review); `--permissive`,
  `--profile PATH`, and `--no-profile` adjust how strictly the bundle is checked.

  A new guide, [Documenting a registry](registry-documentation.md), walks through what
  the command produces and which part of your `.dhall` files each section comes from.

## [0.7.0.0] - 2026-08-16

### Added

- **`seihou agent migrate` now infers the version window.** Both `--from` and
  `--to` used to be mandatory and typed by hand, which meant looking up two
  numbers before every upgrade — and for a cohort chain, looking up a version the
  consumer does not even declare. Either end may now be omitted:

  ```text
  $ seihou agent migrate keiro-upgrade
  Version window: 2.4.0 -> 3.0.0
    --from 2.4.0  [receipt: keiro-upgrade 2.0.0 -> 2.4.0, applied 2026-08-02]
    --to   3.0.0  [probe: nix eval --raw .#keiroVersion]
  ```

  The two ends draw on different sources on purpose. `--to` comes from a new
  optional `versionProbe` field: a shell command the *blueprint's author*
  declares, which reads the version the project depends on. Seihou still reads no
  Cabal, npm, Cargo, or Maven file itself — it stays language-agnostic by never
  guessing the command, because only the author knows where their library's
  version lives. `--from` comes from the project's own migration receipts: the
  highest version already migrated to. That matches the ordinary workflow, where
  the dependency is bumped first and the source is then carried up to it.

  A receipt recorded as *not applicable* deliberately does not count toward the
  inferred start — it records that an edge was considered and skipped, which is
  not progress.

  Nothing that works today stops working. An explicit flag always wins, a
  blueprint that declares no probe behaves exactly as before, and a probe that
  fails or prints something unparseable is a warning rather than a failure: its
  command, exit code, and output are printed, and the command falls through to
  asking for `--to`. The probe *is* executed under `--debug`, the one exception
  to migration debug contacting nothing, because the window decides which edges
  the preview shows.

  For blueprint authors, see
  [Supply a version probe](blueprint-migrations.md#supply-a-version-probe); for
  consumers, see
  [How the version window is inferred](blueprint-migrations.md#how-the-version-window-is-inferred).

- **A blueprint migration edge can now require another library's edge.** When a
  breaking change reaches consumers through an intermediary — `kiroku` ships it,
  `keiro` absorbs it in one of its own releases, and most projects depend on
  keiro and have never heard of kiroku — the upgrade knowledge lives one
  repository away from the version number the consumer actually knows. A
  blueprint edge can now declare that crossing it **entails** crossing an exact
  edge of another blueprint:

  ```dhall
  S.BlueprintMigration::{
  , from = "2.4.0"
  , to = "3.0.0"
  , prompt = ./migrations/2-4-to-3.md as Text
  , entails =
    [ S.EntailedEdge::{ blueprint = "kiroku-upgrade", from = "1.9.0", to = "2.0.0" } ]
  }
  ```

  One command then crosses both, in order, each step running with its own
  blueprint's shared prompt, reference files, allowed tools, and variables:

  ```text
  $ seihou agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0
  Running blueprint migration 1/2: kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
  Running blueprint migration 2/2: keiro-upgrade 2.4.0 -> 3.0.0
  ```

  Expansion is recursive, so a three-deep cohort works without any blueprint
  knowing the whole graph. The entailed step's receipt is written under the
  *entailed* blueprint's name and origin, which is what makes a shared edge
  crossed exactly once: a project that reached kiroku's edge through keiro finds
  nothing to do when it later runs `seihou agent migrate kiroku-upgrade`
  directly, and the reverse order behaves the same way. A project that depends on
  kiroku alone is unaffected by keiro's declaration entirely.

  A cycle, an entailed blueprint that is not installed, and a named edge the
  entailed blueprint does not declare are all hard errors that name the blueprint
  whose author must fix them — never a silently skipped step, because a consumer
  who does not know the cohort has no way to notice a missing member. The
  artifact guard covers every blueprint in the resolved chain, not just the one
  you named.

  See [Entail another library's edge](blueprint-migrations.md#entail-another-librarys-edge).

- **A blueprint migration edge can now report that it does not apply.** A
  well-written edge states its own precondition, and when a project does not meet
  it the correct action is to change nothing and say so. Seihou could only record
  two outcomes — the provider session returned, or it failed — so a deliberate,
  correct no-op was recorded as a completed upgrade. The edge that *should* have
  run once the precondition was met was then silently skipped forever.

  There is now a third outcome. An edge reports it by writing a one-line reason
  to a signal file `seihou` names in the prompt, or, for API providers that
  cannot write files, by ending its reply with `SEIHOU: not-applicable <reason>`.
  Seihou prints the reason, records the attempt with that outcome, and
  **continues to the next edge** — an inapplicable step is not a failure and does
  not halt a chain. Only an applied receipt suppresses a later run, so the edge is
  planned again next time, no `--rerun` needed:

  ```text
  Blueprint migration 1/2: 1.0.0 -> 2.0.0 — not applicable: the project has not adopted the bundle
  Running blueprint migration 2/2: 2.5.0 -> 3.0.0
  ...
  Completed 2 blueprint migration(s) for 'my-library' (1 not applicable).
  ```

  `seihou status` distinguishes the two:

  ```text
  Blueprint migrations:
    my-library v0.3.0: 1.0.0 -> 2.0.0 (applied 2026-07-20 15:02 UTC)
    my-library v0.3.0: 2.5.0 -> 3.0.0 (not applicable 2026-07-20 15:19 UTC -- no direct kiroku imports)
  ```

  Edge authors do not need to invent a convention: seihou's own framing prompt
  carries it, so an edge prompt only has to state what its precondition is.

  **One-time caveat.** Every receipt written before this release is read as
  applied, including any that was really a deliberate no-op — nothing on disk can
  tell the two apart after the fact. `--rerun` remains the remedy for those, as
  it was before. New receipts carry their outcome explicitly, and older manifests
  keep parsing unchanged.

- **`seihou agent run` and `seihou agent migrate` now refuse a stale or
  substituted artifact.** `seihou run` and `seihou migrate` have refused to
  generate from an artifact older than, or from a different repository than,
  `.seihou/manifest.json` records. The agent commands did not, even though
  `agent run` applies a blueprint's baseline modules to your working directory
  and rewrites the manifest, and `agent migrate` writes receipts that suppress
  future runs of the edges they name. Both now consult the same guard, refuse on
  the same terms, and accept the same `--allow-downgrade` override.

  ```text
  ✗ Refusing to run: your local copy of 'keiro-upgrade' is older than the
    version this project expects.

    Recorded in .seihou/manifest.json:  2.0.0
    Installed on this machine:          1.0.0

    Update your local copy first:
      seihou upgrade keiro-upgrade
  ```

  **This may refuse a command that succeeded before.** If your install cache
  lags behind what a colleague committed, run `seihou upgrade <name>`; if a
  blueprint of that name from another repository is installed, reinstall from
  the URL the message prints. `--allow-downgrade` proceeds anyway and prints
  what it overrode.

  `agent run` checks the blueprint and every module its baseline would generate
  from; `agent migrate` checks the blueprint only, since it applies no
  baselines. Neither checks an artifact it will not touch. A refusal happens
  before anything is written, so the working tree and the manifest are left
  byte-identical.

  `--debug` behaves differently for the two subcommands, because it always has:
  it is a true dry run for `agent migrate`, which therefore checks nothing,
  while `agent run --debug` still applies the baseline and still records
  provenance, so it is checked like any other run.

- **`seihou status` reports on the recorded blueprint.** A stale or substituted
  blueprint now appears alongside stale or substituted modules, so you find out
  before an `agent` command refuses.

- **`seihou install` refuses to replace an artifact that came from a different
  repository.** `~/.config/seihou/installed/` is keyed by an artifact's bare
  name across every repository you have ever installed from, and it is shared by
  every project on the machine. Installing over an existing entry used to print
  one line — `warning: overwriting existing installation of 'shared-thing'` —
  whether you were doing the routine thing (reinstalling the same artifact to
  pick up a new version) or the destructive thing (replacing one repository's
  artifact with a different repository's artifact of the same name). The routine
  case is overwhelmingly common, which is what trained everyone to skip the
  line.

  Seihou now reads the `.seihou-origin.json` it is about to delete and decides
  from it:

  ```text
  ✗ Refusing to install 'shared-thing': a different artifact
    is already installed under that name.

    Installed on this machine:  https://github.com/acme/one
    Incoming:                   https://github.com/acme/two

    These are different artifacts that happen to share a name. Installing
    would replace the first for every project on this machine.

    To replace it anyway, re-run with --force.
  ```

  Nothing is removed before that decision, so a refused install leaves the
  existing entry byte-identical, and the command exits non-zero. An entry with no
  `.seihou-origin.json` at all is refused the same way, because seihou cannot
  tell whether it is the same artifact. Two spellings of one git URL —
  `https://host/repo` and `https://host/repo.git` — are still one source.

  The new `--force` replaces the entry anyway and prints what it overrode. It is
  the only override for a registry entry, since `--name` applies to
  single-artifact repositories only.

  `seihou upgrade`, `seihou update`, and `seihou migrate` also write to the
  cache, but always from the URL the artifact itself records, so they are
  structurally same-source and have no `--force`. If one of them reports a
  source mismatch, the cache disagrees with its own provenance file, and each
  reports rather than overrides: `upgrade` marks the module failed, `migrate`
  warns that the project was migrated but the shared cache was left alone, and
  `update` fails the cache-publication step.

  See [`seihou install`](../cli/install.md#when-the-name-is-already-taken).

### Changed

- **`seihou agent migrate`'s `--from` and `--to` are now optional.** Its usage
  line changed from `seihou agent migrate BLUEPRINT --from VERSION --to VERSION
  [PROMPT]` to `seihou agent migrate BLUEPRINT [--from VERSION] [--to VERSION]
  [PROMPT]`. Every existing invocation is unaffected and prints exactly what it
  printed before; a run that omits either flag gains a two-line report of what
  was inferred and where it came from. Add `--verbose` to see an explicitly
  supplied end accounted for too.

- **`seihou agent migrate` now names the owning blueprint in every step label.**
  A chain can span several blueprints, so `Running blueprint migration 1/2:
  1.0.0 -> 2.0.0` became `Running blueprint migration 1/2: my-library 1.0.0 ->
  2.0.0`, and the `--debug` headers gained the same prefix. Scripts matching the
  old shape need updating; nothing else about the output changed.

- **A routine reinstall is quieter, and a failed registry batch now exits
  non-zero.** Reinstalling an artifact from the URL it is already installed from
  no longer prints `warning: overwriting existing installation of '<name>'`; the
  command already tells you what it installed on the line after. If you relied
  on that warning to notice replacements, the different-source refusal above is
  what now surfaces the case worth noticing.

  Separately, `seihou install` against a registry used to report
  `3 entries installed, 2 failed.` and exit zero, so a script could not tell a
  half-applied batch from a complete one. Every entry is still attempted and
  every failure still reported at the end, but the command now exits non-zero
  when any entry failed.

### Fixed

- **A blueprint migration edge is no longer skipped because a same-named
  blueprint from another repository already ran it.** `seihou agent migrate`
  skips any edge that already has a receipt in `.seihou/manifest.json`, and it
  used to decide "already has a receipt" from the blueprint's bare name plus the
  edge's `from` and `to` versions. Two repositories can publish a blueprint
  under the same name. If you ran the `1.0.0 -> 2.0.0` edge of `shared-upgrade`
  from one repository and later installed a different repository's
  `shared-upgrade`, its `1.0.0 -> 2.0.0` edge was dropped from the plan with no
  message at all — the run looked like an ordinary "nothing pending" for work
  that never happened.

  The manifest now records where each of these artifacts came from. The
  `blueprint` entry written by `seihou agent run`, every entry in
  `blueprintMigrations`, and the `recipe` entry all carry an `origin` block, in
  the same shape modules have always had:

  ```json
  {
    "name": "shared-upgrade",
    "origin": {
      "kind": "remote",
      "url": "https://github.com/acme/one",
      "artifact": "shared-upgrade"
    },
    "from": "1.0.0",
    "to": "2.0.0",
    "appliedAt": "2026-08-16T15:02:00Z"
  }
  ```

  A receipt now stands for the origin and name of the blueprint that owns the
  edge together with its `from` and `to` versions, so the two repositories keep
  separate receipts and both edges run. Two spellings of one git URL —
  `https://host/repo` and `https://host/repo.git` — still count as one origin.

  **One-time effect on existing projects.** Receipts written before this release
  carry no provenance, and nothing on disk can say retroactively which
  repository they came from, so they are read as "name only, provenance
  unverifiable". The first `seihou agent migrate` after upgrading may therefore
  list an edge you have already completed as pending. That is honest rather than
  a regression — seihou cannot prove the recorded edge came from the blueprint
  installed now. Re-run it, which is safe by design because edge prompts inspect
  real usage before changing anything and a completed edge finds nothing to do,
  or skip it deliberately by raising `--from`. Nothing is deleted from the
  manifest and no conversion command is needed; `seihou manifest upgrade` is
  unaffected.

  See [What a receipt means](blueprint-migrations.md#which-edge-a-receipt-is-for).

## [0.6.0.0] - 2026-07-28

### Added

- **`seihou manifest upgrade` converts a manifest written by an older seihou.**
  Manifests before schema version 6 recorded, for each applied module, the
  absolute directory it occupied on the machine that ran the command. Seihou no
  longer reads those, and every command says so:

  ```text
  [error] Error reading manifest: this manifest uses schema version 5, which
  records machine-specific absolute paths; run 'seihou manifest upgrade' to
  convert it
  ```

  The new command replaces each recorded path with a portable origin — the git
  URL the module was installed from, or a path relative to the project root for
  a module living inside the project — and prints every conversion, because
  recovering a URL from somebody else's absolute path is inference and
  inference does not belong hidden inside a committed file:

  ```text
  Reading .seihou/manifest.json (schema version 5)

    haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                    →  remote https://github.com/shinzui/seihou-modules.git

    project-lint       /Users/shinzui/work/myproject/.seihou/modules/project-lint
                    →  project .seihou/modules/project-lint

  ✓ Upgraded .seihou/manifest.json to schema version 6.
    Review the diff and commit it: git diff .seihou/manifest.json
  ```

  `--dry-run` shows the same report and writes nothing. Running it on a
  manifest that is already current reports that there is nothing to do and
  exits zero, so it is safe in a script.

  Because the conversion can only record what this machine can see, the command
  refuses to write when an artifact the manifest names is missing or stale
  locally — that would commit a guess and lose the upstream for everyone. It
  names what to install or upgrade first; `--force` writes anyway. Everything
  it does is undone by `git checkout -- .seihou/manifest.json`, and the write
  is atomic.

  See [Upgrading an Older Manifest](manifest-upgrade.md), or
  `seihou help manifest`.

- **Seihou refuses to silently downgrade a project.** If your copy of a module
  is older than the version `.seihou/manifest.json` records, `seihou run` and
  `seihou migrate` now stop before writing anything:

  ```text
  ✗ Refusing to run: your local copy of 'haskell-base' is older than the
    version this project expects.

    Recorded in .seihou/manifest.json:  2.0.0
    Installed on this machine:          1.4.0
    Origin: https://github.com/shinzui/seihou-modules.git

    Update your local copy first:
      seihou upgrade haskell-base

  To proceed anyway — pinning this project to what is installed here —
  re-run with --allow-downgrade.
  ```

  This is the failure a shared manifest makes easy: a teammate upgrades a
  module, runs seihou, and commits; you pull, still have the old copy, run
  seihou, and every generated file quietly reverts — looking like an ordinary
  diff in code review. The refusal happens before the plan is computed, so the
  project is byte-identical afterwards and a refusal costs you nothing. Nothing
  is fetched over the network; seihou tells you what to run.

  The same check catches an *origin mismatch* — a module with the right name
  installed from a different git repository than the manifest records is a
  different module, and seihou says so rather than generating from it.

  Pass `--allow-downgrade` to `run`, `migrate`, or `update` when pinning back is
  deliberate. The command proceeds, but still prints what it is overriding under
  a `! Proceeding anyway` heading. A module found in your personal
  `~/.config/seihou/modules/` has no recorded provenance; its version is still
  compared, but its identity is reported as unverifiable rather than blocked.

  `seihou status` now lists every artifact that differs from what the project
  records, so you find out before a command refuses. It always exits zero.

- **Call tracing for agent commands.** Seihou can now record what each model
  call actually did — which provider and model ran, how long it took, how many
  tokens it used, and what it cost:

  ```sh
  seihou config set agent.trace file
  seihou agent assist "add a health check module"
  cat .seihou/trace.jsonl
  ```

  ```text
  {"kind":"call_started","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:11Z","provider":"anthropic","model":"claude-sonnet-4-6","maxTokens":8192,"promptSummary":"add a health check module"}
  {"kind":"call_finished","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:19Z","provider":"anthropic","model":"claude-sonnet-4-6","latencyMs":7913,"inputTokens":4211,"outputTokens":880,"usd":0.0264}
  ```

  The file is JSON Lines, one object per line, so ordinary tools answer the
  questions you actually have — `jq -s 'map(select(.kind == "call_finished") |
  .usd) | add' .seihou/trace.jsonl` totals what a project has cost you.

  `agent.trace` takes `off`, `file`, `stdout`, or `stderr`, and resolves through
  the same precedence chain as `provider`, `model`, and `effort`: a `--trace`
  flag, `SEIHOU_AGENT_TRACE`, then `agent.<command>.trace` and `agent.trace` in
  local then global config. Use `--trace stderr` to watch a single run without
  leaving a file behind; trace lines go to stderr precisely so they never
  corrupt assistant output you are piping. The file destination is
  `.seihou/trace.jsonl`, changeable with `agent.tracePath`.

  **Tracing is off by default and stays out of your way** — with `agent.trace`
  unset, nothing is written, nothing extra is printed, and no file is created.

  Two limits worth knowing. Interactive `claude`/`codex` sessions are not
  traced: they are spawned subprocesses, not requests Seihou can time or price,
  so tracing covers batch runs (`--batch`, or automatically when stdin is not a
  terminal) and the API providers. And the subscription-based CLI providers do
  not report tokens or cost, so their events carry latency only — use
  `anthropic` or `openai` for cost accounting.

  See [Tracing model calls](agent-assistance.md#tracing-model-calls).

- **Blueprint- and prompt-declared agent settings.** A blueprint or agent
  prompt can now declare the agent it was written for, in its own Dhall file:

  ```dhall
  , launch = Some S.Launch::{
    , provider = Some "claude-cli"
    , model = Some "claude-opus-4-8"
    , effort = Some "max"
    }
  ```

  This matters when a prompt only works well with a particular provider, or
  genuinely needs deep reasoning: rather than hoping whoever runs it has the
  right settings configured, the author states them once. Declared values
  **override every config-file tier** — project-local and global, per-command
  keys included — but **lose to anything you state for a single invocation**: a
  `--provider` / `--model` / `--effort` flag, or a `SEIHOU_AGENT_*` environment
  variable. Precedence is per field, so a `--model` flag replaces only the model
  while a declared `effort` still applies.

  Honored by `seihou agent run`, `seihou agent migrate`, and `seihou prompt
  run`. Add `--verbose` to see what resolved and where each value came from
  (`[blueprint: launch.effort]`, `[flag on subcommand]`, and so on). A
  declaration naming an unknown provider or effort is reported by `seihou
  validate-blueprint` / `seihou validate-prompt` and refuses the run instead of
  silently falling back. `seihou agent config` lists the new tier in its
  precedence legend, and freshly scaffolded blueprints show the field as a
  commented example.

  `prompt.dhall` already accepted a `launch` record in earlier releases, but
  nothing read it; it is now honored, and gains an `effort` field. Existing
  blueprints and prompts are unaffected — the field is optional, and artifacts
  authored against an older schema pin still load. See
  [Blueprints](blueprints.md#launch-settings) and
  [Prompts](prompts.md#launch-settings).

### Changed

- **The manifest is now machine-independent, and manifests written by earlier
  versions must be upgraded before use.** This is a breaking change for existing
  projects; `seihou manifest upgrade` is the fix.

  `.seihou/manifest.json` used to record, for every applied module, the absolute
  directory that module occupied on the machine that ran the command —
  `/Users/shinzui/.config/seihou/installed/haskell-base`. Teams commit the
  manifest, and that path meant nothing in anybody else's clone: commands that
  re-read a module from it either failed or silently fell back to a different
  module than the manifest described.

  Schema version 6 replaces those paths with portable artifact origins. Every
  reference is now the git URL the artifact was installed from plus its name, a
  path relative to the project root for a module living inside the project, or a
  bare name when nothing recorded an upstream:

  ```json
  "origin": {
    "kind": "remote",
    "url": "https://github.com/shinzui/seihou-modules.git",
    "artifact": "haskell-base",
    "repo": "seihou-modules"
  }
  ```

  Two developers who apply the same module now produce the same bytes, so a
  manifest diff in review shows a real change rather than a change of laptop.
  Every command resolves the recorded origin against the local machine's search
  paths, and when the artifact is not installed it says so by name, with the
  `seihou install` command that fixes it, instead of failing somewhere inside a
  Dhall evaluation.

  Manifests at schema version 5 or earlier no longer load. Every command reports
  this and names the remedy; run `seihou manifest upgrade` once, review the
  printed conversions, and commit the result.

  New guide: [Sharing a Seihou Project Across a Team](teams.md) — what to
  commit, what each developer needs installed, and what happens when someone is
  out of date.

### Fixed

- **Provider errors on the `anthropic` and `openai` providers are reported
  properly.** A failing API call — a missing or invalid key, a rate limit, an
  unknown model — was reported as `Error: Provider returned no assistant text.`,
  which told you nothing about what went wrong. It now names the actual failure:

  ```text
  $ seihou agent run my-blueprint --provider anthropic
  Error: BaikaiError {category = AuthError, message = "env var ANTHROPIC_API_KEY is not set", ...}
  ```

- **Reasoning effort now reaches non-interactive agent runs.** Effort was
  applied to interactive Claude Code and Codex sessions but silently dropped
  whenever Seihou took the batch path — `claude -p`, used when stdin is not a
  terminal, such as in CI or through a pipe. Configured, environment-set, and
  blueprint-declared effort now reach the agent in both modes. Requires Baikai
  0.4.1 / baikai-claude 0.4.

## [0.5.0.0] - 2026-07-20

### Added

- **Configurable reasoning effort.** Each agent command (and `seihou prompt
  run`) can now set the model's reasoning effort — how hard it thinks — with the
  same hierarchy as provider and model. Use `agent.effort` /
  `agent.<command>.effort` (levels `minimal`, `low`, `medium`, `high`, `xhigh`,
  `max`), `SEIHOU_AGENT_EFFORT`, or the `--effort LEVEL` flag. Effort flows to
  the local CLIs (`claude --effort` / `codex -c model_reasoning_effort`) and to
  the API providers, and appears as a new row in `seihou agent config`. Unset by
  default, so the CLI/provider picks its own. Requires Baikai 0.4. See
  [AI Agent Assistance](agent-assistance.md#reasoning-effort).

- **Ordered blueprint migrations.** Blueprint authors can declare versioned,
  agent-driven upgrade steps in `blueprint.dhall`, and users can run the exact
  requested window with `seihou agent migrate BLUEPRINT --from VERSION --to
  VERSION`. Seihou runs the declared edges inside that window in ascending order,
  tolerating undeclared gaps, skipping an edge that overlaps one already selected,
  and deferring an edge whose target overshoots the window; it writes a durable
  receipt after every successful step; resumes interrupted chains by default;
  and supports `--rerun` plus a side-effect-free `--debug` preview. See
  [Blueprint Migrations](blueprint-migrations.md) for the full workflow, plus
  [Blueprints](blueprints.md), [Migrations](migrations.md), and the
  [`agent migrate` reference](../cli/agent.md#agent-migrate).

- **Deterministic CLI provider defaults.** When no model is configured, the
  local CLI providers now pin a specific model instead of deferring to the
  ambient `claude` / `codex` session: `claude-cli` defaults to `claude-opus-4-8`
  and `codex-cli` defaults to `gpt-5.6-terra`. Seihou always passes the model
  explicitly, so an agent run never accidentally inherits a different model
  another session selected. Override with `--model` or an `agent.model` /
  `agent.<command>.model` config key.

- **Per-command agent provider and model.** Each agent command can now use a
  different provider and model through configuration. Set
  `agent.<command>.provider` / `agent.<command>.model` (for `assist`,
  `bootstrap`, `setup`, `run`, `migrate`, or `prompt-run`) to override the shared
  `agent.provider` / `agent.model` defaults for that command only. Resolution
  is hierarchical: a project's local config overrides the user's global config,
  and within a scope a per-command key overrides the shared default. The new
  read-only `seihou agent config` command prints the resolved provider and model
  for every command, labelling the source of each value. See
  [AI Agent Assistance](agent-assistance.md) and the
  [agent reference](../cli/agent.md).

- **Project-aware updates.** `seihou update` now stages candidate sources,
  reuses saved per-instance inputs, applies migrations, three-way merges user
  edits from content-addressed generated baselines, skips unchanged commands,
  and publishes cache/manifest state only after success. Human and JSON output,
  interactive conflict/orphan choices, dry-run, force policies, and optional
  Git commits are included. See [the update reference](../cli/update.md).

### Changed

- `seihou status` recommends one update per recorded application; `run` is
  described as initial application/reconfiguration, while `upgrade` is
  explicitly shared-cache-only maintenance.

## [0.4.0.0] - 2026-07-15

No entries were curated here for this release. Its user-visible changes —
agent prompts as a first-class artifact kind, `commandVars`, `seihou docs`
via the OKF extension, and the rest — are recorded in the
[engineering changelog](../../CHANGELOG.md#0400---2026-07-15). This section
exists so the version sequence is unbroken rather than to summarise them
after the fact.

## [0.3.0.0] - 2026-06-12

### Added

- **Blueprints — agent-driven scaffolding.** A new runnable artifact kind for
  open-ended project shapes: Seihou applies a deterministic baseline, then hands
  the project to a configured AI provider. Author with `seihou new-blueprint`,
  check with `seihou validate-blueprint`, and run with `seihou agent run
  BLUEPRINT`. Blueprints are installable from registries, and `seihou status`
  records which blueprint was applied. See
  [Blueprints](blueprints.md).
- **AI provider integration.** Agent commands (`seihou agent`,
  `seihou prompt run`) now route through a configurable provider —
  `claude-cli`, `codex-cli`, `anthropic`, or `openai`. See
  [AI Agent Assistance](agent-assistance.md).
- **`seihou kit`** installs Claude Code and Codex skills and subagents.
- **`seihou list` kind filters:** `--modules`, `--recipes`, and
  `--blueprints` narrow output by artifact kind, and the summary count is
  kind-aware.

### Changed

- **More robust migrations.** The migration planner is now a gap-tolerant
  window walker, so migration chains with version gaps apply reliably. See
  [Migrations](migrations.md).

### Removed

- **Breaking:** the `seihou migrate --bump-only` and `seihou run
  --bump-blocked` recovery flags were removed — the rewritten migration planner
  advances through benign version gaps automatically, so the manual escape
  hatches are no longer needed.

### Fixed

- `seihou migrate` no longer crashes when a chain mixes a file move with a
  `RunCommand` step that removes the source's parent directory.
- Manifests are written atomically (write-to-temp-then-rename), avoiding
  corruption if the process is interrupted mid-write.
- Malformed or cyclic recipes now surface as structured errors instead of
  crashing.
- Generation, migration, and removal paths are constrained to stay within the
  project tree.

### Packaging

- First public [Hackage](https://hackage.haskell.org/) release preparation:
  BSD-3-Clause licensing and complete package metadata, with the CLI's embedded
  help topics and agent prompt templates packaged into source distributions.

## [0.2.0.0] - 2026-04-29

### Added

- **Module migrations.** Modules can declare file-system operations
  (`MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, `RunCommand`) that move a
  project across module versions. `seihou migrate` applies the chain, rewrites
  the manifest, and bumps the recorded version; `seihou run` and `seihou
  status` are migration-aware. See [Migrations](migrations.md).
- **Recipes.** Named, ordered compositions of modules with optional pre-bound
  parameters. Author with `seihou new-recipe`; recipes are first-class in
  `run`, `list`, `install`, and `browse`.
- **Registry tooling.** The `seihou registry` command group (`sync-versions`,
  `validate`) keeps a multi-module repository's `seihou-registry.dhall` in sync
  with its artifacts, with CI-friendly `--check` and non-zero exit on drift.
- **Inline template conditionals.** `{{#if cond}} … {{/if}}` blocks in the
  Template strategy, with unbounded nesting. See
  [Templating](templating.md).
- **`seihou run --confirm-defaults`** steps through each defaulted or
  export-derived variable so you can accept or override it interactively.
- **`seihou status --check-updates`** surfaces available registry updates
  alongside status output.
- **Parameterized-dependency multi-instantiation:** a parent can instantiate
  the same dependency several times with different parameter sets.

### Changed

- `seihou migrate` fetches the latest module before planning, so no manual
  `seihou upgrade` is needed first (`--no-fetch` opts out).

## [0.1.0.0] - 2026-04-15

Initial public release of Seihou — a composable, type-safe project scaffolding
system driven by Dhall modules, with stateful manifests and incremental
regeneration.

### Added

- **Core pipeline:** Dhall module loading and validation, layered variable
  resolution with `--explain`, four generation strategies (`Copy`, `Template`,
  `DhallText`, `Structured`) plus text patching, composition with declared
  dependencies and topological ordering, and plan compilation with shell-command
  hooks.
- **Manifest tracking:** a stateful `.seihou/manifest.json`, a three-state diff
  engine (manifest / plan / disk), interactive conflict resolution, and
  reversible module removal.
- **Module system:** required module versions, `seihou outdated` / `seihou
  upgrade`, schema evolution, and `seihou schema-upgrade`.
- **CLI:** `init`, `run`, `vars`, `install`, `browse`, `list`, `status`,
  `diff`, `validate-module`, `new-module`, `config`, `context`, `remove`,
  agent workflows, and embedded help topics.
- **Registries:** multi-module registry support with discovery and validation.
- **Developer experience:** Bash/Zsh/Fish completions, FZF selection, and a
  `--verbose` flag wired throughout.

---

[0.8.0.0]: https://github.com/shinzui/seihou/compare/v0.7.0.0...v0.8.0.0
[0.7.0.0]: https://github.com/shinzui/seihou/compare/v0.6.0.0...v0.7.0.0
[0.6.0.0]: https://github.com/shinzui/seihou/compare/v0.5.0.0...v0.6.0.0
[0.5.0.0]: https://github.com/shinzui/seihou/compare/v0.4.0.0...v0.5.0.0
[0.4.0.0]: https://github.com/shinzui/seihou/compare/v0.3.0.0...v0.4.0.0
[0.3.0.0]: https://github.com/shinzui/seihou/compare/v0.2.0.0...v0.3.0.0
[0.2.0.0]: https://github.com/shinzui/seihou/compare/v0.1.0.0...v0.2.0.0
[0.1.0.0]: https://github.com/shinzui/seihou/releases/tag/v0.1.0.0
