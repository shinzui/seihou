---
id: 99
slug: declare-seed-steps-in-the-module-schema-and-validate-them
title: "Declare seed steps in the module schema and validate them"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
---

# Declare seed steps in the module schema and validate them

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-1 of the MasterPlan
`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`.
It has no hard dependencies.


## Purpose / Big Picture

A Seihou *module* is a directory with a `module.dhall` file that lists *steps*; each step
generates one file in the user's project. Today every generated file is *managed*: Seihou
records its content hash in `.seihou/manifest.json` and from then on reports every edit to it
as `modified by user`. Some files, such as a `CHANGELOG.md` or a `.cabal` file, are only a
starting point that the project is expected to edit immediately, and reporting them forever
as modified hides the drift that matters.

This plan gives module authors a way to say so. After it, a step may carry
`lifecycle = Some "seed"`. A *seed file* is a file a module creates once, when its path does
not exist yet, and then hands to the project: Seihou never overwrites it, never
content-tracks it, never merges into it, never reports it as modified, and never deletes it.
This plan delivers only the declaration: the Dhall schema field, the Haskell type, the
decoder, and `seihou validate-module` rules that reject nonsensical seed steps. Later plans
in the MasterPlan make `seihou run`, `status`, `diff`, `remove`, and `update` act on it. Until
they land, a seed step behaves exactly like a managed step, which is today's behavior.

To see it working after this plan: write a module whose step has
`lifecycle = Some "seed"`, run `seihou validate-module` on it, and see it pass; add
`patch = Some "append-file"` to the same step and see validation fail with a message naming
the step; write `lifecycle = Some "sede"` and see evaluation fail with a message listing the
accepted values.


## Progress

- [ ] Milestone 1: add `lifecycle` to `schema/Step.dhall`, document it in `schema/README.md`,
      type-check, commit and push in the submodule.
- [ ] Milestone 1: re-pin `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` and `flake.lock`.
- [ ] Milestone 2: add `StepLifecycle` and `Step.lifecycle` in `Seihou.Core.Types`; update
      every `Step` construction site.
- [ ] Milestone 2: decode `lifecycle` in `Seihou.Dhall.Eval.stepDecoder` with a default for
      older modules; force it in `evalModuleFromFile`; decoder tests.
- [ ] Milestone 3: add the "Seed steps" check to `Seihou.Engine.Validate.buildReport`; make
      `lintDuplicateDestinations` lifecycle-aware; tests.
- [ ] Milestone 4: write ADR 0017; document the field in `docs/user/module-authoring.md`;
      add a root `CHANGELOG.md` entry.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Declare the lifecycle as `lifecycle : Optional Text` with values `"managed"` and
  `"seed"`, defaulting to `None Text` (managed).
  Rationale: Matches the text-enumeration convention of `strategy` and `patch`, is optional
  so every existing module keeps working unchanged, and leaves room for future lifecycles.
  Date: 2026-09-19

- Decision: Decode a missing `lifecycle` key with `withDefaults`, not by requiring
  `seihou schema-upgrade` to insert it.
  Rationale: `Seihou.Dhall.Eval` already uses `withDefaults` for keys newer schemas added
  (`removal`, `migrations`, `entails`). Modules pinned to an older schema commit must keep
  evaluating with no edit. `Seihou.Core.SchemaUpgrade` inserts only fields the decoder
  requires (it inserts `patch`), so it needs no change.
  Date: 2026-09-19

- Decision: Allow seeds for `copy`, `template`, and `dhall-text`; reject `structured` seeds
  and seed steps that carry a `patch`.
  Rationale: A patch contributes to a file someone else writes, which contradicts "created
  once, then the project's". `structured` merges generated data into existing file content,
  which is also a form of continued management. Rejecting both keeps the concept small; they
  can be revisited if a real module needs them.
  Date: 2026-09-19

- Decision: Rejecting mixed lifecycles on one destination and removal steps on a seed
  destination are errors reported by a core check, not `--lint` warnings.
  Rationale: Both describe a module whose behavior would be incoherent at run time (is the
  path tracked or not? would `seihou remove` delete a file the project owns?), so they must
  fail validation by default, like "Safe step destinations".
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell (GHC 9.12, `GHC2024`) Cabal workspace with two packages:
`seihou-core/` (library `seihou-core`, all domain logic) and `seihou-cli/` (library
`seihou-cli-internal` in `seihou-cli/src/` and the `seihou` executable in
`seihou-cli/src-exe/`). Read the repository `CLAUDE.md` before editing: records use strict
fields, fields are read and set through `generic-lens` labels (`step ^. #dest`,
`x & #field .~ v`), never through record dot syntax or record update syntax, and each module
using `#label` imports `Data.Generics.Labels ()` itself. A check script
(`nix/check-record-conventions.sh`) enforces this.

