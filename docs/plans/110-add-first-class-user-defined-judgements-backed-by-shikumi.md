---
id: 110
slug: add-first-class-user-defined-judgements-backed-by-shikumi
title: "Add first-class user-defined judgements backed by Shikumi"
kind: exec-plan
created_at: 2026-10-22T13:38:08Z
intention: "intention_01m5hx8k9heqcsn2ahnmxw9k6w"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-22T13:38:08Z
  revisions:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-11T14:55:35Z
      mode: "update"
      note: "Adopt released Shikumi 0.5 decision outputs for the verdict with a policy threshold band; add Baikai 0.10 upgrade to M1; correct stale Seihou facts and command names"
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-11T15:02:02Z
      mode: "update"
      note: "Generalize judgements to per-check questions with their own thresholds and enforcement; add judgment-only gate with escalation; separate transmission safeguard from secret-scan check"
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T16:17:53Z
      mode: "implement"
      note: "M1 started: Baikai 0.10 upgrade, core policy, Shikumi adapter, staged evidence, scanner, execution and reports"
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T18:25:26Z
      mode: "implement"
      note: "M1 completed: schema, manifest 15, check, hooks, adoption, live consumer run"
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T21:01:40Z
      mode: "implement"
      note: "M4 gate route: baikai-typesafe dependency, gate configuration, production gate runner, eval gate tallies"
---

# Add first-class user-defined judgements backed by Shikumi

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Let a project author define a judgement in Dhall, apply it directly or through a module or recipe, and have Seihou review changes with a typed Shikumi program. A judgement is a versioned description of a question, the evidence it may inspect, and the findings it may return. A gate is the project policy that decides whether those findings permit an action. The first shipped example checks staged changes for secrets and contextually sensitive information before a commit.

The normal adoption command is `seihou run security-review`. Its ordinary preview explains the checks, model/data policy, and proposed Git hook integration. Accepting applies the declaration and prepares this checkout. Afterwards a developer uses ordinary `git add` and `git commit`; `seihou check` runs the same checks explicitly. A fresh clone or linked worktree uses `seihou sync` once to restore checkout setup from the manifest. Required checks also run inside Seihou's commit-producing commands before any AI commit-message request. Teams can run `seihou check --range BASE..HEAD` in CI without depending on local hooks.

Users author their own judgements without recompiling Seihou. The initial authoring surface uses one common typed evidence/finding contract, configurable instructions and categories, and labelled evaluation examples. It does not promise arbitrary user-defined Haskell types or load executable plugins.

Integrate directly with Shikumi. There is no Handan package, binary, protocol, or release dependency. Keep Shikumi types and provider details behind a Seihou-owned runtime adapter so further upstream capabilities can be adopted without changing the project artifact format.

Security review is the first example, not the shape of the feature. A judgement is a list of checks. A check is one author-written yes/no question about the evidence: "does this change add a credential?", "does this migration drop a column without a backfill?", "does this change include tests for the behaviour it adds?". The author states which answer is the concern, so a question may be asked in whichever direction reads naturally; in the first two a yes is the concern, in the third a no. Each check has its own thresholds and its own enforcement, because a leaked credential and a missing changelog entry do not deserve the same caution. Nothing in the domain types, report format, command names or policy logic refers to secrets; the secret scanner is one declared deterministic check and one transmission safeguard, described below.

Each check is answered as a Shikumi decision output. A decision output is a typed answer that carries the probability the model assigned to it instead of a bare value. Shikumi released these in 0.5.0.0. Seihou converts it to the probability of the concern, which is the reported probability of yes or its complement according to the check's declared direction, and compares that with the check's two thresholds recorded in project policy: at or above the upper one the check blocks, at or below the lower one it may pass, and in between it asks for human review. The located findings that explain a block remain ordinary typed output of the same call.

A project may also configure a fast gate. A gate is a judgment-only model, one that answers closed questions and nothing else, such as TypeSafe's Jev. It answers each check first. A check the gate clears needs no further call; a check it does not clear is escalated to the generative model, which gives the located findings and the deciding probability. Ordinary benign commits then cost one fast call per check and reach one provider. On a generative model the probability is the model's own stated estimate, not a measured frequency, so thresholds are only meaningful for the provider/model route they were evaluated on.


## Progress

- [x] M1: Seihou builds on the Baikai 0.10 line that Shikumi 0.5.1.0 requires; a thin real-consumer path then applies a judgement, runs a typed Shikumi review whose checks are probability-backed decisions, and blocks an ordinary commit; the required adoption and hook steps are demonstrated before expanding variants. (2026-11-11; the live gate run was not exercised, see the M1 record below.)
- [x] M2: Authors can scaffold, validate, discover, install, compose, and evaluate custom judgement artifacts without rebuilding Seihou; the schema is available at a published immutable import. (2026-11-11; schema `9080a47`. Exception, carried as open work: `seihou install` does not yet acquire a judgement named only by a reference `source`.)
- [ ] M3: The manifest records portable active declarations and project policies, and run/update/remove/sync preserve ownership, migration, and fresh-checkout behavior.
- [ ] M4: Staged and commit-range evidence, deterministic secret detection, the direct Shikumi adapter with per-check decisions, threshold bands and the optional judgment-only gate with escalation, coverage accounting, and redacted results satisfy the security contract.
- [ ] M5: Ordinary Git commits, Seihou commit-producing paths, and CI share the same gate semantics, with tested hook coexistence and no pre-gate AI transmission.
- [ ] M6: Help, authoring documentation, evaluation examples, source-build acceptance, and package checks demonstrate both built-in and user-authored workflows.
- [ ] M7: Released schema and Seihou artifacts, the packaged scanner dependency, and an installed executable pass the normal workflow in an existing consumer, an empty-cache clone, and a linked worktree.

M1 record (2026-11-11, claude-opus-5-5). Commits: Baikai 0.10 upgrade `2998d83`; policy domain `98a33bf`; Shikumi adapter `5eb2beb`; staged evidence, Gitleaks and execution `ea95ace`; reports `8325111`; Judgement schema published as `mori://shinzui/seihou-schema` `50fa7bb` and decoded in `9a0395d`; manifest schema 15 `27f9dc9`; `seihou check`, hooks and adoption `460ea4c`. Source checks: core 1750, okf-extension 54 and cli 954 tests passed after `27f9dc9`'s content; the judgement specs passed again after the final hook change.

The real consumer was a disposable `git clone --local` of Seihou at `23b9058`, with manifest schema 10 and the Nix-managed pre-commit framework hook installed by its own `nix develop` (`core.hooksPath=.git/hooks`). The executable was the source build from `cabal list-bin seihou`, copied onto the front of PATH, reporting `seihou v0.15.0.0`. Preparation, counted separately from the developer commands: Gitleaks 8.30.1 from the dev shell; route and consent through `SEIHOU_JUDGEMENT_PROVIDER=claude-cli`, `SEIHOU_JUDGEMENT_MODEL=claude-sonnet-5` and `SEIHOU_JUDGEMENT_DATA_POLICY=approved-remote` in an isolated `XDG_CONFIG_HOME`; an authenticated `claude` CLI. There were no prompts and no manual edits. Developer commands and results:

```text
seihou run security-review     # previewed; installed .git/hooks/pre-commit.legacy beside the
                               # framework hook (left byte-identical); manifest 10 -> 15, adding
                               # only judgements and null recipeChain/recipeInputs evidence
git commit (the manifest)      # judgement passed (0.02 / 0.05), then Seihou's own hooks passed
git commit (README change)     # judgement passed (0.00 / 0.02), then Seihou's own hooks passed
git commit (ghp_ fixture)      # exit 1: "tmpfix/env.sh:1 critical github-pat (deterministic
                               # secret-scan)", "no request was sent", token absent from output
```

In a scratch repository the bundled definition blocked a synthetic CRM export (`confidential-data` 0.97, four located findings, exit 10), and a project judgement `docs-review` was adopted from `.seihou/modules/docs-review/judgement.dhall` with `seihou run docs-review` and checked with `seihou check docs-review`. That judgement is not about security. Its enforced no-concern check reported 0.65 (needs review, with a located `missing-example` finding), and its advisory check reported a 0.90 block that did not decide the exit code (exit 11).

Not exercised in M1: the live judgment-only gate, because `TYPESAFE_API_KEY` is unset and `baikai-typesafe` is not yet a dependency (gate thresholds, escalation and clearance are covered only by stubs), and a noninteractive first adoption in a project that has no route configured (it is covered by specs, which check the exact `seihou config set` lines). Next: M2 (artifact references from modules and recipes, `new-judgement`, `validate-judgement`, `judgement eval`, `judgement configure`), then M3 (application owners, removal, sync).

Post-M1 record (2026-11-11, claude-opus-5-5). Committed after M1: authoring commands `c8cda9b` (`new-judgement`, `validate-judgement`, `judgement eval` with a threshold sweep, `judgement configure`); documentation `627f670` and `8ba2f9d` (CLI references, the judgements guide, help topics, [ADR 0027](../adr/0027-judgements-decide-from-model-evidence-through-recorded-project-policy.md)); registry, install, list, browse, outdated and upgrade support plus the ambiguous co-located artifact error `2e803b6`; commit ranges, `--policy-ref` and the commit gate for `run`/`update`/`migrate` `3a0c319`; and module and recipe references with schema `mori://shinzui/seihou-schema` `9080a47` in `593a1a8`. Suites after `593a1a8`: core 1767, cli 978, okf-extension 54.

Live evidence on `claude-cli`/`claude-sonnet-5`: `judgement eval customer-data-review` scored `real-customer-data` 3/3 (0.02, 0.90, 0.02) and `undocumented-export` 1/1 in 41 seconds. `seihou check --range main..HEAD` blocked a credential that was added and then removed inside the range (the net diff was empty) with no request sent. `seihou run demo --commit`, applying a module whose output contained a synthetic token, exited 10 with "Changes applied; commit blocked". It made no commit and zero AI calls, and the token was absent from the output. A module reference with a false `when` adopted nothing.

Open items by milestone (updated after `7b63cd8`):
- M2: `seihou install` does not acquire a judgement named only by a reference `source` (the ADR 0020 closure). `browse` has no kind filters for any artifact kind. Shell completion has no name completers for any kind.
- M3, done in `3bebe24`: application and direct owners, conflict refusal, last-owner retirement with removal of a byte-identical hook, `sync` hook repair, and judgement status. Not exercised: a linked worktree and a fresh clone with an empty artifact cache. `remove` of an application whose module lacks a removal specification is refused by existing rules, so the pruning path is covered by specs only.
- M4: the gate route is wired (see the gate record below), but no `TYPESAFE_API_KEY` was available, so no gate probability, latency, accepted input size or oversized-input refusal has been observed. Checks run sequentially.
- M5: `run --commit` is verified live, and `update` and `migrate` share the same `gatedCommit` helper but were not run live. A staged policy weakening is reported in `70df8ad`, and `--policy-ref` covers CI.
- M6: corpus and qualification are done in `7b63cd8`, and docs, help and the OKF rendering (`5b90232`) are in place. The non-security example `docs/examples/judgements/customer-data-review` ships with labelled cases: two checks at different thresholds, one advisory and asked in the no-concern direction, scored 3/3 and 1/1 live.
- M7: not started; release needs publication authorization.

