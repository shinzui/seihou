# Bundle Update Log

## 2026-10-28
* **Update**: IR-9 is completed by ExecPlan 116: run and update publish command receipts before the command phase and withdraw or roll them back on failure; ADR 0023 records the decision.
* **Update**: IR-9 is accepted and planned in docs/plans/116-record-command-receipts-before-module-commands-can-commit-the-manifest.md, which chooses option A: seihou run and seihou update publish the receipt set a successful command phase will produce before the first command runs, withdraw it when the phase fails or is interrupted, and update snapshots the manifest in a version-5 transaction journal so rollback and crash recovery restore it. No schema change; git-init and the recipes that end with it need no edits. Implementation remains pending.
* **Update**: Completed IR-11 via EP-114, IR-12 via EP-113 and IR-13 via EP-115 in Seihou 0.12.0.1. All three source packages and API docs are published; the tagged Nix build passes all 2134 tests and the installed CLI at f529a7a passes cross-registry install/run, terminal/replay, representative-consumer and descriptor-validation acceptance. TAN producer publication remains downstream work.
* **Update**: Linked IR-11, IR-12 and IR-13 to ExecPlans 114, 113 and 115 respectively; source implementations are complete and coordinated release verification is in progress.
* **Update**: Linked IR-12 to ExecPlan 113 for source declarations, dependency closure installation, origin-safe resolution, and released consumer verification; the plan links back to IR-12. Implementation remains pending.
* **Addition**: IR-11 requests recipe-level variable and prompt resolution before module defaults; IR-12 requests declared cross-registry dependency sources and ordinary installation of their closure, extending existing BUG-2; IR-13 requests a recipe authoring validator. All were found while planning the TAN Keiro recipe against installed Seihou 0.11.0.1; the user will fix upstream before TAN implementation.

## 2026-10-15
* **Update**: IR-10 is completed by ExecPlan 105: typed schema-9 directory-link declarations, manifest-only sync with dry-run/JSON and no artifact/config/command/manifest writes, bounded status, shared ownership and safe run/update/remove reconciliation. Real clone tests pass for agent and editor/shared-asset consumers, empty/newer caches, linked worktrees, repair, same-run sources, no-spec removal and rollback; core effect/recovery checks pass. Validation ran on macOS; Linux execution and producer adoption remain downstream verification/release work.
* **Update**: IR-6 is accepted and linked to [ExecPlan 106](../plans/106-supply-default-initial-instructions-to-cli-agent-providers.md). The four-milestone plan supplies one shared default initial instruction for missing/blank CLI prompts at batch and interactive launch boundaries, preserves explicit user prompts and API behavior, exposes the effective migration instruction in debug output, and proves execution with fake providers. Generated defaults stay out of user-authored manifest provenance. Implementation remains pending.
* **Update**: Audited all ten requests against checked-in ExecPlan progress, outcomes, and current source. IR-1 through IR-4 remain completed with their existing target plans (84, 81, 83, and 82 respectively). IR-2 and IR-4 now also have clickable ExecPlan and MasterPlan links in their Status sections. IR-7 and IR-8 are corrected from accepted to completed, with completion times and resolution evidence from plans 91 and 90; IR-8 also links the implemented schema-7 and certification follow-ups in plans 92–94 and 97. IR-10 remains accepted with implementation pending, and now carries the missing targetPlan field for plan 105. IR-5, IR-6, and IR-9 remain proposed with no implementation plan found; their Status sections record the outstanding behavior and distinguish existing related plans from a plan to fulfill the request. IR-6's original claude -p failure is historical because CLI migrations now launch interactively, but omitted prompts still receive no default instruction. This audit inspected source and existing validation evidence; it did not launch live providers or rerun implementation test suites.
* **Update**: IR-10 is accepted and planned in docs/plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md after PR \#1 was validated, updated, and merged. Six milestones cover declarations, versioned manifest ownership, checked link operations, sync/status, command integration, and fresh-clone acceptance. Plans 99 and 100 supply prerequisite lifecycle/schema foundations. Implementation remains pending.
* **Update**: IR-10 was renumbered from the PR’s colliding IR-9 using okf id next; the existing receipt-ordering IR-9 is unchanged. Current-source validation confirms the rebuild gap, corrects claude-gitignore, distinguishes historical evidence from current behavior, and requires tracked-path, containment, collision, and schema-evolution checks.

