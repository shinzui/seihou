# Documenting a registry

A registry repository is a catalogue: `seihou-registry.dhall` at its root lists the modules,
recipes, blueprints, prompts, and judgements the repository publishes, and each artifact's own `.dhall`
file says what it does. That is precise, but it is not something you hand to a colleague who
wants to know what is available and what each thing needs from them.

`seihou-okf-extension docs` turns the registry into a browsable documentation set: one
Markdown page per published artifact, plus one describing the registry itself, with links
between them wherever the artifacts reference one another.

```bash
seihou-okf-extension docs
```

or, through seihou's extension host, when `seihou-okf-extension` is on your `PATH`:

```bash
seihou extension run okf -- docs --dir . --out okf-docs
```

The output is an **OKF bundle** — a directory of Markdown files in the Open Knowledge Format,
each with a block of YAML metadata at the top. Any OKF tool can read it; the `okf` CLI can
validate it, index it, graph it, and query it.

## The output is derived — regenerate it, never edit it

Every page is generated from the `.dhall` sources. An edit you make by hand disappears the
next time anyone runs the command, so the way to change a page is to change the artifact it
describes. Each page records where it came from in a `resource:` field, for example
`seihou://seihou-modules/modules/haskell/nix-haskell-flake`, so a reader can always find the
source. Regenerating an unchanged registry produces byte-identical output, which makes the
bundle safe to commit and to diff in review.

## What ends up on each page

Every page carries the artifact's name, its description, and the version the registry catalog
records. Beyond that, a page shows what its artifact actually declares — and omits the
sections it declares nothing for.

For a **module** (`module.dhall`):

| Section | Comes from |
| --- | --- |
| Dependencies | `dependencies`, with source labels and the variable bindings each edge supplies |
| Variables | `vars` — each declaration's type, requiredness, default, validation rule, description |
| Exports | `exports`, including the alias when one is declared |
| Prompts | `prompts` — the question, its choices, and the condition that gates it |
| Generation steps | `steps` — strategy, source, destination, patch operation, condition, lifecycle |
| Commands | `commands` — the command, its working directory, its condition, application/checkout lifecycle |
| Removal | `removal` — each removal step and the commands that follow |
| Migrations | `migrations` — each `from → to` edge and the operations it performs |

For a **recipe** (`recipe.dhall`): the modules it composes, with the variable bindings it
preconfigures for each, plus its own variables and prompts, optional single base with a
source and version interval, and inherited module and prompt overrides. Inheritance is
documented from the child declaration without fetching or expanding its base.

For a **blueprint** (`blueprint.dhall`): its base modules, the full agent prompt, its
variables and prompts, its reference files, its tool allowlist (`allowedTools`), its agent
launch preferences (`launch`), its version-probe command (`versionProbe`), and its migration
edges with their entailment.

For an **agent prompt** (`prompt.dhall`): the full prompt, its variables and prompts, its
command-derived variables (`commandVars`), its conditional guidance blocks (`guidance`), its
reference files, its tool allowlist, and its launch preferences.

Conditions are shown in the same `when` syntax you wrote them in, for example
``when `Eq nix.treefmt true` ``.

## Entailed migration edges

If a blueprint migration edge declares that crossing it entails crossing an edge of another
blueprint (see [Blueprint migrations](blueprint-migrations.md)), the entailed edge appears
under an `Entails:` heading. When the entailed blueprint is published by the *same* registry,
it is a link to that blueprint's page. When it lives somewhere else — which is the normal
case, and the whole point of entailment — it is shown as labelled text ending in
`(declared outside this registry)`, because there is no page in this bundle to link to.

## Checking the bundle

The generator validates the bundle against the OKF strict authoring rules and against a house
profile — a descriptor saying what a seihou documentation bundle's metadata must carry — and
refuses to write anything if either check fails. It writes that descriptor into the bundle as
`profile.dhall`, so you can re-run the same checks yourself:

```bash
okf validate okf-docs --strict
okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
```