Gate record (2026-11-11, claude-opus-5-5). `baikai-typesafe` 0.1.0.1 and `typesafe-hs` 0.1.0.0 are now dependencies of the internal CLI library, pinned in `nix/haskell-overlay.nix`. `judgement.gateProvider`/`judgement.gateModel` (or `SEIHOU_JUDGEMENT_GATE_PROVIDER`/`SEIHOU_JUDGEMENT_GATE_MODEL`) select the gate, and `judgement configure --gate-provider/--gate-model` writes them. A judgment-only catalogue model is refused as the review route, and anything else as the gate. `productionGateRunner` registers `typesafeProvider` on its own registry. `check`, `check --dry-run`, adoption and `judgement eval` name the gate, and eval reports per check how many unsafe and benign cases the gate cleared or escalated, marking a gate that clears an unsafe case as not qualified. Suites: core 1772, cli 983, okf-extension 54. Live, in a scratch repository on `claude-cli`/`claude-sonnet-5` with `typesafe jev-latest` and no key: the adoption preview named both destinations and recorded `gatePermitted`, and `seihou check` on a README change passed in 5.9 s. Each check reported "gate unavailable (the provider reported an error ...); escalated to review" and was decided by the review (0.00 and 0.02). Four requests were observed in total: two failed gate calls and two reviews.

The original plan authorized planning only; implementation began on 2026-11-11 at the user's request. The intention was created with `mina ci --json 'Add first-class user-defined judgements backed by Shikumi'`. Mina returned the frontmatter ID successfully and warned that its configured default parent is outside this project's Rei scope; changing that project association is separate from creating this plan.

Revision note (2026-11-11): reviewed against the working tree and the current Shikumi and Baikai releases; no implementation has started. Shikumi 0.5.0.0 and 0.5.1.0 shipped probability-backed decision outputs, so the verdict is now a decision with a project-owned threshold band instead of a model-chosen status. Shikumi 0.5.1.0 requires Baikai 0.10, while Seihou still builds against Baikai 0.8, so M1 now starts with that upgrade. Stale facts about Seihou's own version, manifest schema, schema pin and ADRs were corrected, and the authoring commands were renamed to match the existing `new-*` and `validate-*` commands. Details are in Surprises & Discoveries and the Decision Log.

Revision note (2026-11-11, second): at the user's direction the design was generalized beyond security and the fast gate was added. A judgement is now a list of checks, each with its own question, thresholds and enforcement. A judgment-only model may gate each check and escalate to the generative review, which adds `baikai-typesafe` and a second route to qualify. The secret scan was split into a transmission safeguard that applies to every remote request and a deterministic check that only definitions declaring it treat as a finding.

Revision note (2026-11-11, third): at the user's direction each check now declares which answer is the concern, replacing the fixed yes-means-concern convention.


## Surprises & Discoveries

Discovery (2026-11-11): The decision capability this plan treated as future work is released. Hackage lists `shikumi` 0.5.0.0 and 0.5.1.0, and upstream tag `shikumi-0.5.1.0` resolves to `7b96ecf06364b37de44b15c4f58b2528b5a3e0f5`. `mori://shinzui/shikumi/masterplans/12-support-typesafe-jev-and-probability-backed-decision-outputs` records all four child plans Complete. Shikumi's capability record marks the feature `shipped` with stability `experimental`.

Discovery (2026-11-11): Decision types cannot express author-defined categories or per-finding verdicts. Their domains are compile-time Haskell types (`Choice a` over an enum, `Score` over type-level labels), and decisions nested in lists or maps are unsupported. A judgement's categories come from Dhall at run time and its findings are a list. Only a fixed top-level yes/no decision fits; categories and findings stay ordinary typed output.

Discovery (2026-11-11): A judgment-only model cannot produce findings. Baikai's TypeSafe System One provider (`mori://shinzui/baikai/packages/baikai-typesafe`, model `typesafe_jev_latest`) answers only closed questions and refuses free-form output fields, system prompts, tools and every generation control before dispatch. It can return the verdict probability but not a file and line.

Discovery (2026-11-11): Seihou is two Baikai major lines behind what Shikumi needs. `seihou-cli/seihou-cli.cabal` and `nix/haskell-overlay.nix` pin `baikai ^>=0.8.0.0`; `shikumi` 0.5.1.0 requires `baikai >=0.10.0.0 && <0.11`, `baikai-claude` and `baikai-openai` `>=0.7.3.0`, and `baikai-effectful >=0.4.0.5 && <0.5`. Baikai 0.9.0.0 and 0.10.0.0 both carry breaking changes to public sums and records, and eight existing Seihou agent modules import Baikai. Hackage also lists `baikai-effectful` 0.5.0.0, which Shikumi 0.5.1.0's bound excludes.

Discovery (2026-11-11): The plan's Seihou facts had drifted. Seihou is at 0.15.0.0, not 0.10.1.0. The manifest schema is 14, not 10. The recorded `schema` submodule commit is `e9f91438f081fba90f40f987de93df9f74c7117d`, matching `Seihou.CLI.SchemaVersion`, and the working tree currently holds an uncommitted advance of that submodule to `d3c78cd81d9697ebff3128732ec673a17e65c73f`. ADRs 0019 to 0025 were added after the plan was written.

Discovery (2026-11-11, implementation): the Baikai 0.8 to 0.10 upgrade was mechanical. The library and executable compiled unchanged; only the trace fixtures in `seihou-cli/test/Seihou/CLI/AgentTraceSpec.hs` needed Baikai 0.9's new `structuredData` field. Baikai 0.10.1.0 still hardcodes `/bin/ps`, so the overlay patch remains. No separate upgrade plan was needed.

Discovery (2026-11-11, implementation): Shikumi's offline test harness (`shikumi-testing`) is not published to Hackage. The adapter therefore exposes a `Runner` newtype, the same boundary production uses, and its tests interpret Shikumi's `LLM` effect directly with a stub that returns a fixed Baikai response. Without routing, Shikumi takes its prompt-fallback path and still decoded a reply mixing a `Noul` with a list of finding records.

Discovery (2026-11-11, implementation): Gitleaks 8.30.1 (nixpkgs) supports `gitleaks dir` with `--config`, `--gitleaks-ignore-path`, `--ignore-gitleaks-allow`, `--redact` and `--report-path`. Its default `github-pat` rule detects a synthetic `ghp_` token, and reports its line, after 4,100 bytes of padding. A configuration that only sets `[extend] useDefault = true` keeps exactly the built-in rules.


Discovery (2026-11-11, implementation): the plan's stated schema-submodule state was wrong. The checkout at `d3c78cd` was an ancestor of the recorded `e9f9143`, detached since 2026-10-28 with no local changes, not an advance belonging to other work. It was moved to `origin/master` before authoring the Judgement schema.

Discovery (2026-11-11, implementation): `flake.nix` pins `seihou-schema-src` by GitHub revision, not by `git+file:./schema` as the `update-seihou-schema` skill says, so the revision must be edited by hand before `nix flake update seihou-schema-src`. Recorded as FRIC-14.

Discovery (2026-11-11, implementation): Shikumi delivers attempt receipts only for requests that carry an evidence request. Without `Shikumi.LLM.Defaults.withEvidenceRuns`, the observer never ran and every report claimed no request was sent. The runner now attaches a best-effort evidence request, so reports name the observed model and request count.

Discovery (2026-11-11, implementation): this repository sets `core.hooksPath` to `.git/hooks` (git-hooks.nix does), and its `pre-commit` hook is generated by the pre-commit framework. A rule refusing any `core.hooksPath` would have refused Seihou itself. The hook service refuses only a hook directory outside the repository's Git directory and worktree, and installs `pre-commit.legacy` beside a framework-generated hook, which the framework runs first and keeps when it regenerates its own hook.

