---
id: 34
slug: blueprint-docs-and-ecosystem
title: "Documentation, Agent-Prompt Updates, and Ecosystem Polish for Blueprints"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Documentation, Agent-Prompt Updates, and Ecosystem Polish for Blueprints

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

This is the closing plan in the agent-driven-blueprints initiative. By the time
this plan starts, EP-29 through EP-33 have shipped: a third runnable type
called **Blueprint** exists alongside modules and recipes, has a Dhall
schema, a discovery hook, authoring (`seihou new-blueprint`,
`seihou validate-blueprint`) and inspection (`seihou list`, `seihou vars`)
surfaces, an agent runner (`seihou agent run BLUEPRINT [PROMPT]`), a
manifest entry (`AppliedBlueprint`) surfaced by `seihou status`, and full
multi-module-repository support (`seihou-registry.dhall`'s
`blueprints` field, `seihou install`, `seihou browse`, `seihou registry
sync-versions`, `seihou registry validate`). What is missing is the
durable design record, the architectural map readers consult to find
their way around the codebase, the prompts that teach existing
AI-assisted commands (`seihou agent assist`, `bootstrap`, `setup`) that
blueprints exist, and a single user-facing CHANGELOG entry that summarises
the whole initiative.

After this plan ships, a contributor opening
`docs/dev/design/proposed/blueprints.md` finds a rei-style design doc
that explains, in their own terms, why blueprints exist, what shape they
take in Haskell, what the validator enforces, how the runner orchestrates
agent launches, what the manifest records, and how registry support
treats blueprints. A contributor opening
`docs/dev/architecture/overview.md` finds the **Module Loading**
pipeline-stage paragraph mentioning blueprint discovery, the
**Project Structure** tree listing the new files, and the
**Trapped-modules inventory** updated to cover the new exec-target
modules. A user looking for "what is new" opens `docs/user/CHANGELOG.md`
and finds a top-level summary entry naming the new commands and
behaviours. An AI agent running `seihou agent assist`, `bootstrap`, or
`setup` reads its prompt and now knows that blueprints are a third
authoring/consumption surface, knows when to recommend each kind, and
correctly directs the user to `seihou agent run` for blueprints rather
than `seihou run`.

You can prove the work is done by reading the design doc end-to-end and
verifying that every code path it names exists at the path it names; by
running `tree seihou-core/src/Seihou/Core seihou-cli/src-exe/Seihou/CLI
seihou-cli/data schema 2>/dev/null` and confirming each new entry from
the Project Structure section matches a real file; by running
`seihou agent assist --debug` (and the same for `bootstrap` and `setup`)
and grepping the rendered prompt output for "blueprint"; and by
rendering `docs/user/CHANGELOG.md` in any Markdown viewer and confirming
the new top entry summarises the initiative.


## Progress

- [ ] Read EP-29 through EP-33 in their final, merged form to confirm what shipped (file paths, command names, manifest fields, registry shape).
- [ ] Sanity-check that the dependencies are merged: run `git log --oneline | grep -E "(blueprint|EP-29|EP-30|EP-31|EP-32|EP-33)"` and confirm merges for each.
- [ ] Milestone 1: write `docs/dev/design/proposed/blueprints.md` (rei-style; full sections enumerated under Concrete Steps).
- [ ] Milestone 2: edit `docs/dev/architecture/overview.md` (Module Loading paragraph; Project Structure tree; Trapped-modules inventory; Cross-References list).
- [ ] Milestone 2 sub-task: verify the Trapped-modules inventory matches the actual `other-modules` list in `seihou-cli/seihou-cli.cabal` after EP-30 and EP-31 land.
- [ ] Milestone 3: edit `seihou-cli/data/assist-prompt.md`, `bootstrap-prompt.md`, `setup-prompt.md` per the inserts listed under Concrete Steps.
- [ ] Milestone 3 sub-task: audit each new command's `Info` block in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` (`newBlueprintInfo`, `validateBlueprintInfo`, `agentRunInfo`, the registry blueprints branches) and the `agentInfo` umbrella for consistency, examples, and stale phrasing.
- [ ] Milestone 3 sub-task: append the unified CHANGELOG summary entry to `docs/user/CHANGELOG.md` at the top of the Changelog section.
- [ ] Run validation suite: `nix flake check`, `cabal build all`, `seihou agent assist --debug | grep -i blueprint`, `seihou agent bootstrap --debug | grep -i blueprint`, `seihou agent setup --debug | grep -i blueprint`.
- [ ] Final commit and update of the Outcomes & Retrospective section.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: ship a single design doc at
  `docs/dev/design/proposed/blueprints.md` rather than splitting
  authoring, runner, manifest, and registry into separate docs.
  Rationale: the existing proposed-design docs are organised by *concept*
  (`module-system.md`, `composition-and-layering.md`,
  `manifest-and-incrementality.md`), not by code path. Blueprints are a
  single concept with internal sections for each surface; splitting it
  across four files would force readers to chase cross-references for
  what is, conceptually, one thing. The doc is sectioned so a reader
  interested only in "how does the runner work" can jump to **Runner
  Workflow** without reading the rest. Date: 2026-05-07.