*Dhall* is the configuration language modules are written in. The *schema package* is a
separate repository, `shinzui/seihou-schema` on GitHub, vendored in this repository as the git
submodule `schema/`. Module authors import it by URL and integrity hash
(`let S = https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall sha256:<hash>`)
and write steps with *record completion*, `S.Step::{ strategy = "template", src = "a.tpl", dest = "a" }`,
which fills omitted fields from the record's `default`. `schema/Step.dhall` today is:

```dhall
{ Type =
    { strategy : Text
    , src : Text
    , dest : Text
    , when : Optional Text
    , patch : Optional Text
    }
, default =
    { when = None Text
    , patch = None Text
    }
}
```

The procedure for changing the schema and re-pinning it is written down in
`.claude/skills/update-seihou-schema/SKILL.md`; follow it. In short: edit files in
`schema/`, type-check with `dhall type --file schema/package.dhall`, commit and push inside
the submodule (the submodule commit carries no `ExecPlan:` trailers), then in this repository
update `schemaUrl` and `schemaHash` in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` (used by
`seihou new-module` to emit the import line), run `nix flake update seihou-schema-src`, and
commit the submodule pointer, `SchemaVersion.hs`, and `flake.lock` together. Never rewrite a
pushed schema commit.

The Haskell side of a step is `Seihou.Core.Types.Step` in
`seihou-core/src/Seihou/Core/Types.hs` (around line 204):

```haskell
data Step = Step
  { strategy :: !Strategy,
    src :: !FilePath,
    dest :: !Text,
    condition :: !(Maybe Expr),
    patch :: !(Maybe PatchOp)
  }
  deriving stock (Eq, Show, Generic)
