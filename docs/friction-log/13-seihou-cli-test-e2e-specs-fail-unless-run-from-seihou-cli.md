---
type: Friction Entry
title: "seihou-cli-test e2e specs fail unless run from seihou-cli/"
description: "The seihou-cli test binary resolves the schema submodule relative to its working directory, so running it from the repository root fails about 90 end-to-end specs with a misleading git error, and cabal test --test-options cannot carry a -p pattern with spaces or ||."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-11T14:59:08Z"
frictionId: FRIC-13
status: logged
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/122-fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md"
workaround: "cd seihou-cli before running $(cabal list-bin seihou-cli-test); all 905 tests then passed"
---
# seihou-cli-test e2e specs fail unless run from seihou-cli/

## Attempted

Running a filtered and then the full seihou-cli-test suite; first cabal test --test-options="-p '/batch/ || /refused/'", then $(cabal list-bin seihou-cli-test) from the repository root

## Encountered

cabal test rejected the pattern as not valid; the direct binary run from the root reported 90 of 902 failures, all with git -C …/seihou-project/schema ls-tree … (exit 128)

```text
readCreateProcess: git "-C" "/Users/shinzui/Keikaku/bokuno/seihou-project/schema" "ls-tree" "--name-only" "e9f91438…" (exit 128): failed
```

## Workaround

cd seihou-cli before running $(cabal list-bin seihou-cli-test); all 905 tests then passed