Two more that are worth knowing about:

```bash
okf trust okf-docs                              # who produced each page
okf concepts okf-docs --type SeihouBlueprint    # just the blueprints
okf concepts okf-docs --where tags=migration    # anything tagged migration
```

## Recording a generation date

By default no page carries a date, which is what keeps regeneration byte-stable. If you want
one — a CI job stamping a release date, say — pass it explicitly:

```bash
seihou-okf-extension docs --dir . --out okf-docs --generated-at 2026-09-10
```

The value is recorded verbatim. `okf validate` will then note one advisory per page, saying
the date has no `log.md` to date it against; that is a lint, not a failure.

## Options you are unlikely to need

- `--permissive` validates against OKF's permissive conformance rules rather than the strict
  authoring rules.
- `--profile PATH` checks against your own house profile instead of the built-in one.
- `--no-profile` skips the house-profile check entirely.

The full option list is in [`seihou-okf-extension docs`](../cli/okf-docs.md).

## Declaration coverage inventory

Generation reads declarations only. It does not install dependencies, expand recipe bases,
run generation or migration commands, evaluate command variables or version probes, invoke
agents, or read a consumer's manifest, credentials, model routes or saved judgement policy.
A fresh registry checkout needs only `seihou-okf-extension docs`; after changing declarations,
use `seihou-okf-extension docs --force`. Invalid input or a rejecting profile preserves the
existing output even with `--force`.

The following inventory maps the public declaration records in `Seihou.Core.Types`,
`Seihou.Core.Judgement`, `Seihou.Core.Migration` and `Seihou.Core.Registry` to output.
Decoder spellings such as `when`, `default` and `type` correspond to the internal
`condition`, `default_` and `type_` fields. Catalog metadata controls concept identity and
frontmatter; differing metadata in the artifact itself appears under Declaration metadata.

