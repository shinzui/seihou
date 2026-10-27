# Seed lifecycle reference for module authors

Seihou 0.11.0.0 delivers runtime seed ownership. Seihou 0.11.0.1 includes
corrected command help. A seed is a whole file created once and then owned
by the consuming project. Omitted lifecycle remains managed.

## Decide by ownership

| Intent or operation | Decision |
|---|---|
| Whole-file starter the consumer is expected to edit and maintain | Seed, when strategy is copy, template or dhall-text and there is no patch |
| File whose future content is maintained by module policy | Retain managed, even if its filename resembles a starter |
| User-maintained extension file, distinct from generated configuration | Usually seed; confirm the module contract and other writers |
| Continuously generated configuration, lock, tooling or integration | Retain managed unless its documented contract explicitly transfers ownership |
| Patch, structured merge or partial contribution to a shared file | Retain managed; seed does not support partial-file ownership |
| Symlink or reproducible checkout declaration | Retain its existing lifecycle; not a seed |
| Arbitrary command output | Adding lifecycle to a step cannot protect it; inspect and adjust the command or report a blocker |
| Unclear intent, incompatible co-owner or overlapping destination | Preserve the declaration and report the specific unresolved decision |

For example, a bootstrap `package.json` that the project maintains can be a
seed, while a policy module's maintained `package.json` is managed. A starter
README can be a seed, while generated reference documentation stays managed.
An append-only `.gitignore` patch stays managed. A user extension can be a
seed while the shared configuration importing that extension stays managed.
Tests and conditional starters need the same intent check as unconditional
application source. Preserve all conditions and bindings.

## Declaration and schema

Use the affected module's existing schema alias. For an old import without
`Step.lifecycle`, this released pin supports the complete declaration:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/7d02695f5a716384ec2174a018c20ee680ab3d13/package.dhall
        sha256:5a24b98eada6628e3e7da267f4e6c31c1e169179d2bacd5fed7254fc4cc55183

in S.Module::{
    , name = "example-starter"
    , version = Some "0.1.0"
    , steps =
      [ S.Step::{
        , strategy = "template"
        , src = "CHANGELOG.md.tpl"
        , dest = "CHANGELOG.md"
        , lifecycle = Some "seed"
        }
      ]
    }
```

Keep a compatible existing schema pin instead of downgrading it. If the
module hand-writes a closed step record type rather than completing
`S.Step`, extend that type and its managed defaults consistently; evaluate
all affected imports. Do not change the ownership default for unrelated
steps. Do not remove an integrity hash to make an import evaluate.

## Observable runtime contract

An absent, unsettled seed is created exclusively. A pre-existing regular
file is kept. Initial occupied directories/symlinks are refused. Settlement
is recorded without content hashes or baselines in `.seihou/manifest.json`.
While the receipt exists, edits and deliberate deletion survive rerun,
force, update and removal, and are excluded from content drift reporting.
Removing the last claim forgets settlement without deleting the object;
later reintroduction may create an absent file again.

Ordinary update releases a formerly managed file to the project without
touching its bytes or deliberate absence. A reverse transition to managed
ownership asks explicitly whether to keep or accept content; force cannot
consent. Mixed lifecycles and overlapping paths are refused. Lifecycle
protects declarative operations, not arbitrary shell commands.

## Acceptance in disposable consumers

Use the module's normal public inputs and supported installation/discovery
workflow. Adapt TARGET and required variables to the actual module or recipe.
For unpublished source, use an isolated candidate installation and identify
it as such; do not claim the public release already contains the changes.

1. Generate from the changed module in an empty consumer using ordinary
   `seihou run TARGET`. Confirm the intended files exist and a seed receipt
   count appears in `seihou status`. Exercise conditional seeds with the
   relevant normal variable values, including disabled conditions.
2. Edit one seed and delete another. Run `seihou run TARGET --force`,
   `seihou status`, `seihou diff` and `seihou update TARGET`. The edit and
   deletion survive; seeds cause no managed drift. An unchanged repeated
   update is a no-op. Managed policy should retain its previous behavior.
3. In a separate consumer, generate from the original module before the
   lifecycle change. Edit a proposed seed and deliberately delete another.
   Make the changed producer candidate available through normal discovery,
   then run `seihou update TARGET --dry-run` and ordinary `seihou update TARGET`.
   The preview includes `release to project`; accepting preserves bytes and
   absence, and another unchanged update is a no-op. No manual manifest or
   dependency repair may prepare this test silently.
4. Inspect representative recipe/dependency composition, including shared
   writers and conditional destinations. No seed may also be managed or
   checkout-owned. Validate the rest of the module's existing checks.

Commit receipts in the consumer's eventual adoption commit so fresh clones
retain settlement and intentional deletion. This blueprint edits producer
sources; it does not migrate other repositories automatically.