- Decision: do update the user-facing README. Rationale: the README's
  feature list currently names "modules" and "recipes" as the two
  authorable artifacts. Leaving blueprints out of the README would
  make the most discoverable surface of the project lie about its
  capabilities. The README edit is a single sentence and a single
  bullet; the change is included in Milestone 3 with the CHANGELOG
  entry. Date: 2026-05-07.

- Decision: the Trapped-modules inventory edits are a milestone-2
  sub-task rather than a separate milestone. Rationale: the inventory
  is a *table* in the architecture overview, not a separate file. It
  is mechanically derived from the executable's `other-modules` list
  and the trapping import in each module. Coupling it to the
  architecture-overview edit keeps the diff legible. Date: 2026-05-07.

- Decision: the CHANGELOG summary entry is *additive* — the per-plan
  entries that EP-29 through EP-33 each added remain in place. The
  EP-34 entry is the introductory paragraph a user reads first; the
  per-plan entries are the technical detail. Rationale: this matches
  the existing pattern in `docs/user/CHANGELOG.md` where major
  initiatives (e.g., the migrations DX initiative) carry a top-level
  framing paragraph alongside the per-EP technical entries. Date:
  2026-05-07.

- Decision: the agent-prompt edits are deliberately terse. Rationale:
  the existing prompts are already long, and the kind of decision the
  three agents need to make on the user's behalf — module vs recipe
  vs blueprint — is a small decision tree with three leaves. A
  bullet-and-cue list outperforms paragraphs of explanation here.
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The seihou repository is a multi-package Cabal workspace at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. The two relevant
packages are `seihou-core` (the library: domain types, validation,
discovery) and `seihou-cli` (the CLI binary). After EP-29 through EP-33,
the codebase contains three runnable artifact kinds. **Modules**
(`module.dhall`) are deterministic: every input is captured by a
`VarDecl` and every output is a function of the resolved variables.
**Recipes** (`recipe.dhall`) are named compositions of modules with
pre-bound variables; they expand to module sequences before plan
compilation. **Blueprints** (`blueprint.dhall`) are non-deterministic
artifacts authored for AI coding agents to consume; they bundle a
prompt, an optional baseline of modules, and an optional `files/`
directory of reference snippets. Both modules and recipes are run via
`seihou run`; blueprints are run via `seihou agent run BLUEPRINT
[PROMPT]` because their effect on disk is decided by an AI agent at
runtime.

The doc you are writing lives under `docs/dev/design/proposed/`
alongside the existing concept docs. The closest stylistic precedent is
`docs/dev/design/proposed/module-system.md`, which uses the
**rei-style** format: a header table (Status, Created, Updated,
Subsystem), an Overview paragraph, a Motivation paragraph, a
Design Decisions table, a Domain Model section with Haskell type
definitions, body sections for the concept's behaviours, an Edge Cases
section, a Testing Plan section, and Future Enhancements. Use that
shape verbatim; readers familiar with one rei-style doc should find
this one immediately legible.

The architecture overview at `docs/dev/architecture/overview.md` is
the wayfinding document. It opens with an Execution Pipeline diagram
(in an indented `text` block), describes each pipeline stage in prose,
lists the effect stack, lays out a Project Structure tree, documents
the **CLI Module Placement Convention**, and closes with a
Trapped-modules inventory table and a Cross-References list. Your
edits are surgical: one paragraph in **Module Loading**, three new
lines in the Project Structure tree (one per new file), four new rows
in the Trapped-modules inventory, and one new line in the
Cross-References list pointing at the new design doc.

The three agent prompts live at
`seihou-cli/data/{assist,bootstrap,setup}-prompt.md` and are embedded
into the executable via `Data.FileEmbed` from
`seihou-cli/src-exe/Seihou/CLI/{Assist,Bootstrap,Setup}.hs`. After
EP-31 ships, a fourth prompt at `seihou-cli/data/blueprint-prompt.md`
is also embedded, but that file is owned by EP-31; you do not edit it
here. You only edit the three sibling prompts so the existing agents
mention blueprints alongside modules and recipes.

Before you start, run these commands at the repository root to confirm
the dependencies have shipped:

    git log --oneline --all | grep -E "(EP-29|EP-30|EP-31|EP-32|EP-33|blueprint)" | head -20
    test -f seihou-core/src/Seihou/Core/Blueprint.hs && echo "EP-29 ok"
    test -f seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs && echo "EP-30 new ok"
    test -f seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs && echo "EP-30 validate ok"
    test -f seihou-cli/src-exe/Seihou/CLI/AgentRun.hs && echo "EP-31 ok"
    test -f seihou-cli/data/blueprint-prompt.md && echo "EP-31 prompt ok"
    grep -l "AppliedBlueprint" seihou-core/src/Seihou/Core/Types.hs && echo "EP-32 type ok"
    grep -l "blueprints" seihou-core/src/Seihou/Core/Registry.hs && echo "EP-33 ok"

If any of those checks fail, stop and resolve before continuing — the
plan presupposes the dependent code is in place. The masterplan at
`docs/masterplans/3-agent-driven-blueprints.md` lists each EP's
milestones; cross-reference to confirm a missing artefact is genuinely
missing rather than renamed.


