# seihou check

Run the project's active judgements over the staged changes and report a decision.

```sh
seihou check [NAME] [--staged] [--dry-run] [--json]
```

`seihou check` reads the judgements recorded in `.seihou/manifest.json`, captures the
staged index exactly as Git will commit it, and runs every active judgement. It is
read-only: it never stages or unstages files, writes the manifest, or changes hook
setup. The pre-commit hook that `seihou run JUDGEMENT` installs runs
`seihou check --staged`.

`NAME` runs one active judgement, for diagnosis. It is not a substitute for running
all of them. `--staged` states the default scope explicitly. `--dry-run` prints each
judgement, its review route, data policy, scanner, the files in scope and how they
are chunked, and each check's thresholds, then exits without any model request; it
never claims approval. `--json` prints one versioned report (`"version": 1`).

## Exit status

| Status | Meaning |
|---|---|
| 0 | every enforced check passed, or there was nothing to check |
| 10 | an enforced check, or a deterministic finding, blocked |
| 11 | an enforced check needs human review |
| 1 | an error: configuration, a failed review, unreadable Git state, or incomplete coverage |

When enforced checks disagree, the most severe status wins, in the order blocked,
needs review, error. An advisory check reports its real status and is marked
`(advisory)`, but never decides the exit status.

## Evidence

Seihou reads the index with `git ls-files --stage` and `git diff-index --cached`
against `HEAD` (or the empty tree before the first commit), and reads each changed
blob with `git cat-file`; it never reads the working tree. External diff and text
conversion are disabled. A merge with unresolved entries is refused. Deleted,
binary, Git LFS pointer, submodule, symlink and oversized content is listed as not
reviewed; a judgement with uncovered files in scope cannot pass. A judgement's
`evidence` declaration narrows which paths it reads.

## Transmission

Before any request, gitleaks scans every outgoing file and instruction with its
built-in rules only. Flagged material is never sent. For a judgement that declares
`SecretScan`, such as the bundled `security-review`, each hit is a blocking finding
reported by rule and location, never by matched text, and nothing else is sent. For
any other judgement, the affected checks end as errors naming the file. The project
data policy must be `approved-remote` for a hosted route; every route in this
release is hosted, including the `claude-cli` and `codex-cli` providers, which run
in an empty directory with tools disabled.

## Reports

Each check line shows its status, the model-reported probability of the concern, and
the thresholds applied. For a check whose concern is a no answer, the report says the
figure is one minus the model's probability of yes. Findings show the location, the
category's authored severity, the category and a bounded explanation. The last line
names the route and the model the provider reported.

## See also

- [`seihou judgement`](judgement.md) for evaluation and policy changes
- [`seihou new-judgement`](new-judgement.md) and [`seihou validate-judgement`](validate-judgement.md)
- [Judgements guide](../user/judgements.md)
