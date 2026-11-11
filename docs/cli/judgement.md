# seihou judgement

Evaluate a judgement against labelled examples, and configure its route and policy.

```sh
seihou judgement eval NAME [--offline]
seihou judgement configure NAME [--provider PROVIDER] [--model MODEL]
    [--data-policy local-only|approved-remote] [--no-gate]
    [--check CHECK] [--enforcement enforced|advisory]
    [--block-at P] [--pass-at P] [--gate-block-at P] [--gate-pass-at P]
    [--global] [--dry-run]
```

`NAME` is a judgement directory, its `judgement.dhall`, or a judgement name found in
`.seihou/modules`, the user modules directory or the install cache.

## eval

`eval` validates the judgement and its `examples.json` exactly as
[`validate-judgement`](validate-judgement.md) does, then sends every example to the
configured review route through the same program a commit uses, one request per
check per example. It reports each case's outcome next to its expected one and, per
check, the number of correct cases, missed unsafe cases (expected blocked, passed),
false blocks (expected passed, blocked), undecided cases (needs review) and errors,
plus mean latency.

Each case's result is retained, so a threshold sweep below each check shows how the
counts would change under other pass/block pairs without further model calls. The
counts apply to the named route only. Evaluation proposes nothing and writes
nothing; change the definition yourself. Live evaluation may cost money.

`--offline` validates the corpus and runs the deterministic secret scan over the
examples, without any model request. It does not measure model accuracy and is not
a gate approval.

## configure

`--provider` and `--model` choose the review route, written to the project-local
configuration as `judgement.provider` and `judgement.model` (or the global one with
`--global`). They are equivalent to `seihou config set`. No model identifier is
guessed. `--data-policy` writes `judgement.dataPolicy`, which adoption reads; for an
active judgement it also changes the recorded policy. A `local-only` policy is
refused, because every review route in this release sends material to a hosted
service.

`--enforcement`, `--block-at`, `--pass-at`, `--gate-block-at` and `--gate-pass-at`
change the recorded policy of an active judgement. Thresholds apply to one check
named with `--check`; `--enforcement` without `--check` applies to every check. The
command prints the change and writes the manifest atomically; `--dry-run` writes
nothing. An inverted pair (pass above block) or a value outside 0 to 1 is refused.

`--gate-provider` and `--gate-model` are refused in this release: no judgment-only
provider is built in, and the generative review decides every check.

Provider credentials are never stored by Seihou; they stay in the provider's own
environment variables or credential store.
