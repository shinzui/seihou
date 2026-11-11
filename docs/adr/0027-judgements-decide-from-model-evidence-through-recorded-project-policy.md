# ADR 0027 — Judgements decide from model evidence through recorded project policy

- Status: Accepted
- Date: 2026-11-11

## Context

Seihou gained judgements: artifacts that check staged changes, or a commit range,
before a commit (plan
[110](../plans/110-add-first-class-user-defined-judgements-backed-by-shikumi.md)). A
judgement asks a model yes/no questions about exact repository content, and its
answer can stop a commit. That makes three things easy to get wrong: who decides
the outcome, what may leave the machine, and what proves a later commit is safe.

The model route is Shikumi, whose decision outputs report a model-stated
probability of yes. These numbers are not calibrated, differ between models, and
are ordinary response content. Gitleaks finds recognisable credentials
deterministically and locally. A project's commits are produced through Git
hooks, through Seihou's own `--commit` paths, and in CI.

## Decision

**The model reports evidence; Seihou's pure policy decides.** A judgement is a
list of checks. Each check is one yes/no question with a declared concern
direction, its own enforcement and its own threshold pair. The runtime adapter
converts the model's probability of yes into the probability of the concern,
once, and every threshold applies to that number. `Seihou.Core.Judgement`
decides each check from it: block at or above `blockAt`, needs review in the
band, pass only at or below `passAt` with complete coverage. A located finding
blocks when its category's authored severity reaches the check's
`blockingSeverity`; the model never chooses a severity. Malformed, missing or
incomplete results are errors, never passes. `seihou-core` has no Shikumi or
transport dependency.

**Policy is project intent recorded in the manifest.** Adoption records the
definition snapshot, a digest of its canonical encoding, the data policy and each
check's effective enforcement and thresholds (manifest schema 15). A check runs
the recorded snapshot, so a newer artifact or binary cannot silently change what
is checked, and a snapshot that no longer matches its digest is refused. The
review route (provider and model) is local configuration and can narrow, never
broaden, what the project permits. Credentials are never stored.

**Transmission requires consent and a local scan first.** Remote review needs a
configured route and an explicit `approved-remote` data policy. Before any
request, gitleaks scans every outgoing file and instruction with its built-in
rules only, ignoring repository allow-lists. Flagged material is never sent. The
scanner has two roles kept apart: as a transmission safeguard it applies to every
judgement on a remote route; as the `SecretScan` deterministic check it produces
blocking findings only for definitions that declare it. Every route in this
release is treated as remote, including local CLI executables, which run in an
empty directory with tools disabled.

**No approval outlives the process that reviewed it.** There is no success
receipt. Seihou's own `--commit` paths gate after staging and before generating
an AI commit message, and recheck the index identity immediately before
`git commit`. The pre-commit hook reviews the final index again. CI checks every
commit in a range, not the net diff, against the policy read from a trusted base
ref's Git objects (`--policy-ref`), so a change cannot weaken the policy it is
checked against.

**Hooks never overwrite what Seihou does not own.** Seihou writes a marked hook
when none exists, preserves an existing hook byte for byte and runs it first, and
installs `pre-commit.legacy` beside a pre-commit framework hook. A
`core.hooksPath` outside the repository is refused.

## Consequences

Thresholds are tied to one route and must be evaluated on that route
(`seihou judgement eval`); documentation calls them model-reported. A commit
through Seihou's `--commit` with the hook installed is reviewed twice, which is
accepted over trusting a cross-process approval. `git commit --no-verify` skips
local enforcement; CI with a trusted base policy is the independent path. Adding
a new deterministic check, evidence scope or judgement field is a schema and
manifest change under [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md).
