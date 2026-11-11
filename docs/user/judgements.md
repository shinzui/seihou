# Judgements

A judgement checks the staged changes before each commit. It is a list of yes/no
questions, called checks, that Seihou asks a model about the exact content in the Git
index, with optional deterministic checks such as a local secret scan. The model
reports evidence: a probability and located findings. Seihou decides the outcome from
that evidence and the project's recorded policy.

Use a judgement for a concern that a person would otherwise catch in review: committed
credentials, real customer data in fixtures, documentation left out of date. Use a
module or recipe to generate files, and a prompt for an interactive agent session.

## Adopt the built-in security review

Seihou ships `security-review`, which blocks commits that add working credentials or
confidential information. It declares the secret scan, so a credential that gitleaks
recognises blocks before any model sees the change.

```sh
seihou config set judgement.provider claude-cli
seihou config set judgement.model claude-sonnet-5
seihou config set judgement.dataPolicy approved-remote
seihou run security-review --dry-run
seihou run security-review
git add .seihou/manifest.json
git commit -m "chore: adopt security-review"
```

The first three lines choose a review route and record that the project permits
sending staged content to it. Run interactively without `judgement.dataPolicy`,
`seihou run` asks instead. `--dry-run` shows the definition, route, data policy,
scanner, the hook change and each check's thresholds, and writes nothing. Adoption
records the judgement in `.seihou/manifest.json`, which you commit, and installs the
pre-commit hook in this checkout. Gitleaks must be installed (it is in the Nix
development shell); set `SEIHOU_GITLEAKS` to use a specific executable.

From then on `git commit` runs `seihou check --staged`. A blocked commit prints the
judgement, each check's status and probability, the located findings, and what to do.

## How a check decides

A check asks one question. `concernWhen` says which answer is the concern, yes by
default. The model states its probability of yes, and Seihou converts it to the
probability of the concern, taking `1 - p` when no is the concern. Every threshold
applies to that probability, so a higher number is always worse:

| Probability of the concern | Outcome |
|---|---|
| at or above `blockAt` | blocked |
| above `passAt`, below `blockAt` | needs human review |
| at or below `passAt` | may pass |

Equal values remove the needs-review band. A check also blocks on a located finding
whose category's severity, as the author set it, is at or above the check's
`blockingSeverity` (high by default); the model names categories but never chooses a
severity. A model may also ask for human review. Missing, malformed or out-of-range
results, a failed provider call and uncovered files are errors, never passes.

An `Advisory` check reports its real status, marked advisory, without affecting the
exit code. All enforced checks of all active judgements must pass for a commit to
proceed.

The probabilities are stated by the model in its reply. They are not calibrated, and
the same numbers mean different things on a different model. The bundled
`security-review` thresholds were qualified on `claude-cli` with `claude-sonnet-5`
against its 44-case synthetic corpus (`seihou-cli/data/judgements/security-review/examples.json`):
no unsafe case was missed and no benign case was blocked. On any other route they are
unqualified. Use `seihou judgement eval` on your own examples to see where a
route's probabilities fall before trusting a threshold.

## Write a judgement

```sh
seihou new-judgement customer-data-review
```

This creates `.seihou/modules/customer-data-review/judgement.dhall` and a synthetic
`examples.json`. A complete definition with two checks looks like this:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
        sha256:<hash>

in  S.Judgement::{
    , name = "customer-data-review"
    , version = Some "1.0.0"
    , instructions =
        ''
        Review fixtures, logs, and documentation. Synthetic examples are acceptable:
        obviously fake names, example.com addresses and 555 phone numbers. Real
        customer records are not.
        ''
    , evidence = S.JudgementEvidence::{ exclude = [ "*.lock" ] }
    , checks =
      [ S.Check::{
        , name = "real-customer-data"
        , question = "Does this change add information about a real customer?"
        , categories =
          [ S.FindingCategory::{ name = "customer-record", severity = S.Severity.High } ]
        , blockAt = 0.5
        , passAt = 0.1
        }
      , S.Check::{
        , name = "undocumented-export"
        , question = "Do the privacy notes mention every data export this change adds?"
        , concernWhen = S.Answer.No
        , enforcement = S.Enforcement.Advisory
        , blockAt = 0.8
        , passAt = 0.4
        }
      ]
    }