Discovery (2026-11-11, implementation): first live probabilities on `claude-cli` with `claude-sonnet-5` (Seihou's catalogue name), using the bundled `security-review` definition. A benign README change gave `credentials` 0.00 and `confidential-data` 0.02, and passed in 7 seconds. A synthetic CRM export with names, personal emails, phone numbers and "exported from prod CRM" notes gave `credentials` 0.03 and `confidential-data` 0.97, with four located `customer-record`/`personal-data` findings on lines 2 and 3, and blocked (exit 10) in 12 seconds. The gate could not be run live: `TYPESAFE_API_KEY` is not set and `baikai-typesafe` is not yet a dependency.


Discovery (2026-11-11, implementation): qualification of the bundled `security-review` on `claude-cli`/`claude-sonnet-5` with its 44-case release corpus (`seihou-cli/data/judgements/security-review/examples.json`, 22 benign and 22 unsafe). The unsafe cases are fake credentials, contextual confidential data, and instruction-injection attempts; the benign ones include synthetic fixtures, placeholders, public keys, a removed secret and a benign injection attempt. Both checks were 33/33 correct, with 0 missed unsafe cases, 0 false blocks, 0 undecided and 0 errors. The scanner stopped 8 of the 11 credential cases before any request. The highest probability on a benign case was 0.15 (`localhost-db`, `credentials`); the lowest on an unsafe case was 0.80. Mean latency was 6.7 s per example. The provisional thresholds (credentials 0.20/0.60, confidential-data 0.30/0.70) therefore meet M6's rule on this route, with margin. The gate was not qualified, because it cannot run in this build.


Discovery (2026-11-11, implementation): the release corpus has to contain credential-shaped strings. In `examples.json`, one character of each token is a JSON `\u` escape, so the decoded cases are unchanged while the raw bytes do not match pattern scanners that read raw text, such as GitHub push protection. Gitleaks decodes escapes and still finds them: a project that adopts `security-review` would block a commit that changes this file, which is the intended behaviour for such a project.


## Decision Log

Decision (2026-10-22): Depend directly on Shikumi through a Seihou-owned adapter; exclude Handan. The user explicitly requested this boundary because Shikumi will gain more capabilities. Neither future Shikumi decision APIs nor a separate judgement-host release may block the initial generative implementation.

Decision (2026-10-22): Make judgements separate declarative artifacts, with references from modules and recipes, rather than generation strategies or ordinary shell commands. File generation and one-time application-command receipts cannot represent a check whose answer depends on each new staged snapshot.

Decision (2026-10-22): Separate validated findings, execution/coverage status, and deterministic project enforcement. A successful model call is not approval. Missing evidence, malformed output, a runtime failure, and a request for human review cannot become an enforced pass.

Decision (2026-10-22): Store resolved active definitions and ownership in the single portable manifest. A check in a fresh clone must not need an artifact cache, reapplication, or a silently newer rubric. Store run observations only in ignored local reports, never as durable proof that future commits are safe.

Decision (2026-10-22): Put local secret detection before any remote review or AI commit-message generation. Default reporting and tracing omit raw evidence and free-form model content that has not passed output sanitization. Remote review requires an explicit project data policy and a locally configured permitted route.

Decision (2026-10-22): Ship the security example with the Seihou distribution, using the same artifact decoder and judgement contract as custom artifacts. This makes adoption one command without requiring a separate registry installation. The bundled definition carries its real Seihou repository origin and release version; it is not a new weak artifact identity.

Decision (2026-11-11): Express the verdict as one Shikumi `Noul` decision and let Seihou's policy apply a two-threshold band to its probability. This supersedes the 2026-10-22 statement that decision outputs are not a prerequisite. The model no longer chooses pass or block; it reports evidence, and a pure function in `seihou-core` decides. The band gives needs-human-review a defined meaning instead of relying only on the model volunteering uncertainty. Seihou reads the raw probability and ignores Shikumi's locally derived Boolean, so no Shikumi `Params` setting becomes part of project state.

Decision (2026-11-11): Keep categories and located findings as ordinary typed output beside the decision, in one mixed-output call. Shikumi supports mixing decisions and free-form fields on generative models. `Choice` and `Score` are not used, because their domains are fixed at compile time and categories are authored at run time.

Decision (2026-11-11): Qualify only generative routes in this delivery and refuse judgment-only models at configuration with a named diagnostic. A block without a file and line is not an acceptable security finding, and a two-call design (fast verdict, then generative explanation) doubles the transmission surface before either route has been evaluated. `baikai-typesafe` is therefore not a dependency. A verdict-only fast gate remains a possible later extension of the runtime adapter.

Decision (2026-11-11): Thresholds are authored defaults in the judgement definition, overridable in project policy, and recorded in the manifest as policy. A deterministic scanner block and a blocking located finding each block regardless of probability; the band can only withhold a pass, never grant one against other evidence. Default numbers are not fixed in this plan: M1 records observed probabilities on the first route and M6's corpus must justify the released defaults.

Decision (2026-11-11): Leave automatic threshold fitting out of this delivery. Shikumi's ReAnchor optimizer (`mori://shinzui/shikumi/packages/shikumi-optimize`) can fit decision settings, but a forty-case corpus is thin for its held-out fold check and it would add a dependency for a proposal the author must still review. `judgement eval` instead reports how each case would have been decided across a sweep of thresholds from one run, which costs no extra model calls.

Decision (2026-11-11): Model a judgement as a list of checks, each a yes/no question with its own thresholds and enforcement, and run one decision per check. The user requires that security not be the only use case and that different concerns carry different thresholds. One probability per review cannot do that. Shikumi's decision fields are compile-time, so a run-time list of questions cannot share one typed reply; each check is therefore its own call of the same fixed program, with the question in the run-time instruction. This supersedes the single-verdict decision above. The cost is one call per check per evidence chunk, bounded by declared limits and shown in the dry-run. A request to `mori://shinzui/shikumi` for run-time-declared decision sets could later collapse the checks into one call behind the same artifact contract; filing it is outside this plan.

Decision (2026-11-11): Use one convention for every check: yes means the concern is present. Authors phrase the question accordingly. This keeps the band one-directional and the policy function small; a per-check polarity switch is not added. Superseded the same day by the next decision.

Decision (2026-11-11): Give each check a declared concern direction, at the user's direction. A check states whether a yes or a no answer is the concern, defaulting to yes. The runtime adapter converts the model's probability of yes into a probability of the concern, taking the complement when no is the concern, before anything else sees it. Thresholds, policy, reports and evaluation are all expressed on the concern probability, so the band stays one-directional and `decideCheck` does not know about direction. The same conversion applies to the gate.

Decision (2026-11-11): Support a judgment-only gate with escalation, at the user's direction. This supersedes the decision to refuse judgment-only models. The gate has its own threshold pair per check, because its probabilities and a generative model's are not comparable. At or below the gate's pass threshold the check is cleared without a second call. Otherwise the check escalates and the generative review decides, except that a gate probability at or above the gate's block threshold forbids a pass: disagreement between the two models yields needs-review, never a pass. A gate that fails at run time is reported and the check escalates, since the generative route is the complete review and is already a permitted destination. A judgment-only model is still refused as the generative route.

Decision (2026-11-11): Separate the transmission safeguard from the secret-scan check. Scanning outgoing material for credentials before any remote request is project data policy and applies to every judgement on a remote route, whatever its subject. Treating scanner hits as blocking findings is a deterministic check that a definition declares; the bundled security definition does, a documentation-freshness judgement would not. When the safeguard stops a transmission for a judgement that does not declare the check, the affected checks end as errors naming the file, not as findings.

Decision (2026-11-11, implementation): Whether a finding blocks depends on its category's authored severity. A check declares `blockingSeverity` (default high), and a finding blocks when its category's severity is at or above it. The model names a category but never chooses a severity. This makes "a blocking located finding" concrete without a per-finding model verdict.

Decision (2026-11-11, implementation): Staged evidence comes from one `git diff-index --cached --raw -z --no-renames --full-index` call against `HEAD`, or against the empty tree before the first commit. Blob bytes come from `git cat-file blob`, and the snapshot identity is a digest of `git ls-files --stage -z`. A rename appears as a deletion plus an addition. Deleted and pre-change content is never transmitted, so it is not scanned for staged checks. Blocking on it would also stop a developer from deleting a secret that is already committed. Range checking (M4) must still scan every introduced commit.

Decision (2026-11-11, implementation): CLI review routes run in a private empty temporary directory. `claude` gets `--tools "" --strict-mcp-config --disable-slash-commands --setting-sources ""`, and `codex` gets `--sandbox read-only --skip-git-repo-check`. This is how the plan's rule that the reviewer has no tools or agent loop is applied to local CLI providers. API routes need no such flags. `baikai-typesafe` is not yet a dependency. The gate path is generic over a `Runner`, and registering the TypeSafe provider is left to the route configuration work.

Decision (2026-11-11): Name the authoring commands `seihou new-judgement` and `seihou validate-judgement`, matching `new-module`, `new-recipe`, `validate-module` and the other existing artifact commands. `eval` and `configure` have no existing counterpart and stay under the `seihou judgement` group.


Decision (2026-11-11, implementation): the Judgement schema uses flat `blockAt`/`passAt` and `gateBlockAt`/`gatePassAt` fields on each `Check`, matching the plan's example and the `configure` flag names, with provisional defaults of 0.7/0.3 and 0.9/0.05. Published as `mori://shinzui/seihou-schema` commit `50fa7bb`. Module and recipe judgement references are left to M2, so this schema commit touches no existing type.

Decision (2026-11-11, implementation): the bundled `security-review` definition is a self-contained, already-normalized Dhall record with no schema import, at `seihou-cli/data/judgements/security-review/judgement.dhall`. `seihou run security-review` therefore evaluates it offline, through the same decoder as custom artifacts. A test decodes and validates it. Its origin is recorded as `BundledJudgement`, not as a weaker artifact identity; the definition version and digest identify what was adopted.

Decision (2026-11-11, implementation): manifest schema 15 adds `judgements`: per active judgement, the source, the definition snapshot, its digest and the policy. The 14 to 15 step is lossless and accepts an empty list, following the existing checkout-commands step. A snapshot whose digest no longer matches its definition, or a policy that does not name exactly the definition's checks, fails to decode with a re-apply instruction. `seihou update` now stages to the newest capability, so it keeps bringing a manifest to the current schema. Application owners for judgements are not recorded yet; that is M3.

Decision (2026-11-11, implementation): the review route is local configuration, not project intent: `judgement.provider` and `judgement.model` (or `SEIHOU_JUDGEMENT_PROVIDER`/`SEIHOU_JUDGEMENT_MODEL`), with no fallback to `agent.*` and no guessed model. Consent to transmit is `judgement.dataPolicy approved-remote` (or `SEIHOU_JUDGEMENT_DATA_POLICY`), or an interactive confirmation during `seihou run`. Without a route, a policy or Gitleaks, adoption names the exact commands and activates nothing. A local-only policy is refused at adoption because no route in this release is local, so such a judgement could never pass. These keys stand in for `seihou judgement configure` until M2.

Decision (2026-11-11, implementation): the gate route is local configuration, like the review route: `judgement.gateProvider` and `judgement.gateModel`. Whether a gate may be used is project policy (`gatePermitted`). Adoption records it as permitted only when a gate route is configured, and its preview and consent prompt then name the gate as a second hosted destination. Afterwards, `judgement configure NAME --gate-provider/--gate-model` permits it, and `--no-gate` withdraws it, each as a previewed manifest change. A configured gate runs only for judgements whose policy permits it, so a local route can narrow but never broaden. The gate is identified by Baikai's `isJudgmentOnly` catalogue fact, not by provider name. When `TYPESAFE_API_KEY` is unset, the gate label says so, because the provider's own error is deliberately generic.

Decision (2026-11-11, implementation): adoption publishes the hook first and the manifest second. A hook with no active judgement passes, so a failed manifest write never leaves a partial active policy. The hook resolves `seihou` from PATH and stops the commit when it is missing.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell CLI with pure/domain logic in `seihou-core`, reusable CLI services in `seihou-cli/src`, and parsers/dispatchers in `seihou-cli/src-exe`. `seihou-core/src/Seihou/Core/Types.hs` defines generation `Step`, post-generation `Command`, runnable artifacts, application ownership, and the manifest domain. A `Step` requires a source, destination and file strategy. `Seihou.CLI.CommandExecution.planCommands` in `seihou-cli/src/Seihou/CLI/CommandExecution.hs` can skip ordinary commands after a successful receipt, which is inappropriate for repeated judgement gates.

`seihou-core/src/Seihou/Core/Module.hs` discovers modules, recipes, blueprints, and prompts. Its standard search roots are `.seihou/modules`, the user's configuration modules directory, and the install cache. `seihou-core/src/Seihou/Core/Registry.hs` defines registry entries, name collisions, repository discovery and validation. `seihou-core/src/Seihou/Core/Install.hs`, `seihou-cli/src/Seihou/CLI/InstallShared.hs`, and `seihou-cli/src-exe/Seihou/CLI/Install.hs` implement installation. `seihou-core/src/Seihou/Dhall/Eval.hs` decodes artifacts; do not add a parallel untyped configuration reader.

The `schema` directory is a Git submodule owned by `mori://shinzui/seihou-schema`. On 2026-11-11 its recorded commit is `e9f91438f081fba90f40f987de93df9f74c7117d`; the working tree holds an uncommitted advance to `d3c78cd81d9697ebff3128732ec673a17e65c73f` that belongs to other work. Start from whatever is recorded when implementation begins. Its project-relative `package.dhall`, `Module.dhall`, and `Recipe.dhall` are exposed here as `schema/package.dhall`, `schema/Module.dhall`, and `schema/Recipe.dhall`. A file-level Mori URI for the schema sources is pending; use the canonical project URI together with these relative paths in cross-repository work. Registry decoding is currently implemented in Seihou rather than a `schema/Registry.dhall` file. The immutable schema URL/hash for scaffolds lives in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`; `flake.nix`, `flake.lock`, and `nix/haskell-overlay.nix` also participate in schema consumption. Updating only the local submodule does not deliver a usable authoring import.

`seihou-core/src/Seihou/Manifest/Types.hs`, `seihou-core/src/Seihou/Manifest/JSON.hs`, and `seihou-core/src/Seihou/Manifest/Upgrade.hs` own manifest encoding, version checks and adjacent upgrades. On 2026-11-11 `currentManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs` is 14 and Seihou is at 0.15.0.0. Allocate the next version from the actual working tree during implementation; do not reserve a stale version number in this plan. `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` integrates deterministic capability upgrades. `seihou-cli/src/Seihou/CLI/CheckoutSync.hs` and `seihou-cli/src-exe/Seihou/CLI/Sync.hs` implement checkout restoration.

There are three production auto-commit callers: `seihou-cli/src-exe/Seihou/CLI/Run.hs`, `seihou-cli/src-exe/Seihou/CLI/Update.hs`, and `seihou-cli/src/Seihou/CLI/Migrate.hs`. Each uses helpers in `seihou-cli/src/Seihou/CLI/Git.hs` and `seihou-cli/src/Seihou/CLI/CommitMessage.hs`. Today they can send the staged diff to an AI before invoking `git commit`. `gitDiffCached` truncates that prompt to 4,000 characters and does not check the two diff command exit codes. Build a separate complete, checked evidence collector; that helper is not a security boundary. Gate all three callers before message generation, including fixed-message paths, and propagate a blocked/error result to the process exit status.

Shikumi is located through `mori registry show shinzui/shikumi --full`. Its typed runtime comes from `mori://shinzui/shikumi/packages/shikumi`, evaluation from `mori://shinzui/shikumi/packages/shikumi-eval`, and optional observation from `mori://shinzui/shikumi/packages/shikumi-trace`. The core API inspected for this plan is `Shikumi.Signature.mkSignature`, `Shikumi.Module.predict`, `Shikumi.Program.runProgram`, `Shikumi.Schema` derivation/validation, `Shikumi.Routing`, and `Shikumi.LLM`. `modelJudge` in the evaluation package grades a candidate against a reference; it is not the production security program. Build a dedicated typed program for the latter.

On 2026-11-11, Hackage's `https://hackage.haskell.org/package/shikumi.json` lists 0.5.1.0 as the newest version, and upstream tag `shikumi-0.5.1.0` resolves to `7b96ecf06364b37de44b15c4f58b2528b5a3e0f5`. Hackage also lists `shikumi-eval` 0.3.1.0, `shikumi-trace` 0.3.2.0, `baikai` 0.10.1.0, `baikai-claude` and `baikai-openai` 0.7.3.0, and `baikai-effectful` 0.5.0.0. This is discovery evidence, not a permanent dependency constraint. Recheck the registry and upstream tags before selecting bounds.

Decision outputs are released in `Shikumi.Decision`. The Shikumi user guides are in its `docs/user` directory, reachable through `mori registry docs shinzui/shikumi`; read `decisions-and-calibration.md` and the "Probability-backed decisions" section of `signatures-and-schemas.md` (artifact-level Mori URIs for these guides are pending, so use `mori://shinzui/shikumi` with those project-relative names). The facts this plan relies on are:

- `Noul` is a yes/no decision. `NoulWith "yes criterion" "no criterion"` adds a description of each answer. The decoded value holds a locally derived Boolean, the probability of yes, and a confidence. `Field "question" t` attaches the question text. All of these are compile-time types; the rubric text reaches the model through the run-time instruction given to `mkSignature`.
- `Choice` and `Score` are the label and ordered-scale decisions. Their domains are also compile-time, and a decision cannot be nested inside a list, map or other container.
- An output record may mix decisions with free-form fields when run on a generative model. Shikumi then asks the model for a closed evidence value such as `{"noul":0.83}` through native JSON or a marker prompt, and rejects missing keys, extra keys and probabilities outside 0 to 1 with a typed error. These numbers are stated by the model, not read from token log-probabilities, and Shikumi's guide says the shared contract does not imply calibration.
- A judgment-only model is one that answers closed questions and nothing else, routed through Baikai's `isJudgmentOnly` catalog fact. It refuses free-form output fields before dispatch. An output record that derives `DecisionOutputs` is guaranteed at compile time to contain only decisions and can run on such a model. Shikumi sends it one structured state holding the run-time instruction, the typed input and any demonstrations, so an author's question reaches it without a system prompt.
- The only judgment-only provider today is `mori://shinzui/baikai/packages/baikai-typesafe`, 0.1.0.1 on Hackage, requiring `baikai ^>=0.10.0` and `typesafe-hs ^>=0.1.0.0`. Register `Baikai.Provider.TypeSafe.Api.typesafeProvider` on an explicit provider registry and select `typesafe_jev_latest` from `Baikai.Models.Generated`. It reads `TYPESAFE_API_KEY`, is a hosted remote service, performs no internal retries, refuses system prompts, tools, multi-turn history and every explicit generation control, and has no catalogue price, so cost estimates are unavailable. Its guide is `typesafe-judgments.md` in Baikai's `docs/user` directory. Its input size limit is not documented there and must be measured in M1.
- There is no run-time way to declare a set of decision questions. A list of author-defined checks therefore runs as one call per check over one fixed reply type.
- Decision probabilities are response content. They pass through response caches, traces, call logs and OpenTelemetry export wherever those are installed, independently of the separate per-call evidence option.
- `runProgram` is sufficient. Streaming of decisions exists since 0.5.1.0 but returns one atomic answer and bypasses caching, so it offers nothing to a gate.

Provider transports below Shikumi come from `mori://shinzui/baikai`; discover and inspect any imported package with Mori before choosing an API. Seihou already depends on `baikai`, `baikai-claude`, `baikai-openai` and `baikai-kit`, pinned to the 0.8 line in `seihou-cli/seihou-cli.cabal` and `nix/haskell-overlay.nix`, and imports them from `AgentCompletion.hs`, `AgentConfig.hs`, `AgentModels.hs`, `AgentTrace.hs` and `KitConfig.hs` under `seihou-cli/src/Seihou/CLI/` and from `AgentLaunchExec.hs`, `AgentMigrate.hs` and `Kit.hs` under `seihou-cli/src-exe/Seihou/CLI/`. The overlay carries a patch for a hardcoded `/bin/ps` in Baikai 0.8.0.0; check whether the selected release still needs it. Baikai 0.9.0.0 added fields to public content, event, model, error, trace and log types, and 0.10.0.0 added a `ThinkingNone` constructor and new compatibility-record fields; both are recorded in the changelog of `mori://shinzui/baikai/packages/baikai`.

Existing Seihou interactive agent configuration does not automatically define an unattended judgement provider. Reuse configuration/provenance conventions where appropriate, but give judgements their own validated settings. A CLI provider that sends content to a hosted service is remote even though its executable runs locally. Shikumi enforces the output schema on Baikai's `claude-cli` and `codex-cli` providers by passing it to the CLI, and an installed CLI too old to accept the schema fails the call instead of replying unconstrained. Third-party hosts fall back to a marker prompt whose reply is still strictly decoded. Baikai's Claude and OpenAI adapters can mark prompts for provider-side caching when a cache retention is requested; that retains review content at the provider, so judgement requests must leave cache retention unset. Shikumi trace attributes can include full request and response JSON, so its default capture stack must not be enabled unchanged for security evidence. Shikumi's attempt-evidence interpreters (`runLLMResilientWithEvidence`) report the observed model and attempt count, but their error messages can contain provider response text and must be sanitized before reaching a report.

Use Gitleaks as the initial deterministic scanner adapter, with its invocation and output schema verified against the selected release. Mori currently has no registered Gitleaks source. Its [official source and CLI documentation](https://github.com/gitleaks/gitleaks) describe `stdin`, directory and Git scanning and redacted reports. The adapter must scan the exact captured material and translate machine findings into Seihou findings; scanning a mutable worktree while judging a different index is unacceptable. Avoid building a second regex secret scanner inside Seihou.

Relevant local decisions constrain this work. [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) excludes paths, credentials and machine state from the manifest. [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) makes origin plus name the artifact identity; definition hashes identify reviewed bytes, not a replacement artifact identity. [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) and [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md) require explicit handling of stale/substituted artifacts. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) disallows a separate applied-state lockfile. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) requires a schema advance, adjacent upgrade, capability mapping and version-aware validation for this new state. [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md) requires exhaustive, actionable human diagnostics. [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md) supplies the intent/observation/sync pattern, but does not currently authorize a new hook resource kind. Do not encode hooks as fake directory symlinks or infer setup from shell receipts. [ADR 0020](../adr/0020-dependency-sources-belong-to-producer-edges.md) makes install acquire a closure from producer-declared sources without a registry search, and [ADR 0024](../adr/0024-recipes-extend-one-origin-aware-base.md) lets a recipe extend one base; judgement references must be acquired through the same closure and inherited through the same base edge. [ADR 0022](../adr/0022-recipe-descriptor-validation-is-independent-of-composition.md) keeps descriptor validation free of discovery, configuration and prompts, which `validate-judgement` must also honor. [ADR 0023](../adr/0023-command-receipts-are-published-before-the-command-phase-runs.md) publishes command receipts before commands run, which confirms that receipts cannot stand in for a judgement result. [ADR 0025](../adr/0025-a-module-owns-only-its-own-directory-under-seihou.md) gives each module `.seihou/<module-name>/` and lists Seihou's own entries in `reservedSeihouEntries` in `seihou-core/src/Seihou/Core/Path.hs`; any ignored local report directory under `.seihou/` must be added to that list. No existing ADR defines judgement semantics; add that durable decision during implementation. This repository's ADR directory is not a profiled OKF bundle.