```

`Strategy` (around line 166) is `Copy | Template | DhallText | Structured`. `PatchOp`
(around line 176) is `AppendFile | PrependFile | AppendSection | AppendLineIfAbsent`.

Modules are decoded by `Seihou.Dhall.Eval` (`seihou-core/src/Seihou/Dhall/Eval.hs`).
`evalModuleFromFile` (around line 89) normalizes the file with `inputExprWithSettings` and then
runs `extract moduleDecoder expr`. It does **not** type-check against the decoder's expected
type, so record keys the decoder does not ask for are ignored; this is why an older Seihou
binary will simply ignore a `lifecycle` key and treat the step as managed. `stepDecoder`
(around line 677) reads `strategy`, `src`, `dest`, `when`, and `patch` with `field`. Unknown
text values are turned into Haskell `error` calls inside the decoder (see `strategyDecoder`
around line 556 and `parsePatchOp`), and `evalModuleFromFile` forces those fields with
`evaluate` inside its `try` block so the error becomes a `DhallEvalError` rather than a crash;
any new field decoded the same way must be forced there too. `withDefaults` (around line 154)
wraps a decoder so that a missing record key is filled with a Dhall expression before
extraction; `noneText` is the expression `None Text`. `moduleDecoder` uses it for `removal` and
`migrations`, and `blueprintMigrationDecoder` shows how to attach it to the decoder of a list
*element*, which is what `stepDecoder` needs.

`seihou validate-module` is implemented by `Seihou.Engine.Validate.buildReport`
(`seihou-core/src/Seihou/Engine/Validate.hs`, around line 62). It builds a list of `DiagCheck`
values (`label`, `severity` of `DiagError` or `DiagWarning`, and `details`, one text per
finding; an empty list means the check passed). Core checks always run; lint checks run with
`--lint`. `lintDuplicateDestinations` (around line 211) warns when two non-patch steps share a
`dest`. A module's optional removal specification is `Module.removal :: Maybe Removal`, where
`Removal` has `steps :: [RemovalStep]` and each `RemovalStep` has `action :: RemovalAction`,
`dest :: Text`, and `src :: Maybe FilePath` (around line 271 of `Types.hs`); one action deletes
the file at `dest`. Inspect `RemovalAction`'s constructors in `Types.hs` to identify the
file-deleting one (it corresponds to the Dhall value `"remove-file"`).

Tests use tasty with tasty-hspec. Relevant suites: `seihou-core/test/Seihou/Dhall/EvalSpec.hs`
(decoder tests against fixture modules in `seihou-core/test/fixtures/<name>/module.dhall`;
fixtures are written as plain Dhall records without the schema import, see
`seihou-core/test/fixtures/bad-strategy/module.dhall`) and
`seihou-core/test/Seihou/Engine/ValidateSpec.hs` (builds `Module` values in Haskell; its
`goodModule` is the starting point). There are about eighteen places in `seihou-core` and
`seihou-cli` (source and tests) that construct a `Step` with record syntax; find them with:

```bash
grep -rn 'Step$\|= Step\b\|Step {' seihou-core seihou-cli | grep -v RemovalStep
```

Relevant ADRs. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
(the manifest records all applied state) is why later plans record seed receipts; this plan
does not touch the manifest. [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
governs the wording of the new validation findings: name the step by its `dest` as the author
wrote it and never render a Haskell `show` value. No other ADR bears on the schema field. This
plan creates ADR 0017, the definition of a seed file that the rest of the MasterPlan
implements.


## Plan of Work

### Milestone 1 — the schema field

Scope: the Dhall schema can express a seed step, and this repository pins the schema commit
that can. At the end, `schema/Step.dhall` has the new field, the commit is pushed to
`shinzui/seihou-schema`, and `seihou new-module` emits an import of it.

Edit `schema/Step.dhall` to add `lifecycle : Optional Text` to `Type` and
`lifecycle = None Text` to `default`, and update the leading comment to explain the field in
one sentence ("`lifecycle` is `Some "managed"` (the default when omitted) or `Some "seed"`: a
seed step creates its file only when absent and then leaves it to the project"). In
`schema/README.md`, add a short "Seed steps" section after the existing sections showing the
`CHANGELOG.md` example from the MasterPlan's Vision & Scope and the one-paragraph definition
of a seed file. Type-check, prove the field is authorable with a scratch file (see Concrete
Steps), commit, and push in the submodule. Then re-pin in this repository exactly as the
update-seihou-schema skill describes and run `cabal build all`.

Acceptance: `dhall type --file schema/package.dhall` succeeds; the scratch module using
`lifecycle = Some "seed"` type-checks; `git -C schema status --branch --porcelain` shows the
submodule in sync with `origin/master`; `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` names the
new commit and hash.

### Milestone 2 — the Haskell type and decoder

Scope: every module evaluates to a `Step` that knows its lifecycle. At the end, a fixture with
a seed step decodes to `lifecycle = Seed`, a fixture without the key decodes to `Managed`, and
an unknown value fails evaluation with a message listing the accepted values.

In `seihou-core/src/Seihou/Core/Types.hs`, beside `Strategy`, add:

```haskell
-- | Whether a step's output stays under Seihou's management or is created
-- once and handed to the project. See
-- docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md.
data StepLifecycle
  = -- | Tracked in the manifest by content hash, updated, merged, and
    -- reported as modified. The default when a module omits the field.
    Managed
  | -- | Created only when the path is absent; never tracked, overwritten,
    -- merged, reported, or deleted afterwards.
    Seed
  deriving stock (Eq, Ord, Show, Generic)