```

This example, with its labelled cases, is in [`docs/examples/judgements/customer-data-review`](../examples/judgements/customer-data-review/); copy that directory to `.seihou/modules/` to try it. The scaffold fills in the real schema URL and hash. A one-check judgement needs only
`name` and `checks`; each check needs only `name` and `question`. The other fields:

| Field | Default | Meaning |
|---|---|---|
| `instructions` | `""` | Shared rubric sent with every check: what is a concern, what is acceptable |
| `evidence.scopes` | staged changes, commit range | Which evidence the judgement may read |
| `evidence.include` / `exclude` | all paths / none | Git-style path patterns (`*`, `?`, `**`) |
| `limits` | 256 KiB per file, 48 KiB per chunk, 16 chunks, 3 attempts, 120 s, 20 findings | Bounds on one review; exceeding one leaves files uncovered, never silently truncated |
| `deterministicChecks` | none | `[ S.DeterministicCheck.SecretScan ]` makes gitleaks hits blocking findings |
| `concernWhen` | `Yes` | Which answer is the concern |
| `yesMeans` / `noMeans` | none | Optional guidance on each answer |
| `categories` | none | Categories findings may use, each with its severity |
| `enforcement` | `Enforced` | `Advisory` reports without blocking |
| `blockingSeverity` | `High` | Findings at or above this severity block |
| `blockAt` / `passAt` | 0.7 / 0.3 | Review thresholds on the probability of the concern |
| `gateBlockAt` / `gatePassAt` / `useGate` | 0.9 / 0.05 / true | Reserved for the judgment-only gate, which this release does not run |

### Examples

`examples.json` holds labelled synthetic cases:

```json
{ "version": 1,
  "examples": [
    { "id": "prod-export",
      "files": [{ "path": "fixtures/accounts.csv", "content": "customer_id,full_name,email\n88123,Margaret Okonkwo-Hale,m.okonkwohale@gmail.com\n" }],
      "expect": { "real-customer-data": "blocked" },
      "findings": [{ "check": "real-customer-data", "category": "customer-record", "path": "fixtures/accounts.csv", "line": 2 }] }
  ] }
```

`expect` maps a check name to `passed`, `blocked` or `needs-review`; a check left out is
not scored on that case. Cases must be synthetic: evaluation sends them to the route,
and validation scans them for credentials first.

### Validate, evaluate, apply

```sh
seihou validate-judgement customer-data-review
seihou judgement eval customer-data-review --offline
seihou judgement eval customer-data-review
seihou run customer-data-review
```

`validate-judgement` names every problem in the definition and the examples before
any model request. `judgement eval` runs the examples through the same program a
commit uses and reports missed unsafe cases, false blocks, undecided cases and
errors per check, with a threshold sweep computed from the same results. Then
`seihou run` adopts the judgement exactly like the built-in one.

## Seihou's own commits and CI

`seihou run`, `seihou update` and `seihou migrate` with `--commit` run every active
judgement on the staged changes, including unrelated files you staged earlier, before
producing a commit message. A generated message is therefore never sent to an AI before
the changes are reviewed. Immediately before `git commit` the index is compared with the
one that was reviewed and reviewed again if it changed. A block leaves the changes
applied and staged and exits nonzero with "Changes applied; commit blocked"; nothing is
rolled back.

In CI, check every commit a change introduces against the policy of its base:

```sh
seihou check --range origin/main..HEAD --policy-ref origin/main --json
```

`--range` inspects each commit, not the net diff, so a secret added and removed inside
the range is still found, and earlier versions of a file are cited as
`path@<commit>`. `--policy-ref` reads the judgements recorded at that ref from Git
objects, so a change cannot weaken the policy it is checked against. Fetch the base
history first (`fetch-depth: 0`); a shallow clone without it is refused. A base with no
adopted judgements has no trusted policy, and first adoption needs explicit review.

## Reference a judgement from a module or recipe

A module or recipe can activate judgements when it is applied:

```dhall
in  S.Module::{
    , name = "service-base"
    , judgements =
      [ S.JudgementRef::{ name = "security-review" }
      , S.JudgementRef::{ name = "docs-review", when = Some "Eq docs.enabled true" }
      ]
    }
```

`seihou run` collects the references of every module in the composition, including
dependencies, and of the applied recipe, keeps those whose `when` holds for that
artifact's variables, and resolves each name through the ordinary search paths and then
the built-in catalogue. The adoption is previewed with the generation plan and needs
the same consent as `seihou run NAME`; it is applied after the files are generated and
before any `--commit`.

## Change policy

A project's thresholds and enforcement are recorded in the manifest when a judgement
is adopted, starting from the authored defaults. Change them with:

```sh
seihou judgement configure customer-data-review --check real-customer-data --block-at 0.6
seihou judgement configure customer-data-review --enforcement advisory
```

Each change is previewed and written atomically; commit the manifest change. Editing
`judgement.dhall` does not change an active judgement: run `seihou run NAME` again to
adopt the edited definition. The manifest keeps a digest of the adopted definition,
and a hand-edited snapshot is refused.

## What is sent, and where

- Only the files in the judgement's scope, as staged, with line numbers, plus the
  instructions and the check's question.
- Nothing gitleaks flags is ever sent, whatever the judgement's subject.
- Every route in this release is a hosted service, including `claude-cli` and
  `codex-cli`, which run in an empty temporary directory with tools, MCP servers,
  slash commands and user settings disabled. No provider-side cache retention is
  requested and no response cache or trace capture is enabled.
- Credentials stay in each provider's own environment or credential store; Seihou
  stores none.

## Limits in this release

- The judgment-only gate is not available, so the generative review decides every
  check.
- `git commit --no-verify` skips the hook. Local hooks cover cooperative development,
  not a process deliberately bypassing them; enforce in CI with
  `seihou check --range origin/main..HEAD --policy-ref origin/main`.
- `seihou install` does not yet fetch a judgement named only by a module's reference
  `source`; install it explicitly first.
