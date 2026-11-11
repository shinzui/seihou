JUDGEMENTS

A judgement checks the staged changes before each commit. It holds a list of
yes/no questions (checks) that Seihou asks a model about the exact bytes in the
Git index, plus optional deterministic checks such as a local secret scan.
Seihou, not the model, decides the outcome from the model's answer and the
project's recorded policy.

Seihou ships one judgement, security-review, which blocks commits that add
credentials or confidential information. Authors write their own with
seihou new-judgement.

ADOPTING THE BUILT-IN SECURITY REVIEW

  seihou config set judgement.provider claude-cli
  seihou config set judgement.model claude-sonnet-5
  seihou config set judgement.dataPolicy approved-remote
  seihou run security-review --dry-run
  seihou run security-review

Adoption previews the definition, the review route, the data policy, the
scanner and the pre-commit hook change, then records the judgement in
.seihou/manifest.json and installs the hook. Commit the manifest change. Run
interactively, seihou run asks before permitting the route instead of reading
judgement.dataPolicy. Without a route, a data policy or gitleaks, adoption
names what to set and activates nothing.

WHAT A CHECK DECIDES

  Each check is one question, such as "Does this change add a credential?".
  concernWhen says which answer is the problem (yes by default). The model
  states the probability of yes; Seihou converts it to the probability of the
  concern, so a higher number is always worse.

    at or above blockAt         blocked
    between passAt and blockAt  needs human review
    at or below passAt          may pass

  A located finding blocks when its category's authored severity is at or
  above the check's blockingSeverity. A deterministic finding (the secret
  scan) always blocks. Missing, malformed or incomplete results are errors,
  never passes. An advisory check reports its real status without deciding
  the exit code.

  These probabilities are stated by the model. They are not calibrated
  measurements, and the same thresholds mean different things on another
  model. Use seihou judgement eval to see how a route decides your examples.

SECRETS AND TRANSMISSION

  Before anything is sent to a hosted route, gitleaks scans every outgoing
  file and instruction with its built-in rules; repository allow-comments,
  ignore files and GITLEAKS_* variables are ignored. Material it flags is
  never sent. For a judgement that declares the secret scan, such as
  security-review, a hit is a blocking finding. For any other judgement the
  affected checks end as errors naming the file. Every route in this release
  sends content to a hosted service, even the CLI providers. Provider
  credentials stay in that provider's own environment or credential store.

RUNNING A CHECK

  seihou check                   all active judgements on the staged changes
  seihou check NAME              one judgement, for diagnosis
  seihou check --dry-run         plan only: no model request, no approval
  seihou check --json            versioned JSON report
  seihou check --range origin/main..HEAD --policy-ref origin/main
                                 every commit in a range (for CI), against the
                                 judgements recorded at a trusted ref

  Exit status: 0 passed or nothing to check, 10 blocked, 11 needs human
  review, 1 error. The pre-commit hook runs seihou check --staged. It is
  written beside an existing hook (which runs first) or, for a pre-commit
  framework hook, as pre-commit.legacy, which that framework runs first.

WRITING A JUDGEMENT

  seihou new-judgement customer-data-review
  $EDITOR .seihou/modules/customer-data-review/judgement.dhall
  $EDITOR .seihou/modules/customer-data-review/examples.json
  seihou validate-judgement customer-data-review
  seihou judgement eval customer-data-review --offline
  seihou judgement eval customer-data-review
  seihou run customer-data-review

  examples.json holds synthetic labelled cases. Evaluation sends them to the
  configured route; validation scans them for credentials first.

REFERENCES FROM MODULES AND RECIPES

  A module or recipe lists judgements = [ S.JudgementRef::{ name = "..." } ],
  optionally with when = Some "<condition>". seihou run adopts the referenced
  judgements of the whole composition after generating its files.

CHANGING POLICY

  seihou judgement configure NAME --check CHECK --block-at 0.6 --pass-at 0.2
  seihou judgement configure NAME --enforcement advisory
  seihou judgement configure NAME --provider codex-cli --model MODEL

SEIHOU'S OWN COMMITS

  seihou run, update and migrate with --commit run every active judgement on
  the staged changes before producing a commit message, so nothing reaches an
  AI commit-message generator unreviewed. A block leaves the changes applied
  and staged, exits nonzero and says "Changes applied; commit blocked".

LIMITS IN THIS RELEASE

  The judgment-only gate is not available. git commit --no-verify skips the
  hook; run seihou check --range with --policy-ref in CI to enforce
  judgements independently of local hooks.

SEE ALSO

  seihou check --help
  seihou judgement eval --help
  seihou judgement configure --help
  seihou help workflow