## Plan of Work

The work decomposes into three milestones, executed in order. Each
milestone produces a self-contained, reviewable diff.

**Milestone 1: the design doc.** The deliverable is a new file at
`docs/dev/design/proposed/blueprints.md` matching the rei-style format
used by the other proposed-design docs. The doc contains every section
listed under Concrete Steps; substantial drafts of Overview, Motivation,
and Design Decisions are provided in this plan so the implementer can
copy-paste with light editing. The remaining sections (Domain Model,
Validation Rules, Runner Workflow, Manifest Behaviour, Registry
Integration, Edge Cases, Testing Plan, Future Enhancements) are
populated by reading the relevant code paths named in Concrete Steps
and rendering what is there into prose. After this milestone, a reader
can answer the questions "what is a blueprint?", "what does the
validator enforce?", "what does the runner do, in order?", "what does
the manifest record?", and "how does a multi-module repo expose
blueprints?" without reading any code.

Acceptance: `find docs/dev/design/proposed -name 'blueprints.md'`
returns the new file; rendering it in a Markdown viewer shows the
header table, the section headings in the order specified, and no
broken in-doc anchor links; a `grep -F` for each full file path named
in the doc returns at least one hit on disk (the doc must reference
real code paths, not aspirational ones).

**Milestone 2: the architecture overview.** The deliverable is an edit
to `docs/dev/architecture/overview.md` that adds blueprints to the
**Module Loading** pipeline-stage paragraph, adds three lines to the
Project Structure tree, adds four rows to the Trapped-modules
inventory, and adds one line to the Cross-References list. After this
milestone, a contributor reading the overview top-to-bottom learns
that blueprints exist, sees where the relevant files live, and finds
a link to the new design doc.

Acceptance: `git diff docs/dev/architecture/overview.md` shows
exactly the four edit regions named under Concrete Steps, with no
unrelated changes; `nix/check-cli-module-placement.sh` (run by
`nix flake check`) succeeds — the inventory rows match the actual
cabal `other-modules` list.

**Milestone 3: agent prompts and CHANGELOG.** The deliverable is
edits to `seihou-cli/data/{assist,bootstrap,setup}-prompt.md` plus an
appended top-of-section entry in `docs/user/CHANGELOG.md` and a
single-sentence README update. After this milestone, running
`seihou agent assist --debug`, `seihou agent bootstrap --debug`, and
`seihou agent setup --debug` (the existing flag that prints the
resolved prompt instead of launching Claude) each emits prompt text
that mentions blueprints; a user reading the CHANGELOG finds a top
entry summarising the initiative; the README's feature list names
all three runnable kinds.

Acceptance: `seihou agent {assist,bootstrap,setup} --debug 2>&1 |
grep -ic blueprint` returns a non-zero count for each of the three
subcommands; `head -30 docs/user/CHANGELOG.md` shows the new entry;
`grep -i blueprint README.md` returns at least one hit.


## Concrete Steps

### Milestone 1 — write `docs/dev/design/proposed/blueprints.md`

Create the file with the following structure, in order. Every heading
named below uses Markdown level 2 (`##`) unless noted. The header
table at the top uses the same shape as `module-system.md`.

**Header.**

    # Blueprints

    | Field | Value |
    |---|---|
    | **Status** | Implemented |
    | **Created** | 2026-05-07 |
    | **Updated** | 2026-05-07 |
    | **Subsystem** | Core — Runnable Artifacts |

**Overview.** Substantial draft (use as-is, edit lightly):

> A blueprint is the third runnable artifact kind in Seihou,
> alongside modules and recipes. Where a module is a deterministic
> generator (typed inputs in, exact files out) and a recipe is a
> named composition of modules with pre-bound variables, a blueprint
> is a *non-deterministic* artifact authored for an AI coding agent
> to consume. It bundles a prompt template, an optional baseline of
> modules to apply before the agent takes over, and an optional
> `files/` directory of reference snippets the agent may copy or
> adapt. Blueprints are not directly runnable: `seihou run
> my-blueprint` refuses with an actionable message and the user runs
> `seihou agent run my-blueprint [PROMPT]` instead, which optionally
> applies the baseline and then launches a Claude Code session
> pre-loaded with the rendered prompt.

**Motivation.** Substantial draft (use as-is, edit lightly):

> The deterministic shape works beautifully for project shapes that
> vary along small, well-understood axes (project name, license,
> list of GHC extensions, Nix system tuple, etc.). It fits poorly
> for project shapes whose variation is inherently open-ended:
> "scaffold a microservice for $domain", "set up a CI pipeline that
> mirrors $existingProject's conventions", "wire in observability
> that matches our team's $existingPattern". Encoding all the
> relevant axes as typed `VarDecl`s produces modules with dozens of
> optional variables, brittle template matrices, and far too many
> `{{#if}}` branches; a human author rapidly hits the limit of what
> is reasonable to enumerate ahead of time. Blueprints are the
> escape hatch: an author writes a prompt that explains the
> conventions, lists the baseline modules to apply for a known-good
> starting point, and ships reference files; the AI agent then
> drives the open-ended customisation under the user's
> supervision. The deterministic surface (modules and recipes)
> stays uncluttered.

