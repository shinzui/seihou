# Adopt project-owned seeds in this repository's Seihou modules

Inspect the modules authored in the current repository, identify whole-file
starters that belong to the consuming project after generation, and add
`lifecycle = Some "seed"` to those steps. Implement the justified edits and
validate them; an inventory or a recommendation alone does not finish this task.
Read the bundled `seed-lifecycle.md` reference first. It contains the supported
schema pin, ownership rules and acceptance scenarios for Seihou 0.11.0.0.

## Inspect before editing

Read repository instructions and Git status. Locate authored `module.dhall`
files, their imported step definitions, templates, READMEs, registry entries,
recipes, blueprints, commands, removals and migrations. Follow local imports;
do not assume every module lives under `modules/`. Exclude vendored code,
submodules, installed caches and generated documentation from direct edits.
Do not search the filesystem root or `/nix/store`. Use Mori for dependency
source and documentation lookup where available.

This blueprint has no baseline modules and requires no project variables.
Do not scaffold a consumer project over the author's repository. If this is
only a consumer with no authored modules, explain that existing applications
adopt published seed declarations through `seihou update TARGET`, and change
no module sources. Already-correct modules are a successful verification pass.

For each active or conditional step, establish its destination, strategy,
patch, current lifecycle and intended owner from the actual template and
module documentation. Produce a concise table with module/step, destination,
decision (seed, retain managed, retain checkout, or needs author decision), and
the evidence for that decision. Group identical repetitive steps when useful,
but account for every step. Filename extensions are clues, never the rule.

## Make the ownership change

Convert clear project-owned starters using copy, template or dhall-text with
no patch. Typical examples are application/library/test sources, initial
package descriptions, changelogs, starter documentation, editable API/domain
definitions and user extension configuration. A file with one of these names
may still be deliberately maintained policy; establish intent first.

Retain managed steps for maintained policy, reproducible generated artifacts,
shared tooling and ongoing integration. Preserve checkout declarations and
existing seeds. Patches, structured merges, symlinks and directory outputs
cannot become seeds by adding a field. Do not remove patches or change
strategy to force eligibility. Report a needed redesign and the reason.

Add `lifecycle = Some "seed"` at the individual eligible step or the narrowest
shared constructor that only builds such steps. Preserve step order, `when`,
variables, source/destination expressions, template bytes, dependency bindings
and unrelated author edits. Avoid a blanket default or record override that
silently turns policy steps into seeds. If the old pinned schema lacks this
field, update the affected import and integrity hash using the reference;
retain a compatible existing pin when it already supports seeds. Evaluate
the Dhall and inspect the resulting lifecycle values, including helper-built
and conditional steps, rather than trusting textual insertion.

Check every writer of a converted destination across dependencies, recipes
and differently bound instances. Mixed seed/managed/checkout ownership and
overlapping destinations must be resolved consistently before claiming
success. Never convert another module's policy just to silence a collision.
Audit shell commands as well as declarative migrations/removal: lifecycle
does not sandbox shell commands. A command that overwrites a proposed seed
must be adjusted to preserve project ownership or left as a concrete blocker.
Do not silently delete an existing migration's intended behavior.

Apply unambiguous conversions without asking for approval for each file.
For uncertain ownership, keep the existing declaration and report the exact
question with the evidence needed to decide. Complete the independent safe
changes, and distinguish a partial result from a completed migration.

## Validate and prepare delivery

Require `seihou --version` to report 0.11.0.0 or newer; 0.11.0.1 also corrects
command help. Older runtimes may ignore lifecycle and overwrite files. Do not
invent a minimum-client schema field. Document the minimum runtime in changed
module READMEs and author-facing release notes. Bump each changed module's
published version once using this repository's convention; do not bump
already-migrated modules on repeat runs. Synchronize registry versions with
`seihou registry sync-versions` when a registry exists, update any separately
maintained catalog, and regenerate generated docs with the repository's tool.
Do not edit generated documentation by hand.

Run `seihou validate-module PATH` for every changed module and the repository's
relevant checks. When present, run `seihou registry validate`. Use disposable
consumer directories to exercise fresh generation, edited and deleted seeds,
forced reruns, and ordinary update from the original pre-change declarations.
Preserve original declarations before editing so adoption starts from real
managed state. The reference describes the required observations. Supply only
normal public variables and commands; disclose candidate installation used
for unpublished modules. Do not run the modules against the author's checkout.
Do not fabricate manifests, receipts or generated baselines to make checks pass.

Existing consumers adopt the published module with `seihou update TARGET`,
review `release to project` in its normal preview, accept once and commit the
manifest. Do not prescribe `run --force`, remove/reinstall, a separate manifest
upgrade, hand-edited JSON, or a transitive dependency target list for adoption.

Summarize the classification, exact changed modules/versions, validation
results, unresolved decisions and consumer adoption command. State which
runtime and module candidates were tested and whether publication remains.
Preserve unrelated work and staging. Do not commit, push or publish unless
the invoking user explicitly requests it. A successful agent session or
migration receipt alone does not prove the ownership changes passed validation.