Follow the library-first and record conventions in `docs/dev/contributing.md`: runtime/evidence/rendering services belong in the internal library; only optparse/file-embedding/dispatch code belongs in the executable directory. New data-record fields are strict, unprefixed, and accessed with overloaded labels. Never traverse `/nix/store` or the filesystem root to locate dependency code.


## Plan of Work

### M1 — Prove the ordinary consumer path early


Start with a representative existing Git consumer, recording its current Seihou version, manifest version, hooks, hook manager, staged changes and developer commands. Seihou itself is an appropriate first consumer because `nix/pre-commit.nix` and `flake.module.nix` already install managed checks; do not replace those checks with a pristine fixture and claim coexistence. Work in a disposable clone/worktree and temporary user configuration, preserving the real pre-change committed state. Count build/install/provider preparation separately from ongoing developer commands.

Before any judgement code, move Seihou to the Baikai line Shikumi requires. Raise the `baikai`, `baikai-claude`, `baikai-openai` and `baikai-kit` bounds in `seihou-cli/seihou-cli.cabal` and the matching pins in `nix/haskell-overlay.nix`, add `shikumi` and `baikai-effectful` within the bounds the selected Shikumi release declares, and repair the existing agent modules for the 0.9 and 0.10 breaking changes. Commit this as its own change with the existing test suite passing, so a later judgement defect cannot be confused with an upgrade regression. If the upgrade proves larger than a mechanical repair, record that in Surprises & Discoveries and split it into its own plan before continuing.