## 2026-10-02
* **Addition**: IR-9 requests that module command receipts reach `.seihou/manifest.json` before a
module's own commands can commit or push it. `seihou run` and `seihou update` write receipts only
after the whole command phase, so `git-init`'s initial commit and `gh repo create --push` capture a
manifest with no receipts. The tree is dirty right after the run, and a clone's later update treats
those commands as never run. Because every receipt's `completedAt` is the run's `now`, the
final receipt set is known up front. Records two options without choosing: write the expected receipts
first and roll back on failure, or add a final command phase that runs after the receipt write.

## 2026-09-28
* **Addition**: IR-10 requests a checkout-local output lifetime and a command that rebuilds those outputs in a fresh clone. `link-skill` links skills into gitignored `.claude/skills` and `.agents/skills` with shell commands whose receipts are committed, so `planCommands` skips them in every clone, and the only built-in way to re-run them (`update --run-all-commands`) also upgrades artifacts. Observed in a fresh clone of `mori://shinzui/keiro`, where that route meant three module upgrades, three migrations, and a generated `flake.lock`. The preferred shape is a declarative symlink step with `lifecycle = Some "checkout"` (extending MasterPlan 12), observed on disk rather than receipted (ADR 0004), plus a manifest-only rebuild command. A Justfile-recipe module in `mori://shinzui/agent-seihou` is recorded as a stopgap.

## 2026-09-16
* **Update**: IR-7 is implemented. truncateReason and reasonWidth are hoisted out of formatBlueprintMigrations' where clause into a module-level truncateForSummary that the receipt reason and the blueprint Prompt line now share; the prompt is collapsed to one line and bounded at 72 characters while the reason keeps 60. .seihou/manifest.json is untouched - userPrompt still holds the whole prompt and seihou status writes nothing. The optional escape hatch ships as seihou status --full-prompt rather than the suggested --full, because status renders six blocks and bounds one value so a bare --full does not say which; -u and -v are both taken on this command and its siblings. ADR 0013 records the underlying rule.
* **Update**: IR-8 is accepted and planned in docs/plans/90-exempt-additive-patch-paths-from-the-shared-ownership-closure.md. The plan persists the per-path write mode in the manifest as a single boolean FileRecord.additiveOnly (option (a), fail-closed when absent, no schema version bump), checks the exemption in two layers — the CLI preflight against the manifest and reconciliation against the candidate's own operations — and sequences two fail-open defects the closure had been masking ahead of the gate change: prepareCandidateManifest must union surviving owners into the rewritten record instead of replacing them, and may only carry additiveOnly forward when the prior record agreed. Part 2 lands as seihou update <target> --include-shared-owners, expanding to a fixed point and reporting each application it adds.
* **Addition**: IR-8 requests that a targeted `seihou update` stop failing on a shared path whose every
owner writes it with an additive, idempotent patch. `ensureOwnershipClosure` in
`Update/Selection.hs` (mirrored in `Reconcile.hs`) classifies any co-owned path as a whole-file
conflict, but `append-line-if-absent` and `append-section` owners occupy disjoint, commutative slices
that cannot clobber one another. Observed against `mori://shinzui/pgmq-hs`, whose `.gitignore` is
co-owned by `nix-haskell-flake` (append-line-if-absent) and `master-plan`, so `seihou update nix-haskell-flake` refuses. Part 1 asks to exempt the additive, non-overlapping patch strategies from
the closure requirement — noting `FileRecord` records only a single `strategy`/`moduleName` and no
`PatchOp`, so the exemption needs per-owner write mode recorded in the manifest (preferred) or the
owners' steps re-resolved at update time, failing closed on unknown. Part 2 asks for an explicit
`--include-shared-owners` opt-in that expands a named selection to its ownership closure for the paths
where the requirement legitimately still holds, keeping the plan 66/68/69 rule that a bare selection
is never silently broadened.