```

and add `lifecycle :: !StepLifecycle` as the last field of `Step`. Export `StepLifecycle (..)`
wherever `Strategy (..)` is exported. Update every `Step` construction site found by the grep
above to pass `lifecycle = Managed` (tests included). Also add a small pure helper next to
`Step`, `lifecycleToText :: StepLifecycle -> Text` (`"managed"`, `"seed"`), for diagnostics.

In `seihou-core/src/Seihou/Dhall/Eval.hs`, wrap `stepDecoder` with
`withDefaults [("lifecycle", noneText)]` and read `field "lifecycle" (maybe strictText)`,
mapping `Nothing` and `Just "managed"` to `Managed`, `Just "seed"` to `Seed`, and any other
value to `error ("Unknown step lifecycle \"" <> T.unpack other <> "\"; expected one of: managed, seed")`,
following the `parsePatchOp` pattern. In `evalModuleFromFile`, extend the per-step forcing line
to also `evaluate (s ^. #lifecycle)`. Check whether `Seihou.Dhall.Eval` has other entry points
that decode steps (for example a module evaluated from an in-memory expression for
`seihou update` staging or for blueprint baselines); every path that forces step fields must
force `lifecycle` too. A grep for `#patch` in `Eval.hs` finds them.

Add three fixtures under `seihou-core/test/fixtures/`: `seed-step/module.dhall` (one template
step with `lifecycle = Some "seed"` and one without the key), `bad-lifecycle/module.dhall`
(a step with `lifecycle = Some "sede"`), each with the `files/` sources the steps name, written
in the same plain-record style as `bad-strategy`. Add cases to `EvalSpec.hs` asserting the
decoded lifecycles and that the bad value yields a `DhallEvalError` whose message contains
`sede` and `managed, seed`.

Acceptance: `cabal test seihou-core-test` passes, including the new cases; the existing
fixtures (which have no `lifecycle` key) still decode.

### Milestone 3 — validation rules

Scope: `seihou validate-module` rejects seed steps that the rest of the initiative will not
support. At the end, the report has a new core check labelled `Seed steps` with severity
`DiagError`, and `lintDuplicateDestinations` no longer double-reports what the new check
covers.

In `seihou-core/src/Seihou/Engine/Validate.hs` add `checkSeedSteps :: Module -> [Text]` and
insert `DiagCheck "Seed steps" DiagError (checkSeedSteps m)` into `coreChecks` after
`"Safe step destinations"`. It returns one finding per problem, naming the step by its
`dest` as written in `module.dhall`:

1. A `Seed` step with `patch = Just _`:
   `step writing '<dest>' is a seed but has a patch; a seed creates a whole file once and cannot patch one`.
2. A `Seed` step whose strategy is `Structured`:
   `step writing '<dest>' is a seed but uses the structured strategy; seeds support copy, template, and dhall-text`.
3. Two or more steps with the same `dest` text where at least one is `Seed` and at least one
   is `Managed`: `steps writing '<dest>' mix the seed and managed lifecycles; use one lifecycle per destination`.
   Compare `dest` texts literally (before variable substitution), as `lintDuplicateDestinations`
   does. Two seed steps with the same `dest` are allowed only if they have mutually exclusive
   `when` conditions in practice; do not try to prove that — leave that case to the existing
   duplicate-destination lint warning.
4. A removal step whose action deletes a file and whose `dest` equals a seed step's `dest`:
   `removal step deletes '<dest>', which a seed step creates; seihou never deletes seed files`.

Export `checkSeedSteps`. Add `ValidateSpec.hs` cases for each finding plus one asserting that a
module with a valid seed step (template, no patch) passes with no `Seed steps` findings.

Acceptance: `cabal test seihou-core-test` passes. Running the built binary against a scratch
module (see Concrete Steps) prints the check and exits non-zero only for the invalid variants.

### Milestone 4 — the ADR and the reference documentation

Scope: the concept is written down where future contributors and module authors will look.

Create `docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`, following
the format of the existing ADRs (title line `# ADR 0017 — …`, `Status: Accepted`, `Date`,
then Context, Decision, Consequences, Rejected Alternatives, References). The ADR corpus is a
plain filesystem convention (there is no OKF profile for `docs/adr`; `mori.dhall` declares
none), so number it by the next file number. Context: the `haskell-cli-app` status noise
described in the MasterPlan. Decision: the definition of a seed file; the `lifecycle` field
and its two values; the supported strategies and the patch/structured exclusions; that a
destination has one lifecycle; that Seihou never deletes a seed file; that an older binary
reads a seed as managed and that this is accepted rather than gated. State explicitly that the
manifest receipt (EP-2), `run` behavior (EP-3), reporting (EP-4), and `update` release (EP-5)
will amend this record, and reference the MasterPlan. Rejected alternatives: a boolean
field, a new strategy, a project-side ignore list.

In `docs/user/module-authoring.md`, under "Steps and strategies" → "Fields", add
`**lifecycle** (Optional Text)` with the accepted values, the one-paragraph definition, and a
pointer to ADR 0017; keep "when to choose a seed" guidance out (EP-6 writes it). Update the
example step record at the top of that section to show `lifecycle = None Text` alongside
`when` and `patch`. Add an `### Added` entry under `## [Unreleased]` in the root
`CHANGELOG.md` naming the field, `StepLifecycle`, and the `Seed steps` validation check.

Acceptance: the ADR exists and is linked from the MasterPlan's Integration Points; the docs
build is not affected (these are plain Markdown files).


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, inside the Nix dev shell
(`nix develop`) unless stated.

Milestone 1:

```bash
git -C schema fetch origin
git -C schema status --branch --porcelain      # expect: ## master...origin/master
# edit schema/Step.dhall and schema/README.md
dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"
cat > ./seed-step-scratch.dhall <<'DHALL'
let S = ./schema/package.dhall
in  S.Step::{ strategy = "template", src = "CHANGELOG.md.tpl", dest = "CHANGELOG.md", lifecycle = Some "seed" }
DHALL
dhall type --file ./seed-step-scratch.dhall && rm ./seed-step-scratch.dhall
git -C schema add Step.dhall README.md
git -C schema commit -m "feat(schema): add lifecycle to Step for seed files"
git -C schema push origin master
git -C schema rev-parse HEAD
dhall hash --file schema/package.dhall
# edit seihou-cli/src/Seihou/CLI/SchemaVersion.hs with the commit and hash above
nix flake update seihou-schema-src
cabal build all
```

Expected: the type-check prints the record type including `lifecycle : Optional Text`, and
`cabal build all` succeeds.

Milestones 2 and 3:

```bash
cabal build all
cabal test seihou-core-test
```

Manual check of the validator with the built binary:

```bash
mkdir -p "$TMPDIR/seed-demo/files" && cd "$TMPDIR/seed-demo"
printf '# Changelog\n' > files/CHANGELOG.md.tpl
cat > module.dhall <<'DHALL'
{ name = "seed-demo", version = Some "0.1.0", description = None Text
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [ { strategy = "template", src = "CHANGELOG.md.tpl", dest = "CHANGELOG.md", when = None Text, patch = Some "append-file", lifecycle = Some "seed" } ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List Text
}
DHALL
cabal run -v0 seihou -- validate-module .
```

(Adjust the empty-list type annotations to match the current schema if evaluation complains;
`seihou-core/test/fixtures/bad-strategy/module.dhall` is the reference.) Expected output
contains a failed `Seed steps` check with the text
`step writing 'CHANGELOG.md' is a seed but has a patch`, and the exit status is non-zero.
Changing `patch` to `None Text` makes the check pass.


## Validation and Acceptance

`cabal test seihou-core-test` and `cabal test seihou-cli-test` pass. The new `EvalSpec` cases
fail before Milestone 2 (the decoder ignores the key) and pass after. The new `ValidateSpec`
cases fail before Milestone 3 and pass after. `nix flake check` passes, which also proves the
submodule pointer, `flake.lock`, and `SchemaVersion.hs` agree, and that the record-convention
and CLI-module-placement checks accept the new code. The manual `validate-module` transcript
above shows the new finding.


## Idempotence and Recovery

Every edit is additive and can be re-applied. If the schema commit was made but not pushed,
`git -C schema reset --hard origin/master` discards it. If it was pushed and is wrong, fix
forward with a new schema commit and re-pin; never force-push a published schema commit,
because module files in the wild pin it by hash. The Haskell changes compile only once every
`Step` construction site passes `lifecycle`; the compiler lists any that were missed.


## Interfaces and Dependencies

At the end of this plan these exist:

- `schema/Step.dhall`: `lifecycle : Optional Text`, default `None Text`, pushed to
  `shinzui/seihou-schema` and pinned in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`.
- `Seihou.Core.Types.StepLifecycle` with constructors `Managed` and `Seed`, and
  `Seihou.Core.Types.lifecycleToText :: StepLifecycle -> Text`.
- `Seihou.Core.Types.Step` with the additional strict field `lifecycle :: !StepLifecycle`.
- `Seihou.Dhall.Eval.stepDecoder` decoding the field, defaulting to `Managed` when absent.
- `Seihou.Engine.Validate.checkSeedSteps :: Module -> [Text]`, wired into `buildReport` as the
  core check `Seed steps`.
- `docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`.

Later plans consume `Step.lifecycle` (EP-3 compiles it into an operation, EP-5 reuses that)
and amend ADR 0017. No new library dependency is introduced.