**Design Decisions** (table, mirroring `module-system.md`):

| Decision | Choice | Rationale |
|---|---|---|
| Naming | "Blueprint" / `blueprint.dhall` / `RunnableBlueprint` | Connotes "a base plan an agent customises" without overloading existing terminology. |
| Namespace | Shared with modules and recipes (`[a-z][a-z0-9-]*`) | A single `discoverRunnable` lookup resolves all three kinds; cross-kind name collisions are validated at registry-validation time. |
| Run command | `seihou agent run BLUEPRINT` | Co-locates with the existing `seihou agent` namespace; `seihou run BLUEPRINT` refuses with an actionable message. |
| Baseline application | Default on; `--no-baseline` skips | Authors declare base modules so the agent starts from a validated scaffold; `--no-baseline` is a power-user override. |
| Migrations | Not supported | Blueprint output is non-deterministic; the manifest's `files` map cannot be authoritatively rewritten by an author-supplied chain. |
| Resume support | Deferred to a future plan | The v1 manifest entry records *that* a blueprint was applied with version and timestamp, but not the conversation contents. |

**Domain Model.** Reproduce the Haskell types from
`seihou-core/src/Seihou/Core/Types.hs` (the `Blueprint` record, the
`BlueprintFile` helper, the `RunnableBlueprint` constructor on
`Runnable`, the `KindBlueprint` constructor on `RunnableKind`) and
the `AppliedBlueprint` record from EP-32. Show each type as a
Haskell code block (four-space indented). Cross-reference every
type definition by full file path and approximate line range — a
reader should be able to jump straight to the source.

**Validation Rules.** List each rule the EP-29 validator enforces.
Read `seihou-core/src/Seihou/Core/Blueprint.hs` and render every
`Left` branch into prose: name format (`[a-z][a-z0-9-]*`), prompt
non-empty, base-module references resolve at discovery time,
declared `files/` references each exist on disk relative to the
blueprint root, `vars` and the prompt's `{{var}}` placeholders are
consistent, base modules are *modules* (not other blueprints), no
`migrations` field. For each rule, name the user-facing error
message verbatim.

**Runner Workflow.** Document, in order, what
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`'s `handleAgentRun` does:
discover the blueprint via `Seihou.Core.Module.discoverRunnable`,
validate via `Seihou.Core.Blueprint.validateBlueprint`, resolve
variables through the same precedence chain `seihou run` uses
(CLI → env → local → namespace → context → global → defaults →
interactive prompts; reference
`docs/dev/design/proposed/variable-resolution.md`), optionally apply
each declared base module via the same plan/execute path that
`seihou run` uses (skip if `--no-baseline`), render the blueprint's
prompt template via the same `substitute` helper used by the other
agent prompts (in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`), embed
the rendered prompt into the system-prompt scaffold at
`seihou-cli/data/blueprint-prompt.md`, and finally invoke
`launchAgentWith` (in `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`)
with the blueprint's `files/` mounted via `--add-dir` and the
blueprint's `allowedTools` (or the documented default) passed as
`--allowedTools`. Close with the manifest write — invoked into the
EP-32 helper, with the writer's exact module path and function name.

**Manifest Behaviour.** Document the EP-32 changes: the
`AppliedBlueprint` record, its position in `Manifest`, the
`currentManifestVersion` bump, the JSON encoder/decoder shape, the
backwards-compatibility branch that decodes pre-bump manifests with
`blueprint = Nothing`, and how `seihou status` displays the entry.
Reference `seihou-core/src/Seihou/Manifest/Types.hs` and
`seihou-cli/src-exe/Seihou/CLI/Status.hs` by full file path.

**Registry Integration.** Document the EP-33 changes: `Registry`
gains `blueprints :: [RegistryEntry]`, the Dhall registry schema
gains a parallel `blueprints` list, `discoverRepoContents` gains a
`SingleBlueprint FilePath` constructor, `seihou install` learns the
new constructor and the registry-listed-blueprint case,
`seihou browse` displays blueprints, and the `seihou registry
sync-versions` and `seihou registry validate` subcommands walk the
new list. Reference `seihou-core/src/Seihou/Core/Registry.hs`,
`seihou-cli/src-exe/Seihou/CLI/Install.hs`, `Browse.hs`, and the
registry-handler modules under `seihou-cli/src/Seihou/CLI/Registry/`
by full file path.

**Edge Cases.** Enumerate at least: a blueprint whose
`baseModules` references a name that resolves to another blueprint
(rejected at validation); a blueprint applied while a previous
`AppliedBlueprint` entry already exists in the manifest (the new
entry replaces the old; the user is warned); a blueprint with an
empty `files/` directory (allowed; runner does not pass `--add-dir`);
`seihou run BLUEPRINT` against a discoverable blueprint (refusal
message); a blueprint applied with `--no-baseline` against a
project whose existing manifest contains the would-have-been-applied
base modules (manifest is unchanged; the manifest's `AppliedBlueprint`
records the actual choice).

