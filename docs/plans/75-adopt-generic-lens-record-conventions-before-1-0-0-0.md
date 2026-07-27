---
id: 75
slug: adopt-generic-lens-record-conventions-before-1-0-0-0
title: "Adopt generic-lens record conventions before 1.0.0.0"
kind: exec-plan
created_at: 2026-07-27T17:49:55Z
---

# Adopt generic-lens record conventions before 1.0.0.0

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou is about to be released as version 1.0.0.0. All three packages currently sit at
`0.5.0.0`. A 1.0 release is a promise that the code inside is the code we intend to
maintain, so the internal conventions should be the ones the project actually wants
before that promise is made rather than after.

The project has a house style for how Haskell records are defined and manipulated. That
style is written down outside this repository, and this plan restates it in full below so
that no external document is needed to carry out the work. Seihou does not currently
follow it. Instead of accessing record fields through `generic-lens` overloaded labels
(`config ^. #environment`), seihou accesses them through GHC's `OverloadedRecordDot`
extension (`config.environment`). Instead of updating records through lens setters
(`state & #status .~ Active`), seihou updates them through Haskell's record update syntax
(`state { status = Active }`). Almost every record field is lazy where the house style
requires strict fields. Seventy-nine record types have no `Generic` instance at all, which
is the prerequisite for overloaded-label access. Roughly two dozen record types still carry
per-type field name prefixes (`cwLocal`, `fzfBinary`, `depModule`, `drName`) that the house
style forbids. And `seihou-core/src/Seihou/Prelude.hs` imports the one module the house
style explicitly says must never be imported from a shared prelude.

After this plan is complete, a contributor reading any seihou module sees a single,
consistent record idiom: strict fields, no field prefixes, explicit deriving strategies with
`Generic` everywhere, field reads written `record ^. #fieldName`, and field writes written
`record & #fieldName .~ value`. The `OverloadedRecordDot` extension is gone from every Cabal
stanza, so the old idiom cannot silently come back. A repository check enforces the
convention the same way `nix/check-cli-module-placement.sh` enforces the CLI module-placement
convention today, and it runs in both the pre-commit hook and `nix flake check`.

This is an internal refactor, so "observable outcome" needs care. Three things are observable
and must be demonstrated, not merely asserted:

1. The full test suite — 84 test modules across three packages — passes before and after,
   with the same number of examples. Behavior is unchanged; only the idiom changes.
2. The CLI still performs a real end-to-end scaffold. After the change, running
   `seihou init`, `seihou new-module my-haskell`, and `seihou run my-haskell` in a scratch
   directory still produces a generated project and a manifest, exactly as
   `docs/user/getting-started.md` describes.
3. The new enforcement check *fails* when someone reintroduces the old idiom, and passes on
   the converted tree. That is demonstrated by deliberately reintroducing one violation,
   watching the check reject it, and reverting.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M0 — Re-measure the baseline counts and test totals (2026-07-27)
- [x] M0 — Spike: prove `#label` compiles in this codebase alongside `OverloadedRecordDot` (2026-07-27)
- [x] M0 — Spike: measure clean-build wall time before and after, on one module (2026-07-27)
- [x] M0 — Spike: confirm `module Control.Lens` re-export introduces no ambiguity errors (2026-07-27) — it *does*; four names hidden, see Surprises
- [x] M1 — Rewrite `seihou-core/src/Seihou/Prelude.hs` to re-export `module Control.Lens` (2026-07-27)
- [x] M1 — Remove `import "generic-lens" Data.Generics.Labels ()` from the prelude (2026-07-27)
- [x] M1 — Re-export `Generic` from the prelude (2026-07-27) — discovered during the spike
- [x] M1 — Add `generic-lens` and `lens` to `seihou-cli` and `seihou-okf-extension` deps (2026-07-27)
- [x] M1 — Add `DeriveAnyClass` to all eight Cabal `default-extensions` blocks (2026-07-27)
- [x] M1 — Merge the duplicated `default-extensions` block in `test-suite seihou-cli-test` (2026-07-27)
- [x] M1 — Verify `cabal build all` and `cabal test all` still pass unchanged (2026-07-27)
- [x] M2 — Add `deriving stock (Generic)` to the 81 record types that lack it (2026-07-27)
- [x] M2 — Add `!` strictness annotations to every record field in `src/` and `src-exe/` (2026-07-27)
- [x] M2 — Add `!` strictness annotations to every record field in the three `test/` trees (2026-07-27)
- [x] M2 — Fill in the four record literals that omitted a now-strict field (2026-07-27)
- [x] M2 — Add `import GHC.Generics (Generic)` to the 7 modules that skip the prelude (2026-07-27)
- [ ] M3 — Remove per-type field name prefixes from the affected record types
- [ ] M4 — Convert field reads in `seihou-core` (`src/` and `test/`) to `^. #field`
- [ ] M5 — Convert field reads in `seihou-cli` and `seihou-okf-extension` to `^. #field`
- [ ] M6 — Convert the 47 `src` and 61 `test` record-update sites to lens setters
- [ ] M7 — Remove `OverloadedRecordDot` from all six Cabal `default-extensions` blocks
- [ ] M7 — Confirm the three sum-typed record types still compile via pattern matching
- [ ] M8 — Add `nix/check-record-conventions.sh` and wire it into pre-commit and flake check
- [ ] M8 — Demonstrate the check rejecting a deliberately reintroduced violation
- [ ] M8 — Document the convention in the architecture overview and contributing guide
- [ ] M9 — Run the end-to-end scaffold scenario and capture the transcript


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

### Re-measured baseline (2026-07-27, before any change)

The plan-authoring counts had drifted slightly. Actual baseline on the tree at commit
`ff78410`:

```text
dot-access src:          2818   (plan said 2810)
dot-access test:         1927   (plan said 1917)
accessor sections src:    114   (unchanged)
record updates src:        48   (plan said 47)
record updates test:       62   (plan said 61)
.hs files:                261
```

Test totals, which must be identical at the end:

```text
seihou-core-test            1034 tests
seihou-cli-test              421 tests
seihou-okf-extension-test     16 tests
```

The toolchain is GHC **9.12.4**, not 9.12.2 as the plan states, and `lens` resolves to
`5.3.6` rather than the `5.4` the plan expected from the local corpus. Both are inside the
declared bounds, so no bound change was needed.

### The wholesale `Control.Lens` re-export *does* collide — four names

The plan's authoring analysis concluded "the intersection was empty in both directions" and
predicted the wholesale re-export would be safe. That analysis was wrong, in two ways that
are worth naming because they explain why a grep-based prediction cannot substitute for a
compile.

First, it compared `Control.Lens`'s exports only against names seihou imports through
*explicit import lists*. It therefore missed `Options.Applicative`, which
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` imports openly with no list at all.

Second, it compared against "the 1,311 top-level names seihou defines", which was derived
from top-level type signatures. Data constructors have no type signature, so the whole
constructor namespace was invisible to it.

The four actual collisions, all found by GHC:

```text
(.=)      Data.Aeson.(.=) vs Control.Lens.Setter.(.=)
          11 modules, in hand-written ToJSON instances.
argument  Options.Applicative.argument vs Control.Lens.Setter.argument
          Seihou.CLI.Commands, 8 use sites.
List      Seihou.CLI.Commands's `Command` constructor vs lens's
          `pattern List` (Control.Lens.Iso).
Context   Seihou.CLI.Commands's `Command` constructor vs lens's
          `Context(..)` (Control.Lens.Lens).
```

Evidence, from `cabal build all` with a bare `import "lens" Control.Lens`:

```text
src/Seihou/Engine/UpdateTransaction.hs:77:16: error: [GHC-87543]
    Ambiguous occurrence ‘.=’.
    It could refer to
       either ‘Data.Aeson..=’, ...
           or ‘Seihou.Prelude..=’, ...
              (and originally defined in ‘Control.Lens.Setter’).
```

```text
src-exe/Seihou/CLI/Commands.hs:729:8: error: [GHC-87543]
    Ambiguous occurrence ‘List’.
    It could refer to
       either ‘Seihou.Prelude.List’,
              (and originally defined in ‘lens-5.3.6:Control.Lens.Iso’),
           or ‘Seihou.CLI.Commands.List’,
              defined at src-exe/Seihou/CLI/Commands.hs:71:5.
```

Resolved with the plan's documented fallback — a targeted `hiding` clause on the prelude's
lens import, with an inline comment naming each name and why seihou does not need it. None
of the four is a combinator this refactor uses. See the Decision Log.

A precise re-run of the collision analysis, this time covering seihou's constructors, type
names, record fields and value bindings, found exactly five candidate names. Two
(`Context`, `List`) are the constructors above. The other three — `from`, `to`, `op` — are
*record fields*, and are harmless: `NoFieldSelectors` means a record field creates no
top-level selector function, so a field named `to` cannot be ambiguous with
`Control.Lens.Getter.to`. This is a small unadvertised benefit of keeping
`NoFieldSelectors` enabled, and it matters because `to` is a combinator the plan does
intend to use.

### `Generic` was not in scope anywhere

`Seihou.Prelude` re-exported no part of `GHC.Generics`, and the 166 existing `Generic`
derives each carry their own `import GHC.Generics (Generic)`. Adding `deriving stock
(Generic)` to the spike module failed with:

```text
src/Seihou/Effect/ConfigWriterPure.hs:21:23: error: [GHC-76037]
    Not in scope: type constructor or class ‘Generic’
```

Since the house style requires `Generic` on every record, `Generic` is now re-exported from
the prelude. Milestone 2 can then add derives without touching import lists.

### Only 4 of 102 test modules import `Seihou.Prelude`

This is the single biggest correction to the plan's shape. The plan assumed the test trees
would pick up the lens vocabulary the same way library modules do — through the shared
prelude. They do not: 98 of the 102 test modules import `Effectful`, `Test.Hspec`,
`Test.Tasty` and the module under test directly, and never touch `Seihou.Prelude`. The
spike's first test build failed with:

```text
test/Seihou/Effect/ConfigWriterSpec.hs:28:44: error: [GHC-88464]
    Variable not in scope: (&) :: ConfigWriterState -> t0 -> t1