Implement only enough of the proposed domain, bundled definition, `run`, `check`, direct Shikumi adapter and hook wiring to exercise the vertical path. Use an actual supported generative provider for a small synthetic live review, and an offline typed stub to force pass/block/needs-review/error branches deterministically by returning chosen probabilities. Record the probabilities the live route reports for the benign and the confidential example; they are the first evidence for choosing default thresholds. Run the same two examples once through the judgment-only gate with a live key, recording its probabilities, latency, accepted input size and the exact refusal for an oversized input. If the gate cannot be exercised live, record why and continue; the gate is optional and must not hold up the generative path. Include one check that has nothing to do with secrets, such as a documentation-freshness question, so the vertical path is not accidentally security-shaped. Test injection belongs in the test harness, never in a public flag that can cause an enforced production gate to report a fake pass. First-use provider/data-policy selection happens inside adoption's existing preview/configuration flow. Noninteractive adoption must require explicit settings rather than silently consent to transmission.

Acceptance is that `seihou run security-review` previews and activates the judgement, a benign staged change can commit, and a seeded fake credential prevents an ordinary `git commit` with a redacted reason and no provider request. Also submit a contextual synthetic confidential example through the typed review and observe the expected finding. Record every prerequisite, prompt and manual edit. Promote this path into the final implementation; if hook integration or Shikumi decoding needs a different approach, correct it here before building the full artifact surface. A source-only demonstration verifies this milestone, not release delivery.

### M2 — Make custom judgements normal artifacts


Add `Judgement.dhall`, `JudgementRef.dhall` and supporting closed types to `mori://shinzui/seihou-schema` (artifact-level file URIs pending); export them through its project-relative `package.dhall`. Extend its module and recipe schemas with default-empty judgement references. Preserve decoding of supported older artifacts. References resolve through the ordinary composition/search machinery and may use the existing conditional-expression mechanism; do not require users to list transitive references.

In Seihou add `seihou-core/src/Seihou/Core/Judgement.hs` for domain/validation and `seihou-core/src/Seihou/Core/JudgementArtifact.hs` for resolution and definition construction. Extend `seihou-core/src/Seihou/Dhall/Eval.hs`, `seihou-core/src/Seihou/Core/Module.hs`, `seihou-core/src/Seihou/Core/Registry.hs`, installation, list/browse rendering, registry synchronization and full validation. Discover `judgement.dhall` as an artifact; reject ambiguous co-located artifact kinds when adding the new kind rather than silently hiding it. Extend registry name-collision checks and default missing legacy judgement lists to empty. Provide a judgement kind filter in list/browse and completion of judgement names. `seihou outdated` and `seihou upgrade` already cover installed blueprints and prompts; extend them to installed judgements so the new kind is not the one artifact they skip.

A definition carries a name, optional version, shared instructions, evidence and trigger declarations, coverage limits, a list of deterministic checks, and a nonempty list of checks. Evidence declarations choose scopes from a closed, versioned set (staged changes and commit ranges in this delivery) and may narrow them with path include and exclude patterns, so a judgement about documentation need not read source files. Deterministic checks are chosen from a closed, versioned set whose only member in this delivery is the secret scan.

Each check carries a name unique within the judgement, the question, which answer is the concern (yes by default), optional guidance on what counts as yes and as no, allowed finding categories with severities, a default enforcement, and default thresholds: the probability at or above which the check blocks and the probability at or below which it may pass, for the generative review and separately for the gate. Thresholds always refer to the probability of the concern, whichever answer that is, so a higher number is always worse. The pass value must not exceed the block value; equal values remove the needs-review band. A check may opt out of the gate. Validation rejects duplicate check names, values outside 0 to 1 and an inverted pair. The schema supplies defaults so that a one-check judgement needs only a name and a question.

Expose `seihou new-judgement NAME`, `seihou validate-judgement NAME`, `seihou judgement eval NAME`, and `seihou judgement configure NAME`. The first two follow the naming and argument conventions of the existing `new-*` and `validate-*` commands. New creates `.seihou/modules/NAME/judgement.dhall` and a synthetic `examples.json` by default, with `--path` for registry authors. It refuses to overwrite an existing directory. The scaffold carries a useful rubric and annotated examples rather than a vacuous instruction to "review carefully". Editing one instructions field and adding examples must be sufficient for the normal custom judgement. Configuration explains provider/model/data-policy selection and project enforcement; it does not store credentials in an artifact or manifest.

Define `judgement configure NAME` to work before or after application. Before application it prepares settings consumed by the normal preview; after application it previews and atomically records an explicit policy change. Support `--provider PROVIDER`, `--model MODEL`, `--data-policy local-only|approved-remote`, `--gate-provider PROVIDER`, `--gate-model MODEL` and `--no-gate` for the optional gate, and per-check overrides selected with `--check CHECK` followed by any of `--enforcement enforced|advisory`, `--block-at P`, `--pass-at P`, `--gate-block-at P` and `--gate-pass-at P`. Without `--check`, `--enforcement` sets the default for every check. The interactive wizard selects the same values. Provider/model availability is checked against the actual runtime catalogue; no model identifier is guessed. A model the Baikai catalogue marks judgment-only is refused as the review model, with a diagnostic explaining that it cannot return located findings and may be configured as the gate; a model not marked judgment-only is refused as the gate. The gate is a second remote destination and the data policy must permit it separately. Provider credentials remain in the selected transport's normal environment/credential store. Local runtime choices may narrow the committed permitted destinations but cannot broaden them. Unconfigured noninteractive adoption fails with the exact configure command and performs no partial activation.

Publish the compatible schema commit, advance the submodule and immutable scaffold URL/hash together, and update the flake schema input. The schema producer must be published before a consumer scaffold relies on it. This plan's creation does not authorize performing that release now; implementation includes the producer work and records any remaining publication boundary.

Acceptance is an author creating `customer-data-review`, editing its instructions through the normal file, validating it, running its examples, and applying it using `seihou run customer-data-review`. A second author can install the same definition from a registry using ordinary `seihou install SOURCE`, find it through list/browse, and apply it. Invalid categories, bad paths, ambiguous identity and malformed examples fail with named diagnostics before any provider call. Older modules/recipes and registries still load.

### M3 — Record portable intent and restore checkout integration


Extend `seihou-core/src/Seihou/Core/Types.hs`, manifest encoders/decoders, upgrade registry and capability mapping. Persist active, resolved definitions with their origin/name/version, definition digest, instruction text, allowed finding categories, evidence/trigger declarations, coverage limits and application owners. Persist data policy, whether a gate is permitted, and each check's effective enforcement and threshold pairs separately from model findings, keyed by check name. Thresholds are plain numbers in Seihou's own encoding; no Shikumi parameter or setting type is serialized. Store no raw review evidence, provider credentials, absolute paths, timestamps of "last safe" commits, or artifact-cache paths. Snapshot definitions so checks work offline with respect to artifact discovery, even though the chosen model may require a network connection. Evaluation-only fixture files need not be stored in the manifest.

Declare an explicit portable representation for project-selected judgement policy and owners. `run` resolves references once and records the resolved program definition; `update` previews definition/policy changes and replaces selected owners while preserving unselected ones. Agreeing references co-own a declaration; conflicting definitions or policies for the same identity refuse before publication. Disabling a condition or dropping a reference retires only that owner's claim. `remove` removes the last owner's active declaration and Seihou-owned hook contribution safely. Judgements have no ordinary command success receipt. A user editing an artifact must apply/update it to change project intent, and the command must say when the active snapshot differs from the authoring source.

Add one adjacent deterministic manifest upgrade that introduces empty judgement state without inventing active checks for old projects. The normal adoption command stages the lossless supported upgrade atomically. Inference-bearing legacy upgrades remain explicit, with the existing repair command. Check commands are read-only: if a manifest cannot be interpreted at the required capability, they name the necessary adoption/upgrade command and make no implicit state changes.

Implement hook setup as a dedicated typed judgement service, `seihou-cli/src/Seihou/CLI/Judgement/Hooks.hs`, invoked by application and sync. Its desired input is derived from active declarations, and its observations are local hook/config state. Keep this service distinct from ADR 0018's directory-link specification; amend that ADR only if sharing an actual common interface, and document the hook lifecycle explicitly. Resolve Git's hook directory correctly for linked worktrees and `core.hooksPath`. Compose with supported existing hook managers or a preserved existing hook. Preserve original literal symlinks without reading their external targets. Never overwrite user hooks, replace a shared hooks directory globally, or report setup success if the effective hook is unchanged. Unsupported integration must block adoption with a precise supported next action. Solve coexistence with Seihou's own pre-commit/Nix setup as part of the feature, including regeneration of manager-owned hooks.

`seihou sync` repairs missing owned setup from the manifest without resolving producer artifacts or changing tracked files/index/manifest. Repeating sync is a no-op when setup is correct. Status distinguishes declared, operational and misconfigured judgement setup without running the model. Existing hooks remain in effect, and removal only removes an unchanged Seihou-owned contribution. A hook overwritten by another manager is detected and repairable through the normal sync path, never assumed active from a prior receipt.

Acceptance includes an old supported manifest upgraded through ordinary adoption, unchanged pre-existing application state, agreeing owners, conflict rejection, last-owner retirement, and fresh-clone/linked-worktree sync with empty producer caches. A complete failed application/update must not publish a partial active policy. Keep transient check reports out of manifest diffs.

### M4 — Implement complete evidence and a bounded direct Shikumi review


Add reusable services under `seihou-cli/src/Seihou/CLI/Judgement/`: `Evidence.hs`, `Scanner.hs`, `Runtime.hs`, `Config.hs`, `Report.hs`, and `Evaluate.hs`. Domain decisions remain in `Seihou.Core.Judgement`; these services gather bytes, invoke tools/providers and render observations. The sole production language-model adapter is direct Shikumi. Add its dependencies to the internal CLI library, with `shikumi-eval` where evaluation needs it, and update `mori.dhall` and `nix/haskell-overlay.nix` as appropriate. Keep `seihou-core` independent of Shikumi and transport packages.

For staged checks capture the index tree and checked Git metadata using argument-vector subprocess calls and NUL-delimited paths. Derive snapshot identity from indexed paths, modes and blob IDs without refreshing or writing the index; do not use an index-writing tree/cache refresh as a supposedly read-only check. Read blob contents from the index, not the working tree. Disable external diff/text-conversion execution and avoid filesystem traversal through Git attributes. Handle partial staging, additions/deletions, renames, spaces, unusual filenames and linked worktrees. Reject unresolved index entries and failed Git reads. Use complete captured content for relevant changed files, with explicit before/after identity and line mappings; do not silently restrict review to a truncated patch. Sensitive deleted/context material must also be locally scanned before any of it is transmitted. Do not follow staged symlinks or descend into submodules. Unsupported binary/LFS/submodule/archive content is reported as uncovered unless the selected scope explicitly excludes it; it cannot disappear from coverage counts.