**Testing Plan.** Name the test files and what each covers. After
EP-29 through EP-33, expect tests under `seihou-core/test/` covering
the validator, the discovery extension, the manifest decoder bump,
and the registry classifier; tests under `seihou-cli/test/` covering
the CLI parsers and the prompt-substitution path. The Testing Plan
section enumerates these by file and links them to the rules they
exercise. If a rule has no test, the section says so explicitly
(this is a documentation finding for the implementer; it does not
require new test code in EP-34).

**Future Enhancements.** List the deferred items from the masterplan
verbatim: blueprint resume sessions; blueprints depending on other
blueprints; author-declared migrations on blueprints; non-Claude
agent backends; prompt templating that pulls from base modules'
resolved values.

**Cross-References.** Link to:
`docs/masterplans/3-agent-driven-blueprints.md`,
`docs/plans/29-blueprint-domain-model-and-discovery.md`,
`docs/plans/30-blueprint-authoring-and-inspection.md`,
`docs/plans/31-blueprint-agent-runner.md`,
`docs/plans/32-blueprint-manifest-and-status.md`,
`docs/plans/33-blueprint-registry-and-install.md`,
`docs/dev/design/proposed/module-system.md`,
`docs/dev/design/proposed/composition-and-layering.md`,
`docs/dev/design/proposed/variable-resolution.md`,
`docs/dev/design/proposed/manifest-and-incrementality.md`,
`docs/dev/architecture/overview.md`.


### Milestone 2 — edit `docs/dev/architecture/overview.md`

The file is currently 370 lines. Make four surgical edits.

**Edit 1: Module Loading paragraph (around line 66).** The current
text reads "If the name resolves to a recipe (`recipe.dhall`), it is
expanded into its constituent modules before entering the
composition pipeline." Append: "If the name resolves to a blueprint
(`blueprint.dhall`), the loader hands control to `seihou agent run`
rather than the deterministic pipeline; the blueprint is not
plan-compiled (see [Blueprints](../design/proposed/blueprints.md))."

**Edit 2: Project Structure tree (around lines 113–207).** Add three
lines, each at the right alphabetical position within its directory:

In the `seihou-core/src/Seihou/Core/` block, after the existing
`Recipe.hs` line, add:

    │           │   ├── Blueprint.hs   # Blueprint validation, discovery (validateBlueprint, discoverBlueprint)