## 2026-09-14
* **Addition**: IR-7 requests that `seihou status` stop printing the stored blueprint prompt in
full. `blueprintSection` in `StatusRender.hs` emits `userPrompt` verbatim with no length bound, so
a multi-paragraph positional prompt dominates the summary and pushes the actual status off screen.
Observed against `mori://shinzui/kotei`, whose `fix-nix-haskell-flake-customizations` blueprint
carries a long upgrade prompt. `formatBlueprintMigrations` in the same file already truncates a
long migration reason to a scannable line while the manifest keeps the whole of it; IR-7 asks that
the prompt line get the same discipline (collapse whitespace, cut with a trailing `…`), leaving the
manifest untouched, with an optional verbose flag to show it in full.

## 2026-08-17
* **Addition**: IR-6 requests that `seihou agent migrate` work without a trailing PROMPT on the
default claude-cli provider. `claude -p` requires a user message, seihou sends only a system prompt,
and `initialPrompt` is typed and documented as optional — so the invocation every worked example
shows fails on the first edge of every chain, and the error blames the provider. Observed running
keiro-upgrade against mori. The surrounding fail-closed behaviour was correct: no receipt, no source
touched, resumable. Asks for a default instruction, a required argument, or a per-provider fallback.
* **Addition**: IR-5 requests that a blueprint author be able to verify an entailed edge resolves
from the source consumers install from. Observed at the keiro 0.13.0.0 release: an entailment was
correct and the entailed blueprint declared exactly the named edge, but its commit was unpushed, so
every consumer's run would have refused. `validate-blueprint` passes correctly because the question
is not a property of the blueprint being validated, and `--debug migrate` passes because it
resolves the author's own machine — so the preview's reassurance is strongest where it is least
warranted. Asks for resolved-blueprint provenance in the preview, and an opt-in mode that resolves
entailments against their recorded remote.

## 2026-08-16
* **update**: IR-1 is implemented. A blueprint migration receipt now carries an outcome; an edge reports inapplicability through a signal file (interactive providers) or a trailing SEIHOU: not-applicable line (API providers), the chain continues past it, and only an applied receipt suppresses a later run. A dedicated exit code was rejected because an interactive session's exit code is the shell's.
* **Update**: IR-3 is implemented. seihou agent run and seihou agent migrate now consult ManifestGuard before doing any work and refuse a stale or substituted artifact, with a --allow-downgrade override. The blanket --debug exemption applies to agent migrate only, because agent run --debug still applies the baseline and records provenance. ADR 0003 was amended to cover the agent path.
* **Update**: IR-4 is implemented. seihou install classifies the existing installation before removing it and refuses a different-source or unprovenanced overwrite; --force overrides and prints what it overrode. Namespacing the cache by repository stays rejected, now recorded in ADR 0006.
* **Update**: IR-2 is implemented. AppliedBlueprint, AppliedBlueprintMigration, and AppliedRecipe now carry an ArtifactOrigin, the blueprint migration completion key includes it, and a record written without one decodes as unverifiable provenance rather than failing.

## 2026-08-06
* **Addition**: IR-2 requests an `ArtifactOrigin` on `AppliedBlueprint`, `AppliedBlueprintMigration`,
and `AppliedRecipe`, so agent-path provenance is the identity ADR 0002 accepts rather than the
bare name it rejects, and so a migration receipt cannot suppress a different blueprint's edge.
* **Addition**: IR-3 requests that `seihou agent run` and `seihou agent migrate` consult
`ManifestGuard`, extending the ADR 0003 refusal to the one path that applies baselines and writes
receipts without it.
* **Addition**: IR-4 requests that `seihou install` read the origin metadata it is about to delete
and refuse a different-source overwrite, since the install cache is keyed by bare name and a
registry entry has no rename escape hatch.

## 2026-07-31
* **Addition**: IR-1 requests a not-applicable outcome for blueprint migration edges, so an edge
that correctly declines an unmet precondition is not recorded as a completed upgrade and then
silently skipped on the run that should have applied it.