```

So Milestones 4 through 6 must add a lens import to each converted test module, not only
the labels import. See the Decision Log for why that import is an explicit list rather than
an open `import Control.Lens`.

### `(^.)` binds looser than backtick application

`(^.)` is `infixl 8`; a backticked function defaults to `infixl 9`. So the natural
mechanical rewrite of an Hspec assertion is a parse error waiting to happen:

```haskell
-- WRONG: parses as  finalState ^. (#local `shouldBe` ...)
finalState ^. #local `shouldBe` Map.fromList [("local.key", "l")]

-- RIGHT
(finalState ^. #local) `shouldBe` Map.fromList [("local.key", "l")]
```

`record.field` needed no such parenthesis, because `OverloadedRecordDot`'s dot binds tighter
than everything. Every converted read that is an operand of a backticked function — which is
most reads in the 1,927-site test trees, since Hspec assertions are all backticked — needs
wrapping. Any conversion script must handle this or the test trees will not parse.

### `newtype` fields cannot be strict, so they are permanently exempt

The plan's strictness rule reads "every record field carries a `!` annotation", with no
exception. GHC does not allow one:

```text
src/Seihou/CLI/CommandExecution.hs:50:23: error: [GHC-04049]
    • A newtype constructor must not have a strictness annotation
    • In the definition of data constructor ‘CommandPlan’
```

This is not a limitation to work around — a `newtype` is a compile-time coercion with no
runtime box, so its single field is already as strict as its contents. Eleven record fields
in the repository belong to `newtype` declarations and stay lazy-looking forever. Milestone
8's enforcement script must skip `newtype` blocks, or it will flag correct code.

### Strict fields turn omitted record fields from a warning into an error

The plan anticipated that strictness could change runtime behavior at construction sites
supplying a diverging value. The actual effect was more useful: GHC refuses a record literal
that *omits* a strict field, where before it merely warned and filled the gap with a bottom.

```text
test/Seihou/OKF/Docs/RenderSpec.hs:171:11: error: [GHC-95909]
    • Constructor ‘Blueprint’ does not have the required strict field(s):
        launch :: Maybe AgentLaunch
```

Four test fixtures were building `Blueprint` and `AgentPrompt` values with a bottom sitting
in `launch` or `guidance` — harmless only for as long as no test demanded those fields. They
now pass `Nothing` and `[]` explicitly. No production code was affected, and no test changed
behavior: all 1,471 tests pass with identical counts.

### Compile time is not measurably worse

The plan flagged generic-lens compile cost as a risk worth measuring before committing to
~4,700 sites. On the spike module, three incremental rebuilds each way:

```text
converted (generic-lens):  2.84s  2.60s  2.72s
original  (record dot):    3.61s  2.65s  2.55s
```

The two are indistinguishable at this scale. This is weak evidence — one small module with
nine lens sites — so a full `seihou-core` library rebuild will be timed again at the end of
Milestone 4, where the sample is large enough to mean something.


## Decision Log

Record every decision made while working on the plan.

- Decision: Adopt the house record style in full — including replacing `OverloadedRecordDot`
  field access with `generic-lens` overloaded-label access across all ~4,700 call sites —
  rather than adopting only the low-risk subset (strictness, prefixes, record updates,
  prelude hygiene).
  Rationale: The user chose full conformance when presented with the measured cost of each
  option. Partial conformance would leave two competing record idioms in the codebase at the
  moment 1.0.0.0 freezes the maintenance promise, and would leave no mechanical way to stop
  the old idiom from spreading.
  Date: 2026-07-27

- Decision: Keep `NoFieldSelectors` enabled in every Cabal stanza.
  Rationale: The house style does not mention this extension either way. It suppresses the
  generation of top-level field selector functions, and it does not interfere with
  `generic-lens`, because overloaded-label access resolves through the `Generic`
  representation's field metadata rather than through selector functions. Keeping it enabled
  mechanically prevents the "don't use record syntax for access" anti-pattern from creeping
  back, which is exactly what this plan is trying to guarantee. Removing it would restore
  selector functions that `DuplicateRecordFields` would then make ambiguous at nearly every
  use site.
  Date: 2026-07-27

- Decision: Remove `OverloadedRecordDot` from every Cabal stanza, but only in Milestone 7,
  after all call sites are converted.
  Rationale: `OverloadedRecordDot` dot access and `generic-lens` label access can coexist in
  the same module. Keeping both available during the conversion means every intermediate
  commit compiles and every intermediate commit passes the test suite, which is the
  parallel-implementation approach the ExecPlan specification recommends for large
  migrations. Removing the extension first would break roughly 4,700 call sites in a single
  unreviewable commit.
  Date: 2026-07-27

- Decision: Do not attempt overloaded-label access for the three sum types that carry record
  fields (`Seihou.Core.Types.Operation`, `Seihou.Core.Migration.MigrationOp`,
  `Seihou.Engine.Preview.PreviewLine`). Leave those accessed by pattern matching.
  Rationale: `generic-lens` can only produce a lens for a field that appears in *every*
  constructor of a type. In all three of these types, no field appears in every constructor.
  This is not a workaround: the house style explicitly permits pattern matching, stating that
  matching a record in a function head is "fine and often clearest" and that the anti-pattern
  is selector application and update syntax, not pattern matches. These types are already
  pattern-matched today for the same underlying reason — GHC's own `HasField` class has the
  identical all-constructors requirement, so `OverloadedRecordDot` never worked on them
  either.
  Date: 2026-07-27

- Decision: Enable `DeriveAnyClass` to match the house style's stated extension baseline,
  even though seihou currently has zero `deriving anyclass` clauses.
  Rationale: The full-conformance scope includes the extension baseline. The usual hazard of
  `DeriveAnyClass` is that it makes a bare `deriving (Foo)` clause ambiguous between the
  stock and anyclass strategies; seihou has zero bare deriving clauses (all 245 are
  `deriving stock`), and Milestone 8's enforcement check keeps it that way, so the hazard
  does not apply here.
  Date: 2026-07-27

- Decision: Hide four names — `(.=)`, `argument`, `pattern List`, and `Context (..)` — on the
  prelude's `import "lens" Control.Lens`, rather than renaming seihou's own names or
  qualifying the colliding imports at their use sites.
  Rationale: These are the four real collisions the wholesale re-export produces (see
  Surprises & Discoveries). None is a combinator this refactor needs: lens's `(.=)` is the
  `MonadState` assignment operator and seihou uses effectful's `State` with `modify`;
  `argument` is a `Setter` over a `Profunctor`'s argument position; `List` is an `IsList`
  pattern synonym; `Context` is the indexed store comonad. The alternatives are worse — the
  `(.=)` collision alone would mean qualifying every JSON object literal in eleven modules,
  and the `List`/`Context` collisions would mean renaming two constructors of the CLI's
  public `Command` type for the convenience of names nothing uses. This is the fallback the
  plan's Idempotence and Recovery section already sanctions; each hidden name carries an
  inline comment in the prelude naming the collision and the reason.
  Date: 2026-07-27

- Decision: Re-export `Generic` from `Seihou.Prelude`.
  Rationale: The house style requires `deriving stock (Generic)` on every record, and
  `generic-lens` synthesises `#label` from the `Generic` representation, so `Generic` is now
  needed in essentially every module that defines a type. The prelude already exists to carry
  exactly this kind of project-wide vocabulary, and re-exporting it means Milestone 2 adds
  derives without also editing 79 import lists. This is an addition to the house style's
  stated prelude contents, not a deviation from it — the style is silent on `Generic`.
  Date: 2026-07-27

- Decision: In test modules, import the lens vocabulary as an explicit list
  (`import Control.Lens ((&), (.~), (^.), ...)`) rather than opening `Control.Lens` or
  importing `Seihou.Prelude`.
  Rationale: Only 4 of the 102 test modules import `Seihou.Prelude`; the other 98 import
  `Test.Hspec`, `Test.Tasty`, and `Effectful` openly. Dragging ~800 lens names into those
  modules invites exactly the class of collision that Milestone 0 just found in the library
  (Hspec and QuickCheck both export names that lens also exports — `elements` and `example`
  among them), and each such collision would have to be chased down one test module at a
  time. An explicit list is collision-proof by construction and states at the top of each
  file which optics that file uses. The house style's "prelude re-exports all of
  `Control.Lens`" rule is about the *shared prelude*, which is unchanged; it says nothing
  about modules that do not use the prelude.
  Date: 2026-07-27

- Decision: Keep the Milestone 0 spike rather than reverting it.
  Rationale: The plan called for reverting the spike so that Milestones 1 through 6 could
  redo the same edits in their proper order. But the spike converted
  `seihou-core/src/Seihou/Effect/ConfigWriterPure.hs` *completely* — `Generic`, strictness,
  prefix removal, reads, and updates — and left the tree building with all 1,471 tests
  passing. Reverting a complete, verified conversion in order to reproduce it identically
  later is pure waste, and the ordering hygiene the revert was meant to protect only matters
  for partial conversions. The two spec files the spike also touched
  (`seihou-core/test/Seihou/Effect/ConfigWriterSpec.hs` and
  `seihou-cli/test/Seihou/CLI/SavePromptedSpec.hs`) are likewise fully converted for the
  fields they touch.
  Date: 2026-07-27

- Decision: Merge the duplicated `default-extensions` block in `test-suite seihou-cli-test`.
  Rationale: `seihou-cli/seihou-cli.cabal` carried two `default-extensions` fields in the
  same stanza — one before `hs-source-dirs` listing five extensions, one after `main-is`
  listing only `TypeFamilies`. Cabal concatenates repeated list fields so the effective set
  was correct, but the split makes the stanza's extension set invisible to any reader or
  checker that stops at the first block, and Milestone 8's enforcement script must read
  these blocks. Merged into one sorted block. This is why the plan's "six blocks" became
  eight stanzas and nine blocks.
  Date: 2026-07-27

- Decision: Convert the test suites too, in the same plan.
  Rationale: The three test trees contain 1,917 dot-access sites and 61 record-update sites.
  They must be converted regardless, because Milestone 7 removes `OverloadedRecordDot` from
  the test stanzas as well as the library stanzas — leaving them would simply fail to
  compile. Fixture records in tests also need strictness and `Generic` for the same reasons.
  Date: 2026-07-27


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

### What this repository is

Seihou is a composable, type-safe project scaffolding system written in Haskell. A user
writes a *module* — a directory containing a `module.dhall` definition and a `files/`
subdirectory of templates — and runs `seihou run <module>` to generate a project from it.
Seihou resolves variables from several sources, compiles a deterministic generation plan,
executes it, and records what it wrote in a manifest file so later runs can update
incrementally.

The repository is a three-package Cabal workspace, pinned by `cabal.project`:

- `seihou-core/` — the core library (`seihou-core`). Types, Dhall loading, template
  rendering, the execution engine, manifest handling, validation. Library sources are under
  `seihou-core/src/`, tests under `seihou-core/test/`.
- `seihou-cli/` — the CLI. This package has an unusual two-target split described below.
  Library sources are under `seihou-cli/src/`, executable sources under
  `seihou-cli/src-exe/`, tests under `seihou-cli/test/`.
- `seihou-okf-extension/` — a small companion binary that renders seihou registries into
  documentation bundles. Sources under `seihou-okf-extension/src/` and
  `seihou-okf-extension/src-exe/`, tests under `seihou-okf-extension/test/`.

All three packages are at `version: 0.5.0.0` today. The compiler is GHC 9.12.2 with the
`GHC2024` language edition. The build is driven either by `cabal` inside a Nix dev shell or
by the Nix flake directly.

There are six Cabal stanzas that carry a `default-extensions` block, and this plan touches
every one of them:

| Cabal file | Stanza |
| --- | --- |
| `seihou-core/seihou-core.cabal` | `library` |
| `seihou-core/seihou-core.cabal` | `test-suite seihou-core-test` |
| `seihou-cli/seihou-cli.cabal` | `library seihou-cli-internal` |
| `seihou-cli/seihou-cli.cabal` | `executable seihou` |
| `seihou-cli/seihou-cli.cabal` | `test-suite seihou-cli-test` |
| `seihou-okf-extension/seihou-okf-extension.cabal` | `library seihou-okf-extension-internal`, `executable seihou-okf-extension`, `test-suite seihou-okf-extension-test` |

(The last row is three stanzas in one file; there are eight stanzas in total across the three
files. Verify the exact list with `grep -n 'default-extensions' -A 10` on each `.cabal` file
before editing, because the count is easy to get wrong and missing one produces a confusing
compile failure in a single package.)

Every one of those blocks currently lists, at minimum:

```text
DuplicateRecordFields
NoFieldSelectors
OverloadedLabels
OverloadedRecordDot
OverloadedStrings
TypeFamilies
```

The `executable seihou` stanza additionally lists `PackageImports`.

### The CLI module-placement convention (so you do not trip over it)

`seihou-cli` deliberately splits its code across two source directories. Modules under
`seihou-cli/src/` belong to a private library called `seihou-cli-internal`. Modules under
`seihou-cli/src-exe/` belong to the `seihou` executable target. A module is only allowed to
live in `src-exe/` if it imports one of four dependencies — `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli` — or if it transitively imports another
executable-only seihou module (most often `Seihou.CLI.Commands`, which is pinned to the
executable by `Options.Applicative`).

This convention is mechanically enforced by `nix/check-cli-module-placement.sh`, which runs
both as a pre-commit hook and as a `nix flake check` check. **This plan must not move any
module between `src/` and `src-exe/`.** Editing files in place is fine; the check only
inspects placement. The convention is documented at `docs/dev/architecture/overview.md`
(section "CLI Module Placement Convention") and mirrored in `docs/dev/contributing.md`.
Milestone 8 adds a second enforcement script alongside the existing one and should follow its
structure.

### The house record style, restated in full

The house style lives in a document outside this repository. Because an ExecPlan must be
self-contained, its rules are restated here in full. Where the style refers to a different
project's module names, this restatement substitutes seihou's.

**Extensions and dependencies.** Every compilation unit enables `DeriveAnyClass`,
`DuplicateRecordFields` (so the same field name may appear in different record types),
`OverloadedLabels` (so `#fieldName` is valid syntax), and `OverloadedStrings`. The package
depends on `generic-lens` and `lens`. `GHC2024` already implies `DataKinds`,
`DerivingStrategies`, and `LambdaCase`, so those are not listed separately.

**The custom prelude re-exports lens, but never the labels orphan.** The project's shared
prelude re-exports the whole of `Control.Lens`. It must **not** import
`Data.Generics.Labels`. The reason matters and is not a style preference. The `#fieldName`
syntax is resolved by an `IsLabel` type class instance. `generic-lens` supplies one, but it
is an *orphan instance* — an instance defined in a module that owns neither the class nor the
type. Orphan instances propagate transitively: any module that imports a module that imports
`Data.Generics.Labels` also sees the instance, whether it wants it or not. Re-exporting it
from a shared prelude therefore forces the `generic-lens` interpretation of `#label` onto
every module in the project, and permanently breaks any module that needs a *different*
`IsLabel` instance. The concrete casualty named by the house style is the keiki DSL, which
overloads `#label` for its own purposes; with the `generic-lens` orphan in scope, keiki's
bare `#name` reads stop resolving, and the breakage cannot be repaired at the use site.

**The rule that follows:** import `Data.Generics.Labels ()` — note the empty import list,
which imports only instances — in *each individual module* that uses `#label` over a
`Generic` record. Use a plain, unqualified-by-package import here; `PackageImports` is
reserved for the custom prelude, where it pins `Control.Lens` to the `lens` package. Keep the
import out of modules that only *define* domain types and never manipulate them, so that
label-sensitive consumers can import the types without inheriting the orphan.

**Record definition rules.**

- *No field prefixes.* Rely on `DuplicateRecordFields` instead. Write
  `data Member = Member { memberId :: !MemberId, status :: !MemberStatus }`, never
  `_memberMemberId` or `memberStatus`.
- *Strict fields always.* Every record field carries a `!` annotation. For a `Maybe` field,
  `!(Maybe UTCTime)` makes the `Maybe` constructor strict while its contents stay lazy, which
  is what is wanted.
- *Entity ID first.* In event and command payload records, the entity identifier is the first
  field. Seihou is not an event-sourced system and has no event or command records, so this
  rule has no sites in this repository. It is restated only so a future reader knows it was
  considered and found inapplicable.
- *Explicit deriving strategies always.* `deriving stock (...)` for standard classes,
  `deriving anyclass (...)` for classes derived via `Generic`, `deriving newtype (...)` for
  newtypes. A bare `deriving (Generic, Show)` with no strategy keyword is an anti-pattern.

**Field access rules.** Read with `^.` (`syncData ^. #status`). Set with `.~`
(`syncData & #status .~ newStatus`). Set a `Maybe` field to `Just x` with `?~`
(`stateData & #banStatus ?~ status`). Apply a function to a field with `%~`
(`rec & #counter %~ (+1)`, `state & #actions %~ (<> [action])`). Compose lenses with `.` for
nested access (`config ^. #streamCategories . #membersStreamCategory`) and nested update
(`config & #streamCategories . #membersStreamCategory .~ newStream`). Traverse into a `Maybe`
field with `_Just` (`state & #intention . _Just . #parent ?~ parentId`). Apply a pure
function after a lens read with `to` (`d ^. #areaIds . to (Set.fromList . NonEmpty.toList)`).

**Map rules.** Prefer the `at` and `ix` lenses over `Map.insert` and `Map.adjust`. `at` is
for insert and delete and focuses a `Maybe`, so `state & #blockers . at bid ?~ bv` inserts
and `state & #blockers . at bid .~ Nothing` deletes. `ix` only updates a key that already
exists and silently does nothing otherwise, so
`state & #blockers . ix bid . #resolvedAt ?~ time` is an in-place field update.

**Prefer lens over record update syntax.** This too is more than style. Under
`DuplicateRecordFields`, GHC 9.4 and later require that a bare selector occurrence be
entirely unambiguous, and accept a record *update* only when at most one datatype in scope
has every field being updated. So selector access and update syntax stop compiling exactly
where shared field names appear — which, in a codebase that follows the "no field prefixes"
rule, is everywhere. `#label` access resolves through `Generic` and is unaffected.

**Read fields consistently.** Do not mix selector access and lens access inside one function.

**What is explicitly allowed.** Record *construction* syntax is fine and is used throughout
the house style's own examples: `MemberImportedData { memberId = d ^. #memberId, ... }`.
Record *pattern matching* is fine, positionally or with field puns —
`\Member {createdAt} -> createdAt` is idiomatic, and `DuplicateRecordFields` resolves pun
fields by the constructor being matched. The anti-patterns are selector-function application
and record update `{}` syntax, not pattern matches and not construction.

**JSON serialization.** Define the project's shared Aeson options once, in the custom
prelude, and use them everywhere so the wire format is decided in one place.

### How seihou actually looks today

Every count below was measured on the working tree at plan-authoring time and is the baseline
for this work. Re-measure before starting; the numbers will have drifted if other work has
landed. The commands that produced them are given in Concrete Steps.

**Field access uses `OverloadedRecordDot`, not `#label`.** There are **2,810** dot-access
sites (`record.field`) in library and executable sources and **1,917** in the three test
trees. There are a further **114** accessor sections (`(.fieldName)`, used as a function in
`map` and `filter` callbacks) and **232** chained accesses (`a.b.c`). Against that, there are
**zero** uses of `^.`, `.~`, or `%~` anywhere in the repository outside
`seihou-core/src/Seihou/Prelude.hs` itself, and **zero** uses of `#label`. The lens
re-exports in the prelude are dead weight today.

**The prelude imports the forbidden orphan.** `seihou-core/src/Seihou/Prelude.hs` line 58
reads `import "generic-lens" Data.Generics.Labels ()`. Because 138 of seihou's 157 library
and executable modules import `Seihou.Prelude`, the orphan `IsLabel` instance is already in
scope nearly everywhere — it is simply never used. This is precisely the situation the house
style warns against.

**The prelude re-exports lens by explicit name list, not wholesale.** It currently exports
`view`, `over`, `set`, `(^.)`, `(.~)`, `(%~)`, `(&)`, `lens`, `Lens'`, `Getting`, and
`ASetter`. It does not export `(?~)`, `at`, `ix`, `_Just`, `to`, or `folded`, all of which
this plan needs.

**Records are lazy.** There are approximately **723** record fields across library and
executable sources. Exactly **15** of them carry a `!` annotation, all in
`seihou-cli/src/Seihou/Fzf.hs` and `seihou-cli/src-exe/Seihou/CLI/Help.hs`. The other ~708
are lazy.

**Seventy-nine record types have no `Generic` instance.** Overloaded-label access requires
one. The list includes `Seihou.Core.Module.DiscoveredModule`,
`Seihou.Effect.FilesystemPure.PureFS`, `Seihou.Effect.ConsolePure.ConsoleState`,
`Seihou.Effect.ConfigWriterPure.ConfigWriterState`, `Seihou.Effect.LoggerPure.LoggerState`,
`Seihou.Composition.Instance.ModuleInstance`, `Seihou.Composition.Graph.CompositionGraph`,
the ten record types in `Seihou.Engine.Reconcile`, `Seihou.Engine.UpdateTransaction`'s three
types, `Seihou.CLI.CommandExecution.PlannedCommand` and `CommandPlan`, `Seihou.Fzf`'s three
types, and the four types in `seihou-okf-extension`. Regenerate the full list rather than
trusting this excerpt; the command is in Concrete Steps.

**Deriving strategies are already correct.** There are **245** `deriving stock` clauses and
**zero** bare `deriving (...)` clauses without a strategy keyword. This one house rule is
already satisfied and needs no work — only protection.

**Record update syntax is in use.** There are **47** true record-update sites in library and
executable sources across 21 files, and **61** in the test trees. Concentrations are in
`seihou-core/src/Seihou/Effect/FilesystemPure.hs` (5),
`seihou-core/src/Seihou/Effect/ConfigWriterPure.hs` (6),
`seihou-core/src/Seihou/Effect/LoggerPure.hs` (4),
`seihou-core/src/Seihou/Effect/ConsolePure.hs` (5),
`seihou-core/src/Seihou/Engine/Migrate.hs` (4), `seihou-cli/src/Seihou/Fzf.hs` (6), and
`seihou-cli/src/Seihou/CLI/CommandExecution.hs` (3). Note that a naive grep for `{ field =`
also matches record *construction* and record *pattern matches*, which are both permitted;
the refined pattern in Concrete Steps excludes constructor-led braces.

**About two dozen record types carry field prefixes.** Confirmed examples:
`Seihou.Effect.ConfigWriterPure.ConfigWriterState` (`cwLocal`, `cwGlobal`, `cwNamespaces`),
`Seihou.Effect.ConsolePure.ConsoleState` (`consoleInputs`, `consoleOutputs`,
`consoleErrors`), `Seihou.Effect.LoggerPure.LoggerState` (`logDebugMsgs`, `logInfoMsgs`,
`logWarnMsgs`, `logErrorMsgs`), `Seihou.Fzf.FzfConfig` and `FzfOpts` (`fzfBinary`,
`fzfPrompt`, `fzfHeader`, `fzfHeight`, `fzfAnsi`, `fzfNoSort`, `fzfPreview`),
`Seihou.Fzf.Candidate` (`candidateDisplay`), `Seihou.Core.Types.Dependency` (`depModule`,
`depVars`), `Seihou.Core.Module.DiscoveredModule` (`discoveredResult`, `discoveredSource`,
`discoveredDir`) and `DiscoveredRunnable` (`drName`), `Seihou.Core.Migration` (`planModule`,
`blueprintPlanName`), `Seihou.Engine.Preview.PreviewLine` (`previewPath`, `previewStatus`,
`previewModule`, `previewAnnotation`), `Seihou.CLI.Help.HelpTopic` (`topicName`),
`Seihou.CLI.AgentCompletion` (`agentProvider`), and
`Seihou.OKF.Docs.Model` (`entryName`, `refName`, `refResolved`). Regenerate the list rather
than trusting this excerpt.

**Three sum types carry record fields and cannot use `#label`.** They are
`Seihou.Core.Types.Operation` (constructors `WriteFileOp`, `CreateDirOp`, `CopyFileOp`,
`RunCommandOp`, `PatchFileOp`), `Seihou.Core.Migration.MigrationOp` (`MoveFile`, `MoveDir`,
`DeleteFile`, `DeleteDir`, `RunCommand`), and `Seihou.Engine.Preview.PreviewLine`
(`FilePreview`, `DirPreview`, `CommandPreview`, `OrphanPreview`). In all three, no field name
appears in every constructor. They are already accessed by pattern matching, because GHC's
`HasField` has the same all-constructors requirement, so `OverloadedRecordDot` never worked
on them either. They still need strictness annotations and `Generic`, but their access sites
need no conversion.

**`generic-lens` and `lens` are dependencies of `seihou-core` only.** They are declared in
`seihou-core/seihou-core.cabal` as `generic-lens >=2.2 && <3` and `lens >=5.2 && <6`. They
are *not* declared in `seihou-cli/seihou-cli.cabal` or
`seihou-okf-extension/seihou-okf-extension.cabal`. Those two packages currently reach lens
only transitively through `Seihou.Prelude`, which is enough for re-exported names but is not
enough for a direct `import Data.Generics.Labels ()`.

### How `generic-lens` overloaded labels actually work

This matters because two of its constraints shape the plan.

The `#fieldName` syntax comes from the `OverloadedLabels` extension, which desugars `#foo`
into `fromLabel @"foo"`, a method of the `IsLabel` class. The `generic-lens` package provides
a single, very general orphan `IsLabel` instance in the module `Data.Generics.Labels`. That
instance inspects the label at the type level: a label starting with a lowercase letter is
treated as a *field* and produces a lens; a label starting with an uppercase letter (or, on
older GHC, an underscore followed by an uppercase letter) is treated as a *constructor* and
produces a prism; a label starting with a digit produces a positional lens. Only the
lowercase field form is used in this plan.

Two constraints follow directly:

1. **The record type must derive `Generic`.** The lens is synthesized from the type's
   `Generic` representation. This is why 79 types need a `Generic` derive added before their
   fields can be read with `#label`. Note that `NoFieldSelectors` does *not* interfere:
   it suppresses the generation of top-level selector functions but leaves the `Generic`
   representation's field-name metadata intact.

2. **For a multi-constructor type, the field must appear in *every* constructor.** If it does
   not, the compile fails with a message of the form:

   ```text
   Not all constructors of the type Human Bool
   contain a field named 'address'.
   The offending constructors are:
   HumanNoAddress
   ```

   This is what rules out the three sum types listed above.

A third practical consequence: because the lens is synthesized generically at each use site,
`generic-lens` increases compile time relative to plain field selectors. Milestone 0 measures
this on one module so that the cost is known before ~4,700 sites are converted, rather than
discovered afterwards.

### Relevant Architecture Decision Records

**There are no relevant ADRs, because this repository has no ADR corpus.** `docs/adr/` does
not exist. `mori.dhall` at the repository root declares the project, its four packages, its
skills, and two documentation references (`docs/dev/architecture/overview.md` and
`docs/dev/roadmap/v1-milestones.md`), but declares no OKF bundle whose path is `docs/adr`.
Per the ADR workflow this skill follows, when no profiled bundle exists the correct behavior
is to preserve the repository's established filesystem convention and *not* to invent OKF
frontmatter or Mori identity as an incidental plan edit.

Durable architectural context in this repository lives in two places instead, and Milestone 8
updates both:

- `docs/dev/architecture/overview.md` — the canonical home for cross-cutting conventions. It
  already carries "CLI Module Placement Convention" (with a trapped-modules inventory table)
  and a "Key Architectural Decisions" section.
- `docs/dev/contributing.md` — mirrors conventions for contributors, and states explicitly
  that if the two diverge the architecture doc is authoritative.

Prior plans in `docs/plans/` record repeated friction with the current idiom, and are worth
skimming as evidence that the change is warranted, though none of them is a prerequisite:
`docs/plans/20-extract-trapped-cli-helpers.md` (the `OverloadedRecordDot`/`HasField`
import-order sensitivity), `docs/plans/12-sync-registry-versions.md` (ambiguity from shared
`version` and `name` fields), `docs/plans/add-fzf-integration.md` (explicit import lists not
bringing `HasField` instances into scope), and
`docs/plans/3-add-agent-kit-command.md` (choosing explicit accessors over dot syntax in
callbacks). Each of these frictions disappears under `#label`, which resolves through
`Generic` and is insensitive to import lists and to field-name sharing.


## Plan of Work

The work is arranged so that every milestone leaves a tree that compiles and whose tests
pass. The essential trick is that `OverloadedRecordDot` dot access and `generic-lens` label
access coexist happily: a module can contain `config.environment` and
`config ^. #environment` on adjacent lines. So the extension stays enabled through
Milestones 0 to 6 while call sites are converted package by package, and is removed only in
Milestone 7, at which point any missed site becomes a compile error rather than a silent
inconsistency. That is deliberate: the compiler, not a reviewer, finds the stragglers.

Commit after each milestone at minimum, and more often within the larger ones. Every commit
carries the trailer `ExecPlan: docs/plans/75-adopt-generic-lens-record-conventions-before-1-0-0-0.md`.
No `Intention:` trailer is used; the user declined to associate an Intention with this plan.
Work directly on `master`; do not create a feature branch.

### Milestone 0 — Spike: prove the idiom works here, and measure what it costs

Scope: touch exactly one module and prove three things before committing to a 4,700-site
conversion. What exists at the end: a throwaway or reverted change plus three recorded
measurements in Surprises & Discoveries.

The three questions to answer are: (a) does `record ^. #field` actually compile in a seihou
module, given `NoFieldSelectors`, `DuplicateRecordFields`, and the effectful-based effect
stack; (b) does re-exporting the whole of `Control.Lens` from `Seihou.Prelude` introduce
ambiguous-name errors anywhere; and (c) how much does the generic machinery cost in compile
time.

Question (b) has a promising preliminary answer from plan authoring. The set of ~282
term-level names that `Control.Lens` re-exports was compared against the 1,311 top-level
names seihou defines and against every name seihou imports through an explicit import list.
**The intersection was empty in both directions.** The wholesale re-export therefore looks
safe, but "looks safe by grep" is not "compiles", so it is verified for real here.

Pick `seihou-core/src/Seihou/Effect/ConfigWriterPure.hs` as the spike module. It is small,
it has a record (`ConfigWriterState`) that currently lacks `Generic`, has prefixed fields
(`cwLocal`, `cwGlobal`, `cwNamespaces`), is lazy, and contains six record-update sites — so
it exercises every rule this plan applies, in miniature. Convert it fully, build, run its
tests (`seihou-core/test/Seihou/Effect/ConfigWriterSpec.hs`), then record the findings and
revert. Reverting is deliberate: the spike's job is to produce knowledge, and Milestones 1
through 6 redo the same edits in their proper order.

Acceptance: `cabal build seihou-core` succeeds with the spike applied; `cabal test
seihou-core-test` passes; three measurements are written into Surprises & Discoveries; the
working tree is clean again afterwards.

### Milestone 1 — Prelude and build wiring

Scope: make the house idiom *available* everywhere without using it anywhere yet. What exists
at the end: a rewritten `Seihou.Prelude` that re-exports all of `Control.Lens` and no longer
imports the labels orphan; `generic-lens` and `lens` declared as direct dependencies of all
three packages; `DeriveAnyClass` enabled in all eight Cabal stanzas. Nothing else changes,
and the entire test suite must pass unchanged.

Rewrite `seihou-core/src/Seihou/Prelude.hs`. Replace the explicit lens export list
(`view`, `over`, `set`, `(^.)`, `(.~)`, `(%~)`, `(&)`, `lens`, `Lens'`, `Getting`, `ASetter`)
with a wholesale `module Control.Lens` re-export, keeping the `PackageImports` pragma and the
`import "lens" Control.Lens` form so the package stays pinned. Delete line 58,
`import "generic-lens" Data.Generics.Labels ()`, entirely — nothing uses it yet, so its
removal is a no-op today and prevents it being reintroduced by habit later.

The resulting module head should look like this. Note that the other re-export groups
(`Text`, `Map`, `Set`, the effectful core, `first`, `FilePath`, `(</>)`) are unchanged and
are elided here for brevity; preserve them exactly.

```haskell
{-# LANGUAGE PackageImports #-}

module Seihou.Prelude
  ( -- * Text
    Text,

    -- ... other existing export groups unchanged ...

    -- * Lens
    module Control.Lens,

    -- ... remaining existing export groups unchanged ...
  )
where

-- Re-export the whole lens API. PackageImports pins the package so that
-- `Control.Lens` unambiguously means the `lens` package's module.
--
-- Deliberately absent: Data.Generics.Labels. Its IsLabel instance is an
-- orphan, and orphan instances propagate transitively, so importing it here
-- would force the generic-lens interpretation of #label onto every module in
-- the project. Each module that uses #label imports it individually instead.
import "lens" Control.Lens

-- ... other existing imports unchanged ...
```

Then add the dependencies. `seihou-core/seihou-core.cabal` already declares
`generic-lens >=2.2 && <3` and `lens >=5.2 && <6` in its `library` stanza. Add the same two
lines to `seihou-cli/seihou-cli.cabal` (the `library seihou-cli-internal`, `executable
seihou`, and `test-suite seihou-cli-test` stanzas), to
`seihou-okf-extension/seihou-okf-extension.cabal` (all three stanzas), and to
`seihou-core`'s `test-suite seihou-core-test` stanza. Before committing to those bounds,
verify the currently released versions on Hackage rather than assuming; the local corpus
checkout carries `generic-lens 2.3.0.0` and `lens 5.4`, both of which the existing bounds
already admit, so no bound change is expected — but confirm rather than assume.

Finally add `DeriveAnyClass` to the `default-extensions` block of every stanza, keeping the
lists alphabetically sorted (`cabal-gild` sorts them anyway, and `nix fmt` will rewrite the
file if you get it wrong).

Acceptance: `cabal build all` and `cabal test all` both succeed with no new warnings, and the
test counts are identical to the pre-milestone run. If the wholesale `Control.Lens`
re-export produces an ambiguous-occurrence error in some module, that is the outcome
Milestone 0 was meant to catch; resolve it by adding a targeted `hiding` clause to the
prelude's `import "lens" Control.Lens` and record the name and the reason in Surprises &
Discoveries.

### Milestone 2 — `Generic` everywhere, and strict fields everywhere

Scope: satisfy the two structural preconditions for the rest of the work. What exists at the
end: every record type in the repository derives `Generic`, and every record field carries a
`!` annotation. Roughly 79 type declarations and roughly 711 field declarations change,
across library, executable, and test sources.

Do `Generic` first, because it is the precondition for Milestone 4. For each of the 79 record
types identified by the detection script, add `Generic` to the existing `deriving stock`
clause, or add a new `deriving stock (Generic)` clause if the type has none. Do not change
any existing derived class, and do not introduce bare deriving clauses.

Then do strictness. Add `!` before the type of every record field. For `Maybe`-typed and
otherwise-parameterized fields, parenthesize: `!(Maybe UTCTime)`, `!(Map VarName Text)`,
`!(Either ModuleLoadError Module)`. This includes the three sum types with record fields.

Strictness is the one part of this plan that can change runtime behavior, so treat it with
care rather than as pure mechanics. A strict field is forced when the record is constructed.
If any construction site currently supplies a field value that would diverge or throw and is
never demanded, making the field strict turns a silently-ignored bad value into a crash.
A survey of the test trees found exactly one `= undefined` or `= error ...` binding; check it,
and check any place where a record is built from a partially-failed computation. The
`Seihou.Manifest.Types` module hand-writes its `ToJSON`/`FromJSON` instances (rather than
deriving them), so strictness there interacts with JSON decoding: a strict field means a
decoded record forces all its fields at construction. That is desirable — it surfaces decode
errors eagerly — but it is a behavior change worth watching in the manifest round-trip tests.

Work package by package and commit per package so that a bisect can isolate a strictness
regression to one package.

Acceptance: `cabal build all` succeeds; `cabal test all` passes with the same example count
as before; the detection scripts for missing-`Generic` and lazy-field report zero hits.

### Milestone 3 — Remove field name prefixes

Scope: rename prefixed fields to their unprefixed form. What exists at the end: no record
field is named with its own type's abbreviation as a prefix.

This is a rename, and it is safe today precisely because `NoFieldSelectors` is enabled: there
are no top-level selector functions to collide, and `DuplicateRecordFields` allows the same
field name in many types. The rename touches three kinds of site: the field declaration, any
record construction or pattern match that names the field, and — until Milestone 4 converts
them — any `record.prefixedField` dot access.

Apply it type by type, and let the compiler drive: rename the declaration, rebuild the
package, and fix what breaks. Do not use a global search-and-replace on the bare name, since
names like `logInfoMsgs` are distinctive but names like `previewPath` are not.

Two renames deserve individual attention:

`seihou-cli/src/Seihou/Fzf.hs` defines `FzfOpts` with a `Monoid` instance, and six helper
functions built on `mempty { fzfPrompt = Just p }` and similar. After the rename these become
`mempty { prompt = Just p }`, and after Milestone 6 they become `mempty & #prompt ?~ p`.
Do the rename here and leave the update-syntax conversion for Milestone 6, so each commit has
one kind of change in it.

`Seihou.Engine.Preview.PreviewLine` is one of the three sum types. Its four fields
(`previewPath`, `previewStatus`, `previewModule`, `previewAnnotation`) become `path`,
`status`, `module_`, `annotation` — note that `module` is a reserved word in Haskell, so a
trailing underscore is required, matching the existing convention in
`Seihou.Core.Types.VarDecl`, which already uses `type_` and `default_`.

Acceptance: `cabal build all` and `cabal test all` pass; the prefix-detection script reports
zero hits.

### Milestone 4 — Convert field reads in `seihou-core`

Scope: replace every `record.field` read in `seihou-core/src/` and `seihou-core/test/` with
`record ^. #field`, and add the per-module labels import. What exists at the end: `seihou-core`
uses the house idiom for reads while `OverloadedRecordDot` is still enabled, so the package
still builds either way and the diff is reviewable in isolation.

For each module that performs at least one field read, add the plain import
`import Data.Generics.Labels ()` — empty parentheses, no package pin. Then rewrite the reads:

```haskell
-- Before
config.environment
manifest.files
plan.planTo

-- After
config ^. #environment
manifest ^. #files
plan ^. #to          -- after the Milestone 3 prefix rename
```

Chained access composes with `.`:

```haskell
-- Before
config.streamCategories.membersStreamCategory

-- After
config ^. #streamCategories . #membersStreamCategory
```

Accessor sections used as functions become lens reads. There are 114 of these across the
repository:

```haskell
-- Before
map (.name) modules
nubOrdBy (.depModule) effectiveDeps

-- After
map (^. #name) modules
nubOrdBy (^. #module_) effectiveDeps
```

Two situations need judgment rather than mechanics. First, a read whose subject is a value of
one of the three sum types (`Operation`, `MigrationOp`, `PreviewLine`) cannot be converted —
but there should be none, because such reads never compiled. If you find one, you have
misidentified the type; check. Second, some reads occur inside a `do` block over the
effectful monad where `^.` composes awkwardly with `<-`; in those cases `view #field <$>
action` reads better than `(^. #field) <$> action`, and both are house-conformant. Choose
readability.

Do **not** add the labels import to a module that only *defines* record types and never
manipulates them. The house style is explicit that keeping the orphan out of definition
modules is what lets label-sensitive consumers import the types cleanly.
`seihou-core/src/Seihou/Core/Types.hs` is the main such module — it is almost entirely type
declarations. Check whether it performs any reads before adding the import; if it does not,
leave it out.

Commit in slices — by directory (`Seihou/Core/`, `Seihou/Dhall/`, `Seihou/Effect/`,
`Seihou/Composition/`, `Seihou/Engine/`, `Seihou/Manifest/`, `Seihou/Interaction/`) rather
than one enormous commit — and build after each slice.

Acceptance: `cabal build seihou-core` and `cabal test seihou-core-test` pass; the dot-access
detection script reports zero hits under `seihou-core/`.

### Milestone 5 — Convert field reads in `seihou-cli` and `seihou-okf-extension`

Scope: the same conversion, applied to `seihou-cli/src/`, `seihou-cli/src-exe/`,
`seihou-cli/test/`, `seihou-okf-extension/src/`, `seihou-okf-extension/src-exe/`, and
`seihou-okf-extension/test/`. This is the largest single milestone by volume: the CLI carries
the bulk of the 2,810 source-side and 1,917 test-side dot accesses.

Everything from Milestone 4 applies unchanged. One additional caution: several CLI modules
import `Seihou.Core.Types` unqualified specifically because explicit import lists do not
bring GHC's `HasField` instances into scope for `OverloadedRecordDot` — a workaround
documented in `docs/plans/add-fzf-integration.md` and
`docs/plans/20-extract-trapped-cli-helpers.md`. That workaround becomes unnecessary under
`#label`, which resolves through `Generic` rather than through `HasField`. Do not tidy those
imports in this milestone; note the candidates in Surprises & Discoveries and leave the
cleanup for a follow-up, so this milestone's diff stays mechanical.

Remember the module-placement constraint: edit in place, never move a module between
`seihou-cli/src/` and `seihou-cli/src-exe/`.

Commit in slices by directory, building after each.

Acceptance: `cabal build all` and `cabal test all` pass; the dot-access detection script
reports zero hits repository-wide.

### Milestone 6 — Convert record updates to lens setters

Scope: the 47 library and executable record-update sites and the 61 test-tree sites. What
exists at the end: no record update `{}` syntax anywhere; record construction and pattern
matching are untouched.

The mapping is mechanical but the operator choice is not, so pick deliberately:

```haskell
-- Plain field set: use .~
-- Before
entry { version = diff ^. #new }
-- After
entry & #version .~ diff ^. #new

-- Multiple fields: chain with &
-- Before
existing { hash = c ^. #diskHash, generatedAt = now }
-- After
existing
  & #hash .~ c ^. #diskHash
  & #generatedAt .~ now

-- Setting a Maybe field to Just: use ?~, not .~ Just
-- Before
journal { expectedManifest = Just expected }
-- After
journal & #expectedManifest ?~ expected

-- Function applied to a field: use %~
-- Before
summary { willRun = summary ^. #willRun + 1 }
-- After
summary & #willRun %~ (+ 1)

-- Appending to a list field: %~ with the append
-- Before
s { outputs = s ^. #outputs ++ [msg] }
-- After
s & #outputs %~ (<> [msg])

-- Map insert: use the at lens with ?~
-- Before
fs { files = Map.insert path content (fs ^. #files) }
-- After
fs & #files . at path ?~ content

-- Map delete: at with .~ Nothing
-- Before
fs { files = Map.delete path (fs ^. #files) }
-- After
fs & #files . at path .~ Nothing

-- Map adjust of an existing key: use ix
-- Before
st { entries = Map.adjust f k (st ^. #entries) }
-- After
st & #entries . ix k %~ f
```

The `at`-versus-`ix` distinction is a real semantic choice, not a style choice. `at` focuses
a `Maybe` and can insert or delete. `ix` only touches a key that already exists and silently
does nothing otherwise. `Map.insert` maps to `at ... ?~`; `Map.adjust` maps to `ix ... %~`;
`Map.delete` maps to `at ... .~ Nothing`. Getting this backwards changes behavior, so check
each site rather than pattern-matching on shape.

The pure effect interpreters — `seihou-core/src/Seihou/Effect/FilesystemPure.hs`,
`ConsolePure.hs`, `ConfigWriterPure.hs`, `LoggerPure.hs`, `ProcessPure.hs`,
`BaselineStorePure.hs` — hold the densest concentration and mostly follow the
`modify @State (\s -> s { field = ... })` shape. These become
`modify @State (\s -> s & #field . at k ?~ v)` and similar. They have direct spec files
(`seihou-core/test/Seihou/Effect/*Spec.hs`) that exercise them, so convert one interpreter,
run its spec, and only then move on.

`seihou-cli/src/Seihou/Fzf.hs`'s six `mempty { fzfX = ... }` helpers become
`mempty & #x ?~ ...` (or `.~ True` for the two `Bool` options). Confirm that `FzfOpts`'s
`Monoid` instance still behaves as before by running
`seihou-cli/test/Seihou/FzfSpec.hs`.

Acceptance: `cabal build all` and `cabal test all` pass; the record-update detection script
reports zero hits.

### Milestone 7 — Remove `OverloadedRecordDot` and let the compiler find stragglers

Scope: delete `OverloadedRecordDot` from the `default-extensions` block of all eight Cabal
stanzas, then fix whatever fails to compile. What exists at the end: the old idiom is no
longer expressible anywhere in the repository.

This milestone is deliberately placed after all conversion work because it converts "a site
we missed" from an invisible inconsistency into a hard compile error. Expect some failures —
that is the point, and they are the milestone's value. Fix each by converting the site the
same way Milestones 4 through 6 did.

Also confirm here that the three sum types with record fields still compile. They are
accessed only by pattern matching and construction, neither of which depends on
`OverloadedRecordDot`, so no change is expected. If one does fail, the fix is a pattern match
or a small hand-written accessor function, not a `#label`.

Acceptance: `cabal build all` and `cabal test all` pass with `OverloadedRecordDot` absent
from every stanza; `grep -rn OverloadedRecordDot` over the three `.cabal` files and all `.hs`
files returns nothing.

### Milestone 8 — Enforcement and documentation

Scope: make the convention permanent. What exists at the end: a shell script that fails on a
violation, wired into both the pre-commit hook and `nix flake check`; and the convention
written down in the two canonical documentation homes.

Create `nix/check-record-conventions.sh`, modelled on the existing
`nix/check-cli-module-placement.sh` — read that script first and match its structure, its
exit-code discipline, and its error-message style. The new script must fail on each of these:

1. Any `.cabal` stanza listing `OverloadedRecordDot`.
2. Any `.cabal` stanza *not* listing all of `DeriveAnyClass`, `DuplicateRecordFields`,
   `NoFieldSelectors`, `OverloadedLabels`, `OverloadedStrings`.
3. Any record field declaration without a `!` annotation.
4. Any record update `{}` expression — that is, a `{ field =` brace whose head is a
   lowercase identifier or a closing parenthesis rather than an uppercase constructor name.
5. Any bare `deriving (` clause with no strategy keyword.
6. Any occurrence of `import Data.Generics.Labels` in `seihou-core/src/Seihou/Prelude.hs`.

Each of these is a heuristic over source text, not a parse, so each will have edge cases.
Prefer a check that is slightly too strict and offers a documented escape hatch (an
`EXEMPT_` list with an inline comment naming the reason, following the existing script's
precedent) over one that is too permissive. Do not attempt to detect missing `Generic`
derives or field prefixes in the script — the first is better caught by the compiler when a
`#label` fails to resolve, and the second cannot be distinguished from a legitimately
descriptive field name by text matching.

Wire the script into `nix/pre-commit.nix` as a new hook alongside `cli-module-placement`, and
into `flake.module.nix` as a new `checks.record-conventions` derivation alongside
`checks.cli-module-placement`. Copy the existing derivation's shape, including its
`nativeBuildInputs` list.

Then prove the check works. Reintroduce one violation by hand — for example, delete a single
`!` from a field in `seihou-core/src/Seihou/Core/Types.hs` — run the script, observe it
reject the tree with a message naming the file and line, and revert. Capture that transcript
in Validation and Acceptance.

Finally, document the convention. Add a section to `docs/dev/architecture/overview.md`
(this is the canonical home, per the note in `docs/dev/contributing.md` that the architecture
doc wins when the two diverge) covering: the extension baseline; the per-module
`Data.Generics.Labels ()` import and why it must not live in the prelude; the read, write,
and Map idioms; the strictness and no-prefix rules; the explicit-deriving rule; the fact that
construction and pattern matching are permitted; the all-constructors limitation and the
three types it affects; and a pointer to the enforcement script. Mirror a condensed version
into `docs/dev/contributing.md` next to the existing "CLI Module Placement Convention"
section, and update the repository's `CLAUDE.md` so future coding agents pick up the
convention without reading the architecture doc first.

Acceptance: `nix flake check` passes on the converted tree and fails on the deliberately
broken one; the pre-commit hook rejects a commit containing a violation; both documentation
files describe the convention.

### Milestone 9 — End-to-end demonstration

Scope: show that the refactored CLI still does its job. What exists at the end: a captured
transcript of a real scaffold run, recorded in Validation and Acceptance.

Nothing in this plan is supposed to change behavior, and the test suite is the primary
evidence of that. But a test suite can pass while an integrated binary is broken, so run the
scenario from `docs/user/getting-started.md` end to end against a freshly built binary in a
scratch directory, and confirm it produces a generated project and a manifest.

Acceptance: the transcript in Validation and Acceptance shows `seihou init`,
`seihou new-module`, and `seihou run` succeeding, and `seihou status` reporting the
generated files.


## Concrete Steps

All commands are run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, unless stated otherwise. Enter the
pinned toolchain first:

```bash
nix develop
```

### Establish the baseline

Run these before touching anything, and paste the numbers into Surprises & Discoveries as the
"before" column. They are the same commands that produced the counts in Context and
Orientation.

```bash
cabal build all 2>&1 | tail -5
cabal test all 2>&1 | tail -20
```

Expected: a successful build, and a test summary from each of the three suites. Record the
example counts; they must be identical at the end.

Count dot-access sites in library and executable sources:

```bash
grep -rnoE '(^|[^A-Za-z0-9_."])[a-z][a-zA-Z0-9_'"'"']*\.[a-z][a-zA-Z0-9_'"'"']*' \
  --include='*.hs' \
  seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-okf-extension/src | wc -l
```

Expected at baseline: `2810`.

Count them in the test trees:

```bash
grep -rnoE '(^|[^A-Za-z0-9_."])[a-z][a-zA-Z0-9_'"'"']*\.[a-z][a-zA-Z0-9_'"'"']*' \
  --include='*.hs' \
  seihou-core/test seihou-cli/test seihou-okf-extension/test | wc -l
```

Expected at baseline: `1917`.

Count accessor sections:

```bash
grep -rnoE '\(\.[a-z][a-zA-Z0-9_'"'"']*\)' --include='*.hs' \
  seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-okf-extension/src | wc -l
```

Expected at baseline: `114`.

Count true record updates — the leading character class excludes uppercase constructor names,
so this counts updates but not construction:

```bash
grep -rnE '(^|[^A-Za-z0-9_.])([a-z][a-zA-Z0-9_]*|\)) \{ *[a-zA-Z_][a-zA-Z0-9_]* *=' \
  --include='*.hs' \
  seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-okf-extension/src | wc -l
```

Expected at baseline: `47`. Substituting the three `test` directories gives `61`.

### Find records that lack `Generic`

Write this helper to the scratch directory (not into the repository) and run it. It walks
each `data`/`newtype` declaration, notes whether the declaration body contains a `{` (making
it a record) and whether `Generic` appears anywhere in the declaration, and prints the ones
that are records without `Generic`.

```bash
cat > /tmp/seihou-check/recgen.awk <<'AWK'
/^(data|newtype) [A-Z]/ {
  if (inrec && isrec && !hasgen) print FILENAME ":" start ": " tname
  inrec=1; isrec=0; hasgen=0; start=FNR; tname=$2
}
inrec && /\{/     { isrec=1 }
inrec && /Generic/ { hasgen=1 }
inrec && /^[^ \t]/ && FNR>start {
  if (isrec && !hasgen) print FILENAME ":" start ": " tname
  inrec=0
}
END { if (inrec && isrec && !hasgen) print FILENAME ":" start ": " tname }
AWK
mkdir -p /tmp/seihou-check
find seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-okf-extension/src \
  -name '*.hs' -print0 | xargs -0 awk -f /tmp/seihou-check/recgen.awk
```

Expected at baseline: 79 lines, beginning

```text
seihou-cli/src/Seihou/Fzf.hs:44: FzfConfig
seihou-cli/src/Seihou/Fzf.hs:79: FzfOpts
seihou-cli/src/Seihou/Fzf.hs:138: Candidate
seihou-cli/src-exe/Seihou/CLI/ValidatePrompt.hs:33: PromptReport
...
```

Expected after Milestone 2: no output.

### Find lazy record fields

This helper tracks whether it is inside a record body and reports every field line without a
`!`. It is the same shape as the previous script, so put it beside it.

```bash
cat > /tmp/seihou-check/fields.awk <<'AWK'
/^\s*(data|newtype) [A-Z]/            { inrec=1 }
inrec && /\{/                          { inbody=1 }
inbody && /^\s*deriving|^\s*$/         { inrec=0; inbody=0 }
inbody && match($0, /[,{]? *[a-zA-Z_][a-zA-Z0-9_']* :: /) {
  total++
  if ($0 ~ / :: !/) strict++
  else print FILENAME ":" FNR ":" $0 > "/dev/stderr"
}
END { print "total_fields=" total "  strict=" strict }
AWK
find seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-okf-extension/src \
  -name '*.hs' -print0 | xargs -0 awk -f /tmp/seihou-check/fields.awk
```

Expected at baseline, on stdout:

```text
total_fields=723  strict=15
```

with 708 lazy-field lines on stderr. Expected after Milestone 2:
`total_fields=723  strict=723` and nothing on stderr.

### Find sum types whose record fields cannot use `#label`

This confirms the three known cases and catches any new ones. It parses each multi-constructor
`data` declaration, collects each constructor's field names, and reports fields that are not
present in every constructor.

```bash
cat > /tmp/seihou-check/sumrec.py <<'PY'
import re, pathlib
roots = ["seihou-core/src","seihou-cli/src","seihou-cli/src-exe","seihou-okf-extension/src"]
for r in roots:
    for p in sorted(pathlib.Path(r).rglob("*.hs")):
        lines = p.read_text().splitlines()
        i = 0
        while i < len(lines):
            m = re.match(r'^data ([A-Z][\w]*)', lines[i])
            if not m:
                i += 1; continue
            tname, start, j, block = m.group(1), i + 1, i + 1, []
            while j < len(lines) and lines[j].startswith((' ', '\t')):
                if lines[j].strip() == '': break
                block.append(lines[j]); j += 1
            ctors = [(cm.group(1), k) for k, b in enumerate(block)
                     if (cm := re.match(r'^  [=|] ([A-Z][\w]*)', b))]
            if len(ctors) > 1:
                info = []
                for idx, (cn, k) in enumerate(ctors):
                    end = ctors[idx + 1][1] if idx + 1 < len(ctors) else len(block)
                    seg = "\n".join(block[k:end])
                    info.append((cn, re.findall(r"[{,]\s*([a-z][\w']*) ::", seg)))
                allf = set().union(*[set(f) for _, f in info])
                if allf:
                    shared = set.intersection(*[set(f) for _, f in info])
                    print(f"{p}:{start}: {tname} ctors={[c for c,_ in info]}")
                    print(f"    NOT_in_all_ctors={sorted(allf - shared)}")
            i = j
PY
python3 /tmp/seihou-check/sumrec.py
```

Expected at baseline and at completion — this output should not change, because these types
are exempt by design:

```text
seihou-core/src/Seihou/Core/Migration.hs:36: MigrationOp ctors=['MoveFile', 'MoveDir', 'DeleteFile', 'DeleteDir', 'RunCommand']
    NOT_in_all_ctors=['dest', 'path', 'run', 'src', 'workDir']
seihou-core/src/Seihou/Core/Types.hs:388: Operation ctors=['WriteFileOp', 'CreateDirOp', 'CopyFileOp', 'RunCommandOp', 'PatchFileOp']
    NOT_in_all_ctors=['command', 'content', 'dest', 'moduleName', 'occurrence', 'op', 'path', 'src', 'strategy', 'workDir']
seihou-core/src/Seihou/Engine/Preview.hs:27: PreviewLine ctors=['FilePreview', 'DirPreview', 'CommandPreview', 'OrphanPreview']
    NOT_in_all_ctors=['previewAnnotation', 'previewModule', 'previewPath', 'previewStatus']
```

(The `PreviewLine` field names change in Milestone 3; the type stays exempt.)

### Per-package build and test

Use these throughout rather than always building everything — they are much faster.

```bash
cabal build seihou-core       && cabal test seihou-core-test
cabal build seihou-cli        && cabal test seihou-cli-test
cabal build seihou-okf-extension && cabal test seihou-okf-extension-test
```

### Format and full check

Run before every commit. `nix fmt` runs `fourmolu` over Haskell sources and `cabal-gild` over
the `.cabal` files, so it will reformat and re-sort anything you edited by hand.

```bash
nix fmt
nix flake check
```

### Commit message shape

Every commit uses Conventional Commits and carries the ExecPlan trailer:

```text
refactor(core): adopt generic-lens label access in the effect interpreters

Replace OverloadedRecordDot field reads with `^. #field` and record
update syntax with lens setters across the pure effect interpreters.
Add the per-module `import Data.Generics.Labels ()` that brings the
generic-lens IsLabel orphan into scope.

ExecPlan: docs/plans/75-adopt-generic-lens-record-conventions-before-1-0-0-0.md
```


## Validation and Acceptance

Acceptance has four parts. All four must hold before the plan is complete.

### 1. The test suite is unchanged in outcome

Capture the example counts at baseline and compare at the end. Behavior must not change, so
the numbers must match exactly.

```bash
cabal test all 2>&1 | grep -E 'examples|Finished'
```

Expected: three suite summaries, each reporting the same number of examples and zero failures
as at baseline. If an example count *drops*, a test was accidentally deleted or a spec file
stopped being discovered — investigate before proceeding. If a test fails, the most likely
causes in order are: an `at`-versus-`ix` mix-up from Milestone 6 changing Map semantics; a
strict field from Milestone 2 forcing a value that was previously never demanded; or a
prefix rename from Milestone 3 that silently changed which field a construction site targets
because two same-typed fields swapped names.

### 2. The convention holds mechanically

Every detection script reports zero hits:

```bash
# no dot access anywhere
grep -rnoE '(^|[^A-Za-z0-9_."])[a-z][a-zA-Z0-9_'"'"']*\.[a-z][a-zA-Z0-9_'"'"']*' \
  --include='*.hs' seihou-core seihou-cli seihou-okf-extension | grep -v dist-newstyle | wc -l
# no record update syntax
grep -rnE '(^|[^A-Za-z0-9_.])([a-z][a-zA-Z0-9_]*|\)) \{ *[a-zA-Z_][a-zA-Z0-9_]* *=' \
  --include='*.hs' seihou-core seihou-cli seihou-okf-extension | grep -v dist-newstyle | wc -l
# no OverloadedRecordDot
grep -rn 'OverloadedRecordDot' --include='*.cabal' --include='*.hs' . | grep -v dist-newstyle | wc -l
# no labels orphan in the prelude
grep -c 'Data.Generics.Labels' seihou-core/src/Seihou/Prelude.hs
```

Expected: `0`, `0`, `0`, `0`.

And the awk scripts report full strictness and no missing `Generic`:

```bash
find seihou-core seihou-cli seihou-okf-extension -name '*.hs' -not -path '*/dist-newstyle/*' \
  -print0 | xargs -0 awk -f /tmp/seihou-check/fields.awk
```

Expected: `total_fields=N  strict=N` with the two numbers equal.

### 3. The enforcement check actually rejects violations

This is the step that proves the guard is real rather than decorative. Break one thing, watch
it fail, put it back.

```bash
# Remove one strictness annotation
sed -i '' 's/{ name :: !VarName,/{ name :: VarName,/' seihou-core/src/Seihou/Core/Types.hs
bash nix/check-record-conventions.sh; echo "exit=$?"
```

Expected: a non-zero exit and a message naming the file and line, in the style of the existing
placement check, for example:

```text
error: record field is not strict
  seihou-core/src/Seihou/Core/Types.hs:116: { name :: VarName,
Every record field must carry a ! annotation. See the "Record Conventions"
section of docs/dev/architecture/overview.md.
exit=1
```

Then restore and confirm it passes:

```bash
git checkout -- seihou-core/src/Seihou/Core/Types.hs
bash nix/check-record-conventions.sh; echo "exit=$?"
```

Expected: `exit=0` and no output.

Confirm it is wired into both entry points:

```bash
nix flake check 2>&1 | grep -i 'record-conventions'
git commit --allow-empty -m 'test: pre-commit hook wiring'   # then inspect hook output
```

### 4. The CLI still scaffolds a real project

Build a fresh binary and run the getting-started scenario in a scratch directory. Use
`HOME` redirection so the run does not touch the developer's real `~/.config/seihou/`.

```bash
cabal build seihou
mkdir -p /tmp/seihou-e2e && cd /tmp/seihou-e2e
export HOME=/tmp/seihou-e2e/home && mkdir -p "$HOME"
SEIHOU=$(cd - >/dev/null && cabal list-bin seihou) && cd /tmp/seihou-e2e

"$SEIHOU" --version
"$SEIHOU" init
"$SEIHOU" new-module my-haskell
"$SEIHOU" run my-haskell
"$SEIHOU" status
```

Expected, in order: a version string with a git hash; the initialization report naming
`config.dhall`, `modules/`, and `installed/`; a `my-haskell/` directory containing
`module.dhall` and `files/README.md.tpl`; a generation report; and a status listing the
generated files against the manifest at `.seihou/manifest.json`.

The `run` step will prompt for the module's declared variables (the scaffolded module
declares `project.name`). Answer them, or pass them with `--var`. If the scaffolded module
references the seihou-schema URL and the machine is offline, `run` will fail at Dhall import
resolution — that is an environment failure, not a regression; note it and rerun with network
access.

Capture the full transcript into this section when the run succeeds.

Clean up afterwards:

```bash
cd / && rm -rf /tmp/seihou-e2e /tmp/seihou-check
```


## Idempotence and Recovery

Every step in this plan is a source edit followed by a build. Nothing writes outside the
repository except the scratch scripts under `/tmp/seihou-check/` and the end-to-end run under
`/tmp/seihou-e2e/`, both of which are disposable and are removed at the end. No migration
runs, no database is touched, and no released artifact is published — the version bump to
1.0.0.0 and the release itself are explicitly *not* part of this plan.

Re-running any detection script is safe and side-effect-free; they only read and count.

Re-running a conversion is safe because every conversion is idempotent in effect: converting
an already-converted site is a no-op, since `record ^. #field` does not match the dot-access
pattern and `record & #f .~ v` does not match the record-update pattern.

Recovery at any point is `git checkout -- <path>` for a single file, or
`git reset --hard HEAD` to return to the last commit. Because every milestone leaves the tree
building and testing green, `git bisect` is a usable tool if a regression surfaces late —
which is the main reason for committing in per-package and per-directory slices rather than in
one enormous commit.

The one genuinely risky milestone is Milestone 2's strictness pass, because it can change
runtime behavior rather than only syntax. If a test starts failing after it, do not debug the
whole pass at once: revert the strictness commit for the failing package
(`git revert <sha>`), reapply it module by module, and rebuild after each to isolate the
field whose strictness matters. Record the finding in Surprises & Discoveries — a field that
cannot be made strict is real project knowledge, and the exemption belongs in the enforcement
script with an inline comment naming the reason.

The second risk is Milestone 6's `at`-versus-`ix` distinction, which is a silent behavior
change rather than a compile error if you get it wrong. The mitigation is to convert one pure
effect interpreter at a time and run its dedicated spec immediately, rather than converting
all six and running the suite once.

If Milestone 0 reveals that the wholesale `module Control.Lens` re-export causes widespread
ambiguity, or that compile times become unacceptable, stop and record the finding in the
Decision Log before proceeding. Both have documented fallbacks: a targeted `hiding` clause on
the prelude's lens import for the first, and reverting to an explicit export list covering
only the operators this plan uses (`^.`, `.~`, `?~`, `%~`, `&`, `at`, `ix`, `_Just`, `to`,
`view`, `over`, `set`) for the second. Either fallback is a deviation from the house style and
must be recorded as such.


## Interfaces and Dependencies

### Libraries

`generic-lens` (currently `>=2.2 && <3`; the local corpus checkout is `2.3.0.0`) supplies the
orphan `IsLabel` instance in `Data.Generics.Labels` that makes `#fieldName` resolve to a lens
over any `Generic` record, and the `HasField` class in `Data.Generics.Product.Fields` that
does the actual generic synthesis. Verify the current released version against Hackage before
adjusting bounds; the existing bounds already admit `2.3.0.0`, so no change is expected.

`lens` (currently `>=5.2 && <6`; the local corpus checkout is `5.4`) supplies the operators
and combinators: `(^.)`, `(.~)`, `(?~)`, `(%~)`, `(&)`, `at`, `ix`, `_Just`, `to`, `folded`,
`view`, `over`, `set`, and the `Lens'`, `Getting`, and `ASetter` types. All of these become
available through `Seihou.Prelude` after Milestone 1.

Note that `Data.Set.Lens (setOf)` is *not* re-exported by `Control.Lens` and must be imported
directly if a site needs it. No current site does.

Both packages must be declared as direct `build-depends` of all three seihou packages after
Milestone 1, because per-module `import Data.Generics.Labels ()` requires a direct dependency
— reaching the module transitively through `Seihou.Prelude` is not sufficient for an import.

### Modules

`seihou-core/src/Seihou/Prelude.hs` is the single shared prelude, imported by 138 of the 157
library and executable modules. After Milestone 1 it re-exports `module Control.Lens` and
must never import `Data.Generics.Labels`. Its module head after the change is shown in
Milestone 1.

`Data.Generics.Labels` is imported — with an empty import list, `import Data.Generics.Labels ()`,
so that only the instance is brought in — by each module that uses `#label`. Use a plain
import, not a `PackageImports`-pinned one: `PackageImports` is reserved for the prelude, and
`generic-lens` is the only package in scope providing a module by that name, so a plain import
resolves unambiguously.

`nix/check-cli-module-placement.sh` is the model for the new
`nix/check-record-conventions.sh`. Read it before writing the new script and match its
structure, its exit-code discipline, its error-message format, and its `EXEMPT_` escape-hatch
pattern.

`nix/pre-commit.nix` gains a second hook entry alongside `cli-module-placement`.
`flake.module.nix` gains a second check derivation alongside `checks.cli-module-placement`.

### Signatures and shapes that must exist at the end

After Milestone 1, `Seihou.Prelude` exports every name that `Control.Lens` exports, in
addition to its existing `Text`, `Map`, `Set`, effectful, `first`, `FilePath`, and `(</>)`
re-exports.

After Milestone 2, every record type in the repository satisfies both
`instance Generic T` (via `deriving stock`) and "every field is strict".

After Milestone 7, no `.cabal` stanza lists `OverloadedRecordDot`, and every stanza lists
`DeriveAnyClass`, `DuplicateRecordFields`, `NoFieldSelectors`, `OverloadedLabels`, and
`OverloadedStrings`.

After Milestone 8, `nix/check-record-conventions.sh` exists, is executable, exits `0` on a
conforming tree and non-zero with a file-and-line diagnostic on a non-conforming one, and is
reachable both from `nix flake check` (as `checks.record-conventions`) and from the
pre-commit hook.

### Explicitly out of scope

The version bump to `1.0.0.0`, the CHANGELOG entry, and the release itself. This plan
prepares the codebase; releasing is separate work with its own tooling (the `seihou-release`
skill).

Tidying the unqualified `import Seihou.Core.Types` workarounds that existed only to bring
GHC's `HasField` instances into scope. Those become unnecessary under `#label`, but removing
them is a separate, independently verifiable change; Milestone 5 records the candidates and
stops there.

Introducing shared Aeson options in the prelude. The house style calls for defining the
project's Aeson options once in the custom prelude, but `Seihou.Manifest.Types` hand-writes
all of its `ToJSON`/`FromJSON` instances rather than deriving them generically, so there is
no shared options value to centralize today. Consolidating the manifest's JSON handling is
real work with real wire-format risk and does not belong in a record-idiom refactor. Record
it as a follow-up in Outcomes & Retrospective.