For `--range BASE..HEAD`, resolve immutable commits up front and inspect every introduced commit change in the range, not merely the final net diff. A secret introduced and later removed must still be found. Record the ordered commit/blob scope in the snapshot digest. Refuse invalid ranges, shallow-history gaps and missing objects with concrete remedies. Range checking does not use or alter the worktree/index. An empty staged set or empty range reports `NoChanges`, which is an explicit no-op rather than a claimed semantic review.

Run the scanner on the same captured material, supplying sanitized machine-readable reports. Pin/verify its output contract and pass an explicit trusted scanner configuration; repository-local ignore comments, allowlists, environment variables and ambient config must not silently weaken the required baseline. Gitleaks stdin or an isolated private snapshot are possible implementations; validate source-to-line mapping with the selected released CLI rather than assuming Git mode reads an immutable snapshot. Temporary files, if unavoidable, use private permissions and are removed on success, failure and cancellation. Raw scanner output and model errors never stream directly to the terminal or a trace. Missing scanner or scanner failure yields an error, not "no secrets found".

The scanner serves two roles that must stay distinct in code and in reports. As a transmission safeguard it runs before any remote request of any judgement, and material it flags is never transmitted. As a deterministic check it produces findings, only for definitions that declare it; the bundled security definition does, and there a deterministic blocking finding also stops further transmission. For a judgement that does not declare it, flagged material makes the affected checks end as errors that name the file and the safeguard, so the developer learns why nothing was reviewed without the judgement claiming a finding outside its subject. A judgement on a local-only route with no deterministic checks does not need the scanner installed. For remaining semantic review, project data policy must explicitly allow the selected route and evidence scope. A local executable is not proof of local processing. Never silently fall back to another provider, model, data policy, or unstructured output path. No reviewed content is treated as instructions to execute; the reviewer has no tools, shell, browsing, file-writing or agent loop. Malicious text in code/documents is evidence, not an authority over the rubric.

Build two Shikumi programs over adapter-private records, each run once per check with a `Signature` whose instruction is assembled from the definition's shared instructions and that check's question and guidance. The review program's reply has three top-level fields: a `Noul` decision whose fixed, subject-neutral question asks whether the answer to the check's question is yes; a list of findings; and a plain Boolean by which the model may request human review. The gate program's reply has only the `Noul` field and derives `DecisionOutputs`, so the compiler guarantees it can run on a judgment-only model. The decision must be a top-level field because Shikumi does not decode decisions inside containers. The assembled instruction also tells the model which answer is the concern and that findings are the places where the concern shows, so that for a check such as "does this change include tests?" the findings name the untested additions. Convert each decoded reply into Seihou's own per-check output: take the reported probability of yes, replace it with its complement when the check declares no as the concern, carry the result as a plain number, and discard Shikumi's derived Boolean and confidence. This conversion happens once, in the adapter, for both programs. Checks are independent and may run concurrently within the declared attempt and cost limits.

Enforce domain validation in Seihou after decoding as well: categories and severities declared by that check, valid file/location references, bounded output sizes, and a probability within 0 to 1. The model reports evidence; it does not choose project policy or manufacture the coverage count. `decideCheck` then applies that check's recorded thresholds to the review reply: a blocking located finding blocks; a probability at or above the block threshold blocks even with no finding, and the report says no location was given; a probability above the pass threshold, or an explicit request for review, yields needs-review; only a probability at or below the pass threshold with no blocking finding and complete coverage can pass. Invalid or inconsistent outputs are errors. `decideJudgement` combines the checks: any enforced block blocks, otherwise any enforced needs-review or error withholds the pass, and advisory checks are reported with their real status without affecting the result.

When a gate is configured, each check that has not opted out goes to the gate program first. A gate probability at or below the check's gate pass threshold clears the check with no review call, and the report says the gate decided it. Any higher probability escalates that check, for the evidence chunks that exceeded the threshold, to the review program, whose reply decides as above with one restriction: if the gate probability reached the gate block threshold, the check cannot pass and ends as needs-review at best. A gate runtime failure, refusal or oversized input is reported and escalates the check; it is neither an error for the whole judgement nor a clearance. The gate request is subject to the same transmission safeguard, data policy, timeout and limits as the review request, sends no system prompt or generation controls, and receives the evidence as typed input. Coverage accounting records, per check and chunk, whether the gate or the review decided. Reuse Shikumi's typed transient retry handling, with a bounded overall timeout, input/output limits and attempt count. Do not use repeated calls until the model changes its mind about a block. Report the observed model, actual runtime version, attempts, available usage, and for each check the concern probabilities, the thresholds applied and which route decided, labelling every probability as model-reported and, for a check whose concern is no, saying that the figure is the complement of the model's yes. Take the observed model and attempt count from Shikumi's attempt evidence rather than from the requested configuration. Leave cache retention unset on every request and install no response cache. Shikumi's optimistic cost admission is not a strict monetary cap; describe its actual limit honestly.

Chunk large but supported evidence deterministically within declared limits, retaining complete coverage accounting. Each chunk yields its own probability for each check, and for a given check the highest one governs. Aggregate any block, uncertainty or runtime error so it prevents an enforced pass. If limits prevent complete review, name the uncovered files and the supported next step; never truncate and pass. Before each provider request apply the same local data checks to every outgoing field, including instructions and contextual snippets. Redact and bound all human/JSON report strings, including model-generated text that may echo source contents. Default local reports contain only sanitized findings, scope/digests and operational metadata. No raw Shikumi prompt/response capture, shared response cache or telemetry export is enabled for production security checks in this delivery. Offline synthetic fixtures provide replay/evaluation without retaining real secret-bearing inputs.

Acceptance is the same immutable evidence driving scanner and semantic review, a fake credential caught beyond character 4,000, a contextual confidential finding, no remote call after scanner block, a malformed reply producing an error, a stubbed probability on each side of both thresholds producing pass, needs-review and block, an out-of-range or missing probability producing an error, a blocking finding with a low probability still blocking, two checks in one judgement reaching different outcomes from the same probability because their thresholds differ, an advisory check reporting a block without failing the judgement, a check whose concern is no blocking on a low reported probability of yes and passing on a high one for both the gate and the review, a gate clearance making no review request, a gate escalation making exactly one, a gate block followed by a clean review ending as needs-review, a failing gate escalating visibly, a non-security judgement stopped by the transmission safeguard reporting an error and no finding, and no test-secret marker in stdout/stderr/local reports/telemetry. Capture coverage and exact version/route in the report. Verify that bypass-like strings in evidence and model output cannot change policy.

### M5 — Share gate enforcement across Git, Seihou and CI