In the `seihou-cli/src-exe/Seihou/CLI/` block (which is also where
`NewModule.hs`, `NewRecipe.hs`, `Validate.hs`, etc. live — note that
in the current overview the seihou-cli path is shown under
`seihou-cli/src/`; EP-19 / EP-21 split this into
`seihou-cli/src/` (library) and `seihou-cli/src-exe/` (executable).
Confirm by inspecting the on-disk layout first; if the overview
still shows the old single-path layout, also update the directory
header to reflect the split. Place the three new entries:

    │           │   ├── NewBlueprint.hs      # seihou new-blueprint handler
    │           │   ├── ValidateBlueprint.hs # seihou validate-blueprint handler
    │           │   ├── AgentRun.hs          # seihou agent run handler

In the `seihou-cli/data/` block (add the block if absent), list:

    │   ├── data/
    │   │   ├── assist-prompt.md
    │   │   ├── bootstrap-prompt.md
    │   │   ├── setup-prompt.md
    │   │   └── blueprint-prompt.md

In a top-level `schema/` block (add if absent), list:

    └── schema/
        ├── package.dhall
        ├── Module.dhall
        ├── Recipe.dhall
        └── Blueprint.dhall

Verify each path by `ls`-ing the directory before committing the
edit. If a directory listed above does not exist on disk, your
dependency check earlier in this plan failed; resolve the dependency
gap before writing the tree.

**Edit 3: Trapped-modules inventory (around lines 271–299).** The
table currently lists 28 modules. After EP-30 and EP-31, add four
new rows — the implementer must read the post-EP cabal file to
confirm the exact module list, but the expected additions are:

| Module | Trapping reason |
|---|---|
| `Seihou.CLI.AgentRun` | `Data.FileEmbed` for the embedded `blueprint-prompt.md` template |
| `Seihou.CLI.NewBlueprint` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.ValidateBlueprint` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Blueprint.Common` | Imports `Seihou.CLI.Commands` (transitively trapped) — *only if EP-30/EP-31 introduced this; otherwise drop* |

Run `grep -E "^[[:space:]]+Seihou\.CLI" seihou-cli/seihou-cli.cabal`
inside the `executable seihou` block to confirm the actual list
before committing. Sort the new rows alphabetically into the table
to match the existing convention.

**Edit 4: Cross-References list (around lines 363–369).** Add a new
bullet:

    - [Blueprints](../design/proposed/blueprints.md) — Agent-driven runnable type, runner workflow, manifest behaviour

Place it after the [Module System] bullet so the three runnable-type
docs (modules, composition, blueprints) cluster.

After all four edits, run `nix flake check` and confirm the
`check-cli-module-placement.sh` script passes — the script is wired
to fail if the inventory drifts from the cabal file.


### Milestone 3 — agent prompts, CHANGELOG, README, CLI help audit

**3a: edit `seihou-cli/data/assist-prompt.md`.** After the
`### module.dhall format` section ends and before the next `###`
heading, insert a new subsection. Exact text to insert (the prompt
files are user-facing — the implementer can wordsmith but should not
shrink the decision tree):

    ### Blueprints (third runnable kind)

    Some authoring requests are too open-ended for a typed module
    (dozens of `{{#if}}` branches, a templating combinatoric
    explosion). Those belong in a *blueprint* — an authoring artifact
    that bundles a Markdown prompt, an optional list of base modules
    to apply, and an optional `files/` directory of reference
    snippets. A blueprint runs via `seihou agent run NAME`, not
    `seihou run`.

    Use a blueprint when:
    - the variation axes are inherently open-ended ("scaffold a
      microservice for $domain")
    - a prose prompt is the right interface for a coding agent

    Use a module when:
    - all variation is enumerable as `VarDecl`s
    - the output is deterministic given those variables

    To scaffold one: `seihou new-blueprint NAME` writes
    `blueprint.dhall`, `prompt.md`, and `files/`. Validate with
    `seihou validate-blueprint .`.

In the `## Seihou CLI Commands` section, append two new bullets to
the existing list:

    - `seihou new-blueprint NAME [--path DIR]` — scaffold a new blueprint
    - `seihou validate-blueprint [PATH]` — validate blueprint.dhall

**3b: edit `seihou-cli/data/bootstrap-prompt.md`.** Replace the
beginning of the **Bootstrap Workflow** section (currently step 1,
"Gather requirements") with a kind-decision step ahead of it. Insert
this new step 1 (renumbering existing steps):

    1. **Choose the kind.** Three artifact kinds are available:
       - **Module** when all variation is enumerable as typed
         variables and the output is a deterministic function of
         those variables (deterministic-axes-known). Most
         scaffolding requests fit here.
       - **Recipe** when the user wants a static composition of
         existing modules with pre-bound variables — no new
         generation logic, just a named bundle. Use when the user
         already has the modules and wants a one-name handle to
         apply them all.
       - **Blueprint** when the variation is open-ended and a
         coding agent should drive the customisation
         (open-ended-with-baseline). Use when listing the user's
         requirements would produce dozens of variables and
         conditional steps.

       Decision tree: if you can list the inputs as typed variables,
       it's a module. If you're composing existing modules without
       new logic, it's a recipe. If you'd be writing a prose prompt
       to explain conventions to the user, it's a blueprint.

In the `## Seihou CLI Commands` section, append the same two bullets
as in 3a (`seihou new-blueprint`, `seihou validate-blueprint`), plus
a third:

    - `seihou agent run BLUEPRINT [PROMPT]` — run a blueprint (launches Claude with the blueprint's prompt)

After the existing **Registry Format** section, append a short
paragraph noting that registries can list blueprints:

    A registry can also list blueprints alongside modules:

        , blueprints =
          [ { name = "payments-service"
            , version = Some "0.1.0"
            , path = "blueprints/payments-service"
            , description = Some "Microservice scaffold (agent-driven)"
            , tags = [ "service", "haskell" ]
            }
          ]

    `seihou install`, `seihou browse`, and `seihou registry
    sync-versions` all handle blueprint entries.

**3c: edit `seihou-cli/data/setup-prompt.md`.** In the **Consumption
Workflow** section, insert a new step ahead of the existing step 1
(**Discover**). The new step explains the discovery-time fork:

    1. **Recognise the kind.** Some discoverable runnables are
       blueprints, not modules or recipes. `seihou list` distinguishes
       them with a kind label. A module or recipe runs via `seihou
       run NAME`. A blueprint runs via `seihou agent run NAME
       [PROMPT]` — `seihou run NAME` against a blueprint refuses
       with an actionable message. If the user names a runnable that
       turns out to be a blueprint, switch to the agent-run flow:
       resolve the variables the blueprint declares (the standard
       precedence chain applies), optionally let the baseline modules
       apply, then launch.

(Existing steps 1–8 renumber to 2–9; update the cross-references in
the same section accordingly.)

In the `### Generation` subsection of `## Seihou CLI Commands`,
append:

    - `seihou agent run BLUEPRINT [PROMPT] [--var K=V] [--no-baseline]` — run a blueprint
      - Discovers the blueprint, resolves variables (same precedence chain as `seihou run`), optionally applies base modules, then launches Claude Code with the rendered prompt and the blueprint's `files/` mounted as a read-only reference
      - `--no-baseline`: skip applying declared base modules
      - `--debug`: print the resolved prompt instead of launching

**3d: README update.** The user-facing README at the repository root
lists the project's authorable artifacts. Find the sentence that
names "modules" and "recipes" and add "blueprints" to the
enumeration. Add a one-line bullet near the feature list:

    - **Blueprints** (`seihou agent run BLUEPRINT`) — agent-driven scaffolding for open-ended project shapes (see `docs/dev/design/proposed/blueprints.md`).

If the README does not yet enumerate a feature list (it may be
sparse), add a single sentence under the project description:
"Three authorable artifact kinds are supported: deterministic
*modules*, named compositions called *recipes*, and agent-driven
*blueprints*."

**3e: CLI help-text audit.** Read each of these `*Info` blocks in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` and verify they share a
consistent voice and example shape with the existing
`agentBootstrapInfo`, `runInfo`, and `installInfo` blocks (which are
the longest-running stable patterns):

- `newBlueprintInfo` (added by EP-30)
- `validateBlueprintInfo` (added by EP-30)
- `agentRunInfo` (added by EP-31; under the `agent` subparser)
- The `agentInfo` umbrella (currently lines 1150–1174); confirm the
  "Available subcommands" list now includes `run` alongside
  `assist`, `bootstrap`, `setup`
- The `installInfo`, `browseInfo`, `syncVersionsInfo`, and
  `validateRegistryInfo` blocks — EP-33 should have updated their
  footers to mention blueprints; verify
- The `listInfo` and `varsInfo` blocks — EP-30 should have updated
  these to acknowledge the new kind; verify

For each block found inconsistent (missing `Examples:` block,
missing a blueprint-specific example where one would help, stale
phrasing referring only to "modules and recipes"), fix it in this
plan. Keep edits minimal — the audit goal is consistency, not
rewriting working text.

**3f: CHANGELOG entry.** Append a new top-level entry in
`docs/user/CHANGELOG.md`, placed at the top of the `## Changelog`
section (above the existing `### 2026-04-28` entry). Format mirrors
the existing entries. Exact wording (date the implementer fills in
on the day they ship):

    ### YYYY-MM-DD (Blueprints: agent-driven scaffolding for open-ended project shapes)

    **Reviewed commits:** ExecPlans 29–34
    (`docs/plans/29-blueprint-domain-model-and-discovery.md`,
    `docs/plans/30-blueprint-authoring-and-inspection.md`,
    `docs/plans/31-blueprint-agent-runner.md`,
    `docs/plans/32-blueprint-manifest-and-status.md`,
    `docs/plans/33-blueprint-registry-and-install.md`,
    `docs/plans/34-blueprint-docs-and-ecosystem.md`) — the
    agent-driven-blueprints initiative.

    **Behaviour change (user-facing):**

    - A new third runnable kind, the **blueprint**
      (`blueprint.dhall`), joins modules and recipes. Blueprints
      bundle a prompt template, an optional baseline of modules to
      apply before the agent takes over, and an optional `files/`
      directory of reference snippets.
    - Authoring: `seihou new-blueprint NAME [--path DIR]` scaffolds
      a blueprint; `seihou validate-blueprint [PATH]` validates one.
    - Running: `seihou agent run BLUEPRINT [PROMPT]` resolves the
      blueprint's variables, optionally applies the baseline
      (`--no-baseline` skips), renders the prompt, and launches an
      interactive Claude Code session with the blueprint's `files/`
      mounted as a read-only reference.
    - `seihou run BLUEPRINT` refuses with an actionable message
      directing the user to `seihou agent run`. Blueprints are not
      directly runnable by design.
    - `seihou status` records `Scaffolded from blueprint: <name>
      <version> on <date>` when a blueprint has been applied.
    - `seihou list`, `seihou vars`, `seihou install`, `seihou
      browse`, `seihou registry sync-versions`, and `seihou registry
      validate` all understand the new kind. A `seihou-registry.dhall`
      can list blueprints alongside modules.

    **Why:**

    Modules and recipes are deterministic by design — every input
    captured by a `VarDecl`, every output a function of resolved
    variables. That shape works for project shapes that vary along
    small, well-understood axes; it fits poorly for shapes whose
    variation is inherently open-ended ("scaffold a microservice
    for $domain", "wire in observability that matches our team's
    pattern"). Blueprints are the escape hatch: an author writes a
    prompt, the AI agent drives the open-ended customisation under
    the user's supervision, and the deterministic surface stays
    uncluttered.

    **Docs updated:**

    - `docs/dev/design/proposed/blueprints.md` — new design doc
      describing the runnable type, validation, runner workflow,
      manifest behaviour, and registry integration.
    - `docs/dev/architecture/overview.md` — Module Loading paragraph
      mentions blueprint discovery; Project Structure tree adds the
      new files; Trapped-modules inventory adds the new exec-target
      modules.
    - `seihou-cli/data/{assist,bootstrap,setup}-prompt.md` — the
      three AI-assisted commands now know blueprints exist and route
      users to `seihou agent run`.
    - `README.md` — feature list names all three runnable kinds.

After appending, update the **Last Reviewed Commit** marker at the
top of the file to point at the EP-34 merge commit (the implementer
fills in the SHA after committing).


## Validation and Acceptance

Run each of the following from the repository root and confirm the
documented outcome.

**Design doc renders.** Open
`docs/dev/design/proposed/blueprints.md` in a Markdown viewer (e.g.,
`glow` or `bat -l md`). The header table renders, every section
heading appears in the order given in Concrete Steps M1, no anchor
links 404. Run:

    grep -n "^## " docs/dev/design/proposed/blueprints.md

The output must show, in order: Overview, Motivation, Design
Decisions, Domain Model, Validation Rules, Runner Workflow, Manifest
Behaviour, Registry Integration, Edge Cases, Testing Plan, Future
Enhancements, Cross-References.

**Cross-references resolve.** For each full file path mentioned in
the design doc, confirm it exists:

    grep -oE 'seihou-(core|cli)/[a-zA-Z0-9./_-]+\.(hs|md|dhall)' docs/dev/design/proposed/blueprints.md \
      | sort -u | while read p; do test -e "$p" || echo "MISSING: $p"; done

The pipeline must produce no output. Any `MISSING:` line is a bug
in the doc.

**Architecture overview matches reality.** Verify the Project
Structure tree:

    for p in seihou-core/src/Seihou/Core/Blueprint.hs \
             seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs \
             seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs \
             seihou-cli/src-exe/Seihou/CLI/AgentRun.hs \
             seihou-cli/data/blueprint-prompt.md \
             schema/Blueprint.dhall; do
      test -e "$p" && echo "ok $p" || echo "MISSING $p"
    done

Every line must be `ok`.

Verify the Trapped-modules inventory matches the cabal file:

    grep -E "Seihou\.CLI" seihou-cli/seihou-cli.cabal | sort -u > /tmp/cabal-mods.txt
    grep -oE "Seihou\.CLI\.[A-Za-z.]+" docs/dev/architecture/overview.md | sort -u > /tmp/doc-mods.txt
    diff /tmp/cabal-mods.txt /tmp/doc-mods.txt

The diff should be empty (modulo modules that are exempted). Run
`nix flake check` and confirm `check-cli-module-placement.sh` is
green; that script is the authoritative arbiter.

**Agent prompts mention blueprints.** Run each of:

    seihou agent assist --debug 2>&1 | grep -ic blueprint
    seihou agent bootstrap --debug 2>&1 | grep -ic blueprint
    seihou agent setup --debug 2>&1 | grep -ic blueprint

Each must return at least 2 — the prompt body uses the word
"blueprint" multiple times.

**CHANGELOG entry visible.**

    head -50 docs/user/CHANGELOG.md | grep -F "Blueprints: agent-driven"

Returns one line.

**README enumerates three kinds.**

    grep -ic blueprint README.md

Returns at least 1.

**Build is clean.** Run `cabal build all` and `nix flake check` and
confirm both succeed. Documentation changes alone should not break
the build, but the inventory check and any cabal-formatter check
will fail if Milestone 2 misaligned with reality.


## Idempotence and Recovery

Each milestone is independently re-runnable. If you have already
written `docs/dev/design/proposed/blueprints.md` and need to revise
it, edit in place — no other artefact references its line numbers.
The architecture-overview edits are inserts at named anchor points
(section headings, table boundaries); re-applying the inserts twice
produces visible duplication, so before re-running the milestone
inspect the file with `grep -n "Blueprint" docs/dev/architecture/overview.md`
and back out any duplicate inserts manually.

The agent-prompt files are loaded at compile time via
`Data.FileEmbed`. After editing them, the `seihou` binary must be
rebuilt for the new prompts to take effect. Run `cabal build all`
between editing a prompt and running `seihou agent assist --debug`
to confirm the change.

The CHANGELOG entry is additive. If you accidentally append twice,
remove the duplicate by hand.

If the validation steps reveal a missing file referenced by the
design doc, the dependency check at the start of this plan failed —
the named EP did not actually ship that artefact, or shipped it at a
different path. Resolve by reading the relevant EP's
`Outcomes & Retrospective` section to find the actual path, then
update the design-doc reference.


## Interfaces and Dependencies

EP-34 hard-depends on EP-31 (`docs/plans/31-blueprint-agent-runner.md`)
and soft-depends on EP-30, EP-32, EP-33
(`docs/plans/{30,32,33}-*.md`). The reason: the design doc and
architecture overview describe shipped behaviour, not aspirational
behaviour. If the runner has not shipped, the design doc cannot
truthfully say "the runner does X"; if the manifest schema has not
shipped, the doc cannot describe `AppliedBlueprint`; if the registry
support has not shipped, the doc cannot describe registry
integration.

Sanity-check the dependencies have shipped before starting:

    git log --oneline --grep="EP-29" --grep="EP-30" --grep="EP-31" --grep="EP-32" --grep="EP-33" --all
    test -f seihou-core/src/Seihou/Core/Blueprint.hs            # EP-29
    test -f seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs       # EP-30
    test -f seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs  # EP-30
    test -f seihou-cli/src-exe/Seihou/CLI/AgentRun.hs           # EP-31
    test -f seihou-cli/data/blueprint-prompt.md                 # EP-31
    grep -q "AppliedBlueprint" seihou-core/src/Seihou/Core/Types.hs              # EP-32
    grep -q "blueprint = Nothing" seihou-core/src/Seihou/Manifest/Types.hs       # EP-32 (back-compat decode)
    grep -q "blueprints" seihou-core/src/Seihou/Core/Registry.hs                 # EP-33

Run all eight checks. If any fails, stop and pick up the
corresponding EP first; do not write documentation that names paths
which do not exist.

This plan does not introduce any new code, so it has no downstream
dependencies. Future plans (e.g., a hypothetical EP-35 adding
blueprint-resume support) extend the design doc EP-34 wrote, not
replace it.


---

*Revision note: initial draft. Future revisions to this plan must
update the Surprises & Discoveries, Decision Log, and Outcomes &
Retrospective sections per `.claude/skills/exec-plan/PLANS.md`'s
Revision Protocol.*