| Declaration | Fields and output |
| --- | --- |
| Registry | `repoName`, `repoDescription`: overview identity and description; `modules`, `recipes`, `blueprints`, `prompts`, `judgements`: grouped overview links and one concept each |
| RegistryEntry | `name`, `version`, `description`, `tags`: frontmatter and opening text; `path`: `resource` pointer |
| Module | `name`, `version`, `description`: identity metadata; `vars`, `exports`, `prompts`, `steps`, `commands`, `dependencies`, `removal`, `migrations`: corresponding sections; separately decoded `judgements`: Judgements |
| Recipe | `name`, `version`, `description`: identity metadata; `modules`: Composes; `vars`, `prompts`: corresponding sections; `extends`: Extends; `moduleOverrides`: Inherited module overrides; `promptOverrides`: Inherited prompt overrides; separately decoded `judgements`: Judgements |
| Dependency / ModuleRef | `module_` / `name`, `source`, `vars`: dependency row, origin label and supplied bindings; `resolved`: controls a local module link |
| RecipeReference / BaseRecipeRef | `recipe`, `source`, `versionRange.minimum`, `versionRange.before`: Extends; `resolved`: controls a local recipe link |
| RecipeModuleOverride | `module_`, `vars`: Inherited module overrides; no implied additional instance |
| Blueprint | `name`, `version`, `description`, `tags`: identity metadata; `prompt`: Agent prompt; `vars`, `prompts`, `baseModules`, `files`, `allowedTools`, `migrations`, `launch`, `versionProbe`: corresponding sections |
| AgentPrompt | `name`, `version`, `description`, `tags`: identity metadata; `prompt`, `vars`, `prompts`, `commandVars`, `guidance`, `files`, `allowedTools`, `launch`: corresponding sections |
| VarDecl | `name`, `type_`, `default_`, `description`, `required`, `validation`: Variables row |
| VarType / VarValue | Text, Bool, Int, List and Choice types; text, boolean, integer and list defaults: Variables |
| Validation | Pattern, Range (inclusive endpoints), MinLength, MaxLength: Variables |
| VarExport | `var`, `alias`: Exports |
| Prompt | `var`, `text`, `condition`, `choices`: Prompts or Inherited prompt overrides |
| Expr | Lit, Eq, Not, And, Or, IsSet: authored expression syntax on conditional declarations |
| Step | `strategy`, `src`, `dest`, `patch`, `condition`, `lifecycle`: Generation steps |
| Strategy / PatchOp | Copy, Template, DhallText, Structured, Symlink; AppendFile, PrependFile, AppendSection, AppendLineIfAbsent: Generation steps |
| StepLifecycle | Managed: reconciled ownership; Seed: create once, then project owned; Checkout: portable link restored by `seihou sync` in a clone/worktree |
| Command | `run`, `workDir`, `condition`, `lifecycle`: Commands or Removal commands; ApplicationCommand versus repeatable CheckoutCommand setup through `seihou sync` |
| Removal / RemovalStep | `steps`, `commands`; `action`, `dest`, `src`, `condition`: Removal; RemoveFile, RemoveSection and RewriteFile are distinguished |
| Migration / MigrationOp | `from`, `to`, `ops`: Migrations; MoveFile/MoveDir (`src`, `dest`), DeleteFile/DeleteDir (`path`), RemoveLine (`path`, `line`), RunCommand (`run`, `workDir`) |
| BlueprintMigration / EntailedEdge | `from`, `to`, `prompt`, `entails`; `blueprint`, `from`, `to`: Migrations with kind-correct local links or external labels |
| BlueprintFile | `src`, `description`: Reference files |
| AgentLaunch | `provider`, `model`, `effort`: Agent launch with precedence; `mode`: shown as reserved and ignored |
| CommandVar | `name`, `run`, `workDir`, `condition`, `trim`, `maxBytes`: Command variables |
| PromptGuidance | `title`, `body`, `condition`: Guidance |
| JudgementRef / JudgementDocRef | `name`, `source`, `when`: Judgements; `resolved`: controls a local judgement link |
| JudgementDefinition | `name`, `version`, `description`: metadata; `instructions`, `checks`, `evidence`, `limits`, `deterministicChecks`: corresponding sections |
| JudgementCheck | `name`, `question`, `concernWhen`, `yesMeans`, `noMeans`, `categories`, `enforcement`, `blockingSeverity`, `review`, `gate`, `useGate`: Checks |
| Thresholds / FindingCategory | `passAt`, `blockAt`; `name`, `severity`, `description`: per-check review/gate thresholds and category definitions |
| EvidenceDeclaration | `scopes` (StagedChanges, CommitRange), `include`, `exclude`: Evidence |
| CoverageLimits | `maxFileBytes`, `maxChunkBytes`, `maxChunks`, `maxAttempts`, `timeoutSeconds`, `maxFindings`: Coverage limits |
| Judgement enums | Yes/No concern direction, Enforced/Advisory enforcement, Info/Low/Medium/High/Critical severity, SecretScan deterministic check: Checks and Deterministic checks |

Execution records such as `Runnable`, `Operation`, composition/manifest state, migration
plans, judgement policies, observations, findings, evidence indexes and decisions are runtime
outputs, not registry declarations. Documentation includes the authored judgement defaults;
it never claims they are the policy adopted by any consuming project.

A local link requires a matching published artifact of the correct kind and no explicit
external `source`. An explicit source remains labelled text even when a local artifact has
the same name. Missing local names and external bases remain readable without acquisition.
Recipe pages describe the declared child and its inheritance rules, not an expanded
composition. `RemoveLine` removes every exact matching logical line (excluding LF/CRLF
terminators); it preserves nonmatching bytes and is not a substring replacement.

Literal values use code spans with delimiters long enough to contain backticks. Multiline
inline values use labelled JSON string notation, preserving newlines and backslashes. Full
agent prompts and command probes use fences long enough to contain embedded fences.
Judgement thresholds are model-reported probabilities of the concern, not calibrated risk.