Add parser options and dispatch in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` and `seihou-cli/src-exe/Main.hs`, with thin new `Check.hs` and `Judgement.hs` dispatchers. `seihou check` defaults to all active checks on staged changes; an optional NAME selects one active judgement for diagnosis. `--staged` makes the default explicit. `--range BASE..HEAD` selects commit-range evidence and is mutually exclusive with staged selection. `--dry-run` reports the checks, permitted route, evidence scope and coverage plan without provider calls or setup changes; its output must never claim approval. `--json` emits the stable versioned report, while ordinary output identifies the judgement, reviewed scope, findings, and next action.

Use exit 0 for pass or explicit NoChanges, 10 for a policy block, 11 for needs-human-review, and 1 for runtime/configuration/incomplete-coverage errors. Parser errors retain normal CLI behavior. Enforcement is per check. An advisory check may leave the exit at 0 despite reported findings, but the report must retain its actual status and mark it advisory. For every enforced check, block, needs-review, error and incomplete coverage all prevent the action; when several enforced checks disagree the exit code is the most severe, with block above needs-review above error. All active enforced judgements must pass; a named diagnostic invocation is not a substitute for running them all. Existing `--force`, `--no-commands`, receipt reuse and agent settings do not bypass an enforced gate. No generic skip/force-pass flag is introduced.

Create `seihou-cli/src/Seihou/CLI/Judgement/CommitGate.hs` and route run/update/migrate through it after normal intentional staging, before AI message generation, and immediately before committing. Check all staged changes that Git will commit, including unrelated pre-staged files, without staging or unstaging them. If the gate blocks after files were generated, leave those user-visible changes and staging intact and return nonzero with "changes applied; commit blocked" and the exact check command. Do not pretend external file generation or shell effects were rolled back.

Bind approval to index tree, active-definition digests, policy including thresholds, and selected runtime configuration. Recheck those inputs after model/message generation and before commit; if they changed, rerun the required review or refuse with an actionable stale-result message. The ordinary pre-commit hook verifies the final staged tree too, including modifications made by earlier hooks. With a pre-commit framework, arrange the judgement after mutating formatters or force a new review if they change the index. A process-local approved snapshot may avoid duplicate model work only for the exact same gate invocation; no committed success receipt authorizes future content. Do not add an environment variable that can forge approval for a later hook process. Prefer a second review over an unverifiable cross-process bypass; measure this cost before considering a dedicated protected local handoff protocol.

Hook and Seihou paths cover ordinary cooperative development, not a hostile local process deliberately replacing Git hooks or racing the index. State that boundary without claiming an atomic Git security sandbox. CI is the independent enforcement path for hooks bypassed with Git's own facilities. For required CI policy, use the policy from a trusted base commit/branch, not unreviewed policy weakening in the change under test; support `--policy-ref REF` with immutable resolution, and use explicit initial-adoption review when no trusted policy exists. Read that policy from Git objects rather than checking it out. Local hooks may use active manifest policy, but staged policy removal/weakening must be visibly reported rather than mistaken for an ordinary clean result.

Acceptance covers all three auto-commit callers, fixed and generated commit messages, a staged-tree change during review, an existing hook changing staged content, and JSON/exit-code agreement. An instrumented provider/message generator must see zero secret-bearing requests when the scanner blocks. CI catches a secret introduced and removed within a range and does not accept a proposed weakening of its base policy.

### M6 — Make authoring, evaluation and source delivery reviewable


Ship the bundled `security-review` definition and synthetic evaluation corpus under `seihou-cli/data/judgements/security-review/`, with explicit Cabal source packaging and a small executable-only embedding adapter. Decode bundled and custom definitions through the same path. Use ordinary artifact search first and the bundled catalogue as a final fallback for a new application; always preview origin/version. Once applied, the manifest snapshot wins, so a same-named cache artifact or a newer binary cannot silently replace it. Custom judgement artifacts installed from registries get the same validation and reporting as bundled ones.

Add `JudgementSpec.hs`, `JudgementArtifactSpec.hs` and manifest upgrade tests under `seihou-core/test/Seihou/`; add evidence, runtime, output-sanitization, hook/commit and real-binary consumer tests under `seihou-cli/test/Seihou/CLI/`. Register them in each test `Main.hs` and Cabal manifest. Match existing test conventions rather than introducing a second runner. Use offline Shikumi stub/loopback facilities verified from upstream sources for protocol/ordering tests. A stub proves orchestration and rejection behavior, not the quality of a real model.

`seihou judgement eval NAME` loads the author's labelled `examples.json`, runs the same program under an explicitly configured permitted model, and reports missed unsafe cases, false blocks on benign cases, undecided cases, runtime failures, latency and available usage at the configured thresholds. Because each case's probability is retained from the run, it also prints how those counts would change across a sweep of threshold pairs, without further model calls, and names the route the numbers apply to. It proposes nothing and writes nothing; the author edits the definition. Score cases by the decided status, not by equality of whole replies, since two correct replies differ in their probabilities. Cases contain synthetic inputs, expected category/location/status, and stable IDs; validation catches malformed or secret-bearing example data before remote submission. Default invocation may incur model calls and must say so in help. Add an explicit offline mode that validates the corpus and tests deterministic policy/scanner behavior without claiming model accuracy. Offline mode cannot emit evidence usable as a production gate pass.

For release qualification use at least 20 benign and 20 unsafe labelled synthetic cases spanning fake credentials, contextual confidential data, synthetic fixtures, removed secrets, and instruction-injection attempts. Require zero missed critical seeded credential cases and no more than 10 percent false blocks on the benign release set for the route advertised in documentation. Record uncertainty/error counts separately; abstention is not a detected finding. The bundled definition's default thresholds are the ones this corpus was qualified with on that route; a project that selects a different route is told that the thresholds are unqualified for it. Qualify the gate separately on the same corpus: at its default gate thresholds no unsafe case may be cleared by the gate, and the share of benign cases it escalates is reported as its cost. `judgement eval` reports the gate and the review per check, and the combined outcome. If the gate cannot meet this, the bundled definition ships with the gate off, the documentation calls it unqualified, and that is recorded as a delivery limitation rather than by loosening the rule. The release corpus also includes a second bundled or example judgement on a non-security subject with at least two checks using different thresholds, so the general contract is exercised by more than tests. If the semantic route cannot meet the declared qualification, keep that route unqualified and the delivery milestone open rather than lowering acceptance silently. This corpus bounds a release check, not a proof that unknown sensitive data cannot escape. Re-evaluate before changing the advertised model/rubric/runtime defaults.

Write `docs/cli/check.md`, `docs/cli/judgement.md`, `docs/user/judgements.md`, and embedded `seihou-cli/help/judgements.md`. Update README command/artifact tables, `seihou-cli/help/workflow.md`, `seihou-cli/data/module-reference.md`, architecture docs, CLI completions, changelog and affected generated OKF rendering in `seihou-okf-extension`. The documentation must distinguish local scanner findings from probabilistic semantic review, explain the two thresholds, the concern direction and that thresholds always apply to the probability of the concern, and that the probability is a model-stated estimate tied to one route, name scope/coverage limits, explain provider consent and credentials, and show a complete custom artifact. Update/create the durable judgement ADR when the interface is accepted; do not turn a proposed design into a falsely implemented ADR during plan creation.

Acceptance is that a new author follows only the public help to create, edit, validate, evaluate and activate a custom judgement, while a developer follows the one-command built-in adoption and ordinary commit workflow. Dry-run performs no model request or mutation. All required focused and repository gates pass on the final source candidate, and the plan records actual executable versions and observations rather than test counts alone.

### M7 — Deliver published artifacts and verify the installed workflow


Include Gitleaks in the supported Nix development/runtime packaging, with a verified version and subprocess contract. Make the packaged `seihou` find its scanner without requiring a global PATH edit. For Cabal/Hackage installations, clearly document the external scanner prerequisite and check it during adoption, with an exact supported installation action for the detected platform; do not silently download executables during a check. Packaging differences are visible acceptance limits, not hidden preparation. Verify the source archive includes judgement definitions, help and examples.

Use the existing release workflow when implementation reaches release, including its dependency-order and PVP checks. Recheck current released Shikumi/transport versions and upstream tags before choosing bounds; validate the minimum supported runtime and selected current release without declaring compatibility with future APIs. Pin `baikai-typesafe` and its `typesafe-hs` dependency in `nix/haskell-overlay.nix` alongside the other Baikai packages, and document `TYPESAFE_API_KEY` as needed only when a gate is configured. Update schema pins and build metadata together. Publish the schema first, then the Seihou packages, then verify the installed binary against those published artifacts. If publication/installation awaits authorization or credentials, stop at the concrete release-ready candidate and leave M7 open.

From the actual existing consumer, use the released installed `seihou run security-review`, exercise benign/blocked commits, and activate a user-authored judgement. Clone it into an empty artifact cache and create a linked worktree; use only documented `seihou sync` and normal provider credential setup before ordinary Git commands. Prove existing hook checks survive, scanner discovery works, tracked bytes/index/manifest do not change during sync/check, and no source-tree absolute paths are needed. Record installed `seihou --version`, schema revision, Shikumi/scanner versions, selected route, platforms tested, and any remaining release gap before marking the plan complete.


## Concrete Steps

All repository commands below run from the Seihou repository root unless a consumer directory is named. Public judgement commands are proposed interfaces implemented by this plan; they do not exist in Seihou 0.15.0.0. Do not report these transcripts as already observed.

Refresh upstream discovery before implementation and bounds selection:

```bash
mori registry list
mori registry search shikumi
mori registry show shinzui/shikumi --full
mori registry docs shinzui/shikumi
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
mori registry search baikai
curl -fsSL https://hackage.haskell.org/package/shikumi.json
curl -fsSL https://hackage.haskell.org/package/baikai.json
curl -fsSL https://hackage.haskell.org/package/baikai-effectful.json
git ls-remote --tags https://github.com/shinzui/shikumi.git 'refs/tags/shikumi-*'
git status --short
git submodule status schema
```

Hackage's version listing is a JSON object ordered as text, so 0.10.1.0 appears before 0.2.0.0; read the whole object rather than its last entry. Read the source at the paths returned by Mori and check the selected released APIs, including the dependency bounds in the selected Shikumi release's Cabal file. Use the registered schema producer checkout for schema commits. Do not make an untracked schema-only edit and leave consumers pinned to old bytes.

Build in the repository's supported development environment. For repeatable noninteractive commands use:

```bash
nix develop -c cabal build all
nix develop -c cabal run seihou -- --version
nix develop -c cabal run seihou -- check --help
nix develop -c cabal run seihou -- judgement --help
```

For the early source-build consumer run, obtain the absolute executable path with `cabal list-bin seihou` in that same development environment and put its containing directory on the disposable consumer's PATH. Hooks must invoke that same binary, not an older global installation. Record this source-build setup explicitly. Release acceptance repeats the workflow with the installed executable and no source-build PATH override.

In the chosen disposable consumer, with an installed or explicitly recorded development executable and no prior judgement state:

```bash
seihou --version
seihou run security-review --dry-run
seihou run security-review
seihou check --dry-run
git add README.md
git commit -m 'docs: clarify the project description'
seihou check --staged --json
```

Adoption's normal preview/configuration flow selects the permitted provider/model/data policy once, displays hook changes and scanner availability, and uses the existing confirmation boundary. The benign commit succeeds. An empty staged set after the commit reports NoChanges, not "security verified". To test a secret, stage a synthetic scanner fixture from the checked-in test corpus in a disposable consumer; never use a real credential. Its ordinary commit is refused with a redacted finding, and the provider stub/request observer records zero transmissions.

Custom authoring, starting in that consumer, uses:

```bash
seihou new-judgement customer-data-review
```

Edit `.seihou/modules/customer-data-review/judgement.dhall` and its `examples.json` through the normal authoring workflow. For example, the new schema must support this minimal definition, with evidence/category/limit defaults documented by the scaffold:

```dhall
let S = ../../../schema/package.dhall

in S.Judgement::{
     name = "customer-data-review",
     version = Some "1.0.0",
     instructions = ''
       Review fixtures, logs, and documentation. Synthetic examples are acceptable.
     '',
     checks =
       [ S.Check::{
           name = "real-customer-data",
           question = "Does this change add information about a real customer?",
           blockAt = 0.5,
           passAt = 0.1
         },
         S.Check::{
           name = "undocumented-export",
           question = "Do the privacy notes mention every data export this change adds?",
           concernWhen = S.Answer.No,
           enforcement = S.Enforcement.Advisory,
           blockAt = 0.8,
           passAt = 0.4
         }
       ]
   }
```

The field names and numbers above illustrate the contract; the schema work in M2 settles the spelling. The two checks show the point of the design: the same judgement holds a strict enforced check and a lenient advisory one, and the second is asked in the direction where no is the concern.

The relative import above illustrates a repository fixture under `.seihou/modules/NAME` only. Real generated consumer scaffolds must contain the published immutable schema URL/hash from `Seihou.CLI.SchemaVersion`, not a source-checkout-relative import. No consumer is asked to repair that import manually.

Continue through the public commands:

```bash
seihou validate-judgement customer-data-review
seihou judgement eval customer-data-review --offline
seihou judgement eval customer-data-review
seihou run customer-data-review
seihou list --judgements
seihou check customer-data-review
```

The live evaluation uses the explicitly selected permitted route; offline evaluation labels itself as corpus/scanner/policy validation. Apply previews the changed project intent and hook setup. The named check reads the active snapshot and reports which version/definition was reviewed. A typical human block has this meaning; wording may improve without changing the structured codes:

```text
security-review  BLOCKED
Scope: staged changes; complete for 3 changed text files
config/example.env:12  critical  embedded-credential
Remove the credential from the staged content, then run seihou check.
No remote review was requested. No commit was created.
```

A semantic review that lands between the thresholds reads like this, with the numbers illustrative:

```text
customer-data-review  NEEDS REVIEW
Scope: staged changes; complete for 2 changed text files
real-customer-data    needs review  model-reported probability 0.41 (pass at 0.10, block at 0.50)
undocumented-export   passed        cleared by gate, probability 0.03 (advisory)
fixtures/accounts.json:8  medium  customer-record
Confirm the record is synthetic, or remove it, then run seihou check.
No commit was created.
```

For a clone or linked worktree, from its project root:

```bash
seihou sync --dry-run
seihou sync
seihou check --dry-run
```

For CI, with required base history fetched and a trusted base containing the adopted policy:

```bash
seihou check --range origin/main..HEAD --policy-ref origin/main --json
```

The command resolves both refs to immutable commits at startup and returns nonzero for blocked, uncertain or failed enforced checks. First adoption without a trusted base policy needs explicit CI configuration/review rather than pretending there is an existing baseline.

Run focused tests while implementing, then these final source checks after all code/schema/build changes:

```bash
nix develop -c cabal test all --test-show-details=direct
nix develop -c bash nix/check-record-conventions.sh
nix develop -c bash nix/check-cli-module-placement.sh
nix fmt
nix flake check
git diff --check
```

Record provenance revisions with the skill script when implementation begins, and use Conventional Commits with `ExecPlan: docs/plans/110-add-first-class-user-defined-judgements-backed-by-shikumi.md` and the frontmatter `Intention:` trailer. Continue on the current branch unless the user requests a branch. Use the release skill only when executing the delivery milestone, and record its actual published/installed validation separately from source checks.


## Validation and Acceptance

The early integration proof is M1's real pre-change consumer using the actual public commands and the actual managed-hook environment. The uncertain boundaries are schema-to-artifact decoding, typed Shikumi replies, scanner-to-snapshot mapping, and hook composition. Prove each through that path before broadening combinations. No private fixture script may perform schema adoption, hook repair, index changes, provider configuration or artifact resolution that the normal command omits.

Artifact acceptance includes project-local and installed custom definitions, direct application and transitive module/recipe references, registry collision/validation behavior, immutable schema imports and packaged scaffolds. Applying the same judgement twice is idempotent. An updated definition is an explicit reviewed project-intent change. Removing one owner preserves others, and fresh checks use the recorded definition with an empty artifact cache.

Evidence acceptance covers staged versus unstaged differences, partially staged files, renames, deletion context, filenames requiring NUL-delimited parsing, unresolved index entries, binary/LFS/submodule exclusions, input limits, a finding beyond 4,000 characters, and a secret added then removed inside a commit range. Invalid Git reads, uncovered required content and truncated model inputs are errors. Scope and coverage are independently measured by Seihou. Tests must verify actual input blob IDs as well as final verdicts.

Security acceptance uses synthetic credentials only. A scanner block prevents every remote request, including AI commit-message generation. An approved remote semantic review receives only the permitted scope after preflight; local-only policy never falls back to remote processing. Injected instructions in evidence, unknown categories, invented locations, oversized output, echoed secrets, malformed JSON, timeout, provider refusal and missing scanner each produce bounded redacted output and the intended nonzero outcome. Test sentinel strings must be absent from stdout, stderr, ignored reports and configured telemetry sinks. A clean scanner report is never described as a proof that semantic review is complete.

Gate acceptance observes ordinary Git and all three Seihou commit paths. The same inputs produce the same policy decision regardless of entry point. A fixed commit message does not skip checking. Generation success followed by a judgement block returns nonzero and explains the remaining applied changes. Earlier hooks and concurrent ordinary edits invalidate stale snapshots. Existing hooks still run in their supported order; no hook installation writes outside the selected checkout/configuration boundary without a visible preview. Dry-run and check do not mutate setup or tracked state. CI uses trusted policy independently of the proposed change and detects intermediate leaking commits.

Evaluation acceptance separates offline runtime/protocol correctness from real model quality. Run the labelled release corpus against the documented route, report missed unsafe examples and false blocks independently, and satisfy M6's stated thresholds. Record the rubric digest, corpus revision, provider/model identity, thresholds, runtime/package versions, errors, uncertainty and latency. Offline tests prove the band arithmetic with stubbed probabilities; only the live corpus run says anything about where a real model's probabilities fall. Synthetic examples and finite observed rates do not justify a universal "safe to commit" guarantee. Future optimizer/calibration features may be evaluated later; they must not silently rewrite an active rubric or policy.

Delivery acceptance requires the released schema import, source archive contents, scanner availability, packaged Seihou and installed executable to pass the exact consumer workflow. Record the commands and version outputs for macOS and Linux when supported; an untested platform remains a named delivery limitation. Neither source tests nor a successful release upload proves that the installed user's binary works. M7 remains open until installed verification succeeds, or the final handoff explicitly identifies its remaining release/installation gap.


## Idempotence and Recovery

Judgement creation refuses an existing destination. Validation, evaluation planning, check and dry-run do not alter project intent, staging or hook setup. Live evaluation may incur provider cost, which help reports; retry is bounded and never used to erase an adverse decision. Reapplying an identical definition/policy does not duplicate owners or hook entries.

Manifest capability upgrades are adjacent and deterministic where evidence permits. Apply/update publish definitions and ownership only after full validation, using existing atomic/transactional publication boundaries. A failed check cannot leave a pass receipt. Failed hook setup is reported as failed adoption/setup rather than as operational enforcement; restore only unchanged owned contributions and preserve user edits. A later `seihou sync` converges from recorded intent after an interrupted setup.

Checks are read-only with respect to the Git index and worktree. If Seihou staged generated files before a block, it leaves them staged and explains that the commit was not created. Do not clean up unrelated staged files, reset the index or roll back arbitrary shell effects. Re-running after the developer corrects content gathers a new snapshot. Old reports are diagnostic observations and never authorize a different tree.

Temporary scanner material is private and short-lived. Default reports are ignored, sanitized and replaceable; deleting them does not change policy or disable checks. No default raw replay archive or shared model cache exists for sensitive reviews. Hook retirement removes only a byte-identical owned contribution or restores the recorded original local integration when still unchanged; third-party changes cause a named conflict, not destructive cleanup.

Use disposable clones/worktrees and isolated configuration for acceptance. Keep any original index, hooks and user configuration untouched. Publishing producer artifacts and installing releases are distinct delivery actions; follow the repository's release procedure and retain existing release tags. Do not amend unrelated commits or create a feature branch as incidental planning work.


## Interfaces and Dependencies

There is no parent MasterPlan or prerequisite child plan. Schema publication and the released Shikumi APIs used by the implementation are integration dependencies owned by this delivery, not reasons to leave authoring or consumer adoption to another unspecified task. Re-read producer instructions before editing another repository and use canonical Mori references in durable cross-repository messages.

`seihou-core/src/Seihou/Core/Judgement.hs` owns the following conceptual interfaces. Final constructor details may follow repository conventions, but the distinctions are acceptance requirements:

```haskell
data JudgementStatus = Passed | Blocked | NeedsReview | Failed | NoChanges
data JudgementEnforcement = Enforced | Advisory
data EvidenceScope = StagedChanges | CommitRange CommitId CommitId

-- Records are strict and Generic in the implementation.
-- Definition: artifact identity/version, shared instruction, evidence scopes
--   and path filters, deterministic checks, limits, and a nonempty list of
--   checks. A check: name, question, concern direction, guidance,
--   categories, default enforcement, default review and gate thresholds,
--   gate opt-out.
-- Every probability below is the probability of the concern, already
--   complemented by the adapter where a check's concern is a no answer.
-- Input: immutable evidence records with safe file IDs and coverage metadata.
-- Output, per check: the review probability and, when a gate ran, the gate
--   probability, as plain numbers; typed findings; an explicit request for
--   human review; which route decided. No Shikumi type appears here.
-- Policy: permitted data destinations, whether a gate is permitted, and per
--   check name the enforcement, thresholds and severity/category rules.
-- Report: per check the status, findings, probabilities and thresholds
--   applied; overall execution status, coverage, decision and provenance.
-- Nothing above names secrets, credentials or security.

decideCheck
  :: CheckPolicy
  -> CheckObservation
  -> CheckDecision

validateJudgementOutput
  :: JudgementDefinition
  -> JudgementInput
  -> JudgementOutput
  -> Either JudgementError JudgementOutput

decideJudgement
  :: JudgementPolicy
  -> JudgementObservation
  -> JudgementDecision
```

The status report may use separate execution and decision fields instead of one sum if that makes advisory and coverage behavior clearer; do not collapse successful execution into approval. Findings include a declared category, severity, validated source location, sanitized explanation and supported remedy. Seihou supplies actual coverage and snapshot identity. Empty evidence is NoChanges, deliberate exclusions are counted, and absent/malformed evidence cannot become Passed.

`seihou-cli/src/Seihou/CLI/Judgement/Runtime.hs` owns the only conversion to Shikumi types:

```haskell
-- Private to the module: the Shikumi programs and their wire records.
reviewProgram
  :: JudgementDefinition
  -> JudgementCheck
  -> Program ReviewRequest ReviewReply

gateProgram
  :: JudgementDefinition
  -> JudgementCheck
  -> Program ReviewRequest GateReply

-- Exported: Seihou types only. The effect row follows the module's needs.
runJudgement
  :: JudgementExecution
  -> JudgementDefinition
  -> JudgementInput
  -> Eff es (Either JudgementError JudgementObservation)
```

The program runs over private records because the reply needs Shikumi's decision field type, which must not leak into `seihou-core`:

```haskell
data ReviewReply = ReviewReply
  { concern :: !(Field "Is the answer to the question in the instructions yes?" Noul)
  , findings :: !(Field "Each place the concern appears, with its category, severity and location" [ReplyFinding])
  , needsHumanReview :: !(Field "True when the evidence cannot be judged with confidence" Bool)
  }

-- Derives DecisionOutputs, so it can run on a judgment-only model.
newtype GateReply = GateReply
  { concern :: Field "Is the answer to the question in the instructions yes?" Noul
  }
```

The field descriptions are compile-time text, so they are deliberately subject-neutral; everything specific to a check travels in the run-time instruction.

The fixed question wording is illustrative and is settled in M1 against a live route. The module constructs the typed signature from author instructions, runs bounded provider effects, validates results and converts typed Shikumi errors into Seihou errors. `runJudgement` accepts a Seihou execution configuration and returns a Seihou observation holding each check's probabilities. Public schemas, manifest encodings, core policy tests and CLI callers must not import Shikumi `Params`, tracing records or decision types. Tests can supply a typed interpreter through this same service boundary.

Persisted definition digests cover the normalized definition bytes and schema/contract version. Snapshot identity covers ordered blob/commit identities and evidence scope. An approval identity additionally includes all active definition digests, effective policy, selected provider/model and relevant request configuration. These are invalidation keys, not artifact identities or permanent attestations. Do not serialize credentials or model-generated content into applied state.

The initial public contract supports custom instructions/categories and synthetic evaluation corpora over staged/commit-range evidence. It does not add arbitrary executable judgement plugins, user-defined output schemas, automatic fixes, an agent tool loop, background daemons, per-user approval bypasses, whole-history retroactive scanning, automatic rubric optimization, or automatic threshold fitting. It supports author-defined yes/no checks only, each with a declared concern direction: no `Choice` or `Score` outputs, no judgment-only model as the sole reviewer, and no evidence scopes or deterministic checks beyond the closed sets named above. Those sets, the check record and the report are versioned so that further scopes, further deterministic checks, ReAnchor-fitted thresholds and a single-call form of multiple checks can be added without breaking existing artifacts. Thresholds shipped as defaults must come from the M6 corpus on a named route; do not present a model-stated probability as a calibrated one.

Add `shikumi`, `shikumi-eval` where evaluation needs it, `baikai-effectful`, and `baikai-typesafe` for the gate to the internal CLI library, and raise the existing `baikai`, `baikai-claude`, `baikai-openai` and `baikai-kit` bounds to the line the selected Shikumi release requires. On 2026-11-11 that means `shikumi` 0.5.1.0 with `baikai` 0.10 and `baikai-effectful` 0.4.0.5; `baikai-effectful` 0.5.0.0 is outside Shikumi 0.5.1.0's bound. Do this only after inspecting current source through Mori and checking Hackage/upstream tags, and select and test concrete bounds at implementation time. `baikai-typesafe` is 0.1.0.1 on that date. Add no `shikumi-optimize`, `shikumi-cache` or Handan dependency. The packaged Gitleaks adapter uses a verified released CLI contract and local configuration owned by the selected project policy. The existing Seihou executable remains the single user entry point; no separate judgement host installation is required.
