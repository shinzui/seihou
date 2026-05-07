---
id: 21
slug: enforce-cli-library-first-convention
title: "Add an Automated Enforcement Check for the CLI Library-First Convention"
kind: exec-plan
created_at: 2026-04-27T02:09:55Z
intention: "intention_01kq63sz0ced98e23qvad7zpnp"
master_plan: "docs/masterplans/2-cli-library-first-convention.md"
---


# Add an Automated Enforcement Check for the CLI Library-First Convention

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this plan, a small enforcement script catches every future violation of the
CLI library-first convention before it reaches `master`. The script reads
`seihou-cli/seihou-cli.cabal`, walks `executable seihou`'s `other-modules`, and
fails when an entry does not import one of the recognised executable-only
dependencies (`Options.Applicative`, `Data.FileEmbed`, `GitHash`,
`Paths_seihou_cli`) and is not transitively trapped via importing another
executable-only seihou module. The script wires into `flake.nix`'s `checks`
attribute so `nix flake check` runs it, and into the existing pre-commit
configuration so a normal commit is rejected if it adds a trapped helper to the
executable.

Why this matters: the convention documented in
`docs/dev/architecture/overview.md` (sibling plan
`docs/plans/18-document-cli-library-first-convention.md`) and encoded in the
cabal layout (sibling plan
`docs/plans/19-restructure-cli-cabal-library-first.md`) is socially and
mechanically expressed but not actively guarded. A future contributor who
adds a new pure helper directly to `executable seihou`'s `other-modules`
will not see any error from `cabal build`; both targets share
`hs-source-dirs: src`, so cabal accepts the placement. Without an automated
check, the convention will erode the same way the original
"helpers-in-the-executable" pattern did. The check makes the convention
mechanical: violating it produces a build failure with a clear remediation
hint.

Observable outcome: after this plan ships,

    nix flake check

includes a `cli-module-placement` check that succeeds against `master`. A
deliberate test:

    # In a scratch worktree, add a violating module to the executable's
    # other-modules:
    sed -i.bak '/^    Paths_seihou_cli$/a\    Seihou.CLI.RemoteVersion' \
        seihou-cli/seihou-cli.cabal
    nix flake check 2>&1 | rg "Seihou.CLI.RemoteVersion"

prints a violation message naming `Seihou.CLI.RemoteVersion` and pointing
the contributor at `docs/dev/architecture/overview.md` section "CLI Module
Placement Convention". Restore the file with `mv seihou-cli/seihou-cli.cabal.bak
seihou-cli/seihou-cli.cabal`.

Equivalently, if the contributor forgets `nix flake check` and tries to
commit the violation, the pre-commit hook catches it at commit time with
the same message.


## Progress

- [x] Confirm the post-EP-3 layout: `executable seihou`'s `other-modules` is annotated; `Seihou.CLI.AgentLaunch` is in the library; `Seihou.CLI.AgentLaunchExec` is in the executable; `Seihou.CLI.SchemaVersion` is in the library; `Seihou.CLI.Outdated`'s re-exports are gone.
- [x] Decide the script location and language. Bash at `nix/check-cli-module-placement.sh`.
- [x] Implement the script. Adapted to the post-EP-2 source-dir split (reads `seihou-cli/src-exe`, not `seihou-cli/src`). Robust repo-root resolution covers direct invocation, `pkgs.runCommand`, and the pre-commit hook.
- [x] Verify the script passes against the current tree. Output: `OK: 24 modules in executable other-modules, all justified.`
- [x] Wire the script into `flake.nix`'s `checks.<system>` attribute as a new `cli-module-placement` check.
- [x] Wire the script into `flake.nix`'s `pre-commit-check.hooks` block so violations fail at commit time.
- [x] Verify the deliberate-violation test: temporarily added `Seihou.CLI.RemoteVersion` to the executable's `other-modules`; `nix flake check` failed with the script's `FAIL:` message naming the module; restored the cabal file and confirmed the check passes again.
- [x] Update the project-root `CLAUDE.md` with a one-line pointer to the check.
- [x] Add a CHANGELOG entry to `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- **The pre-EP-4 tree was not as clean as the masterplan claimed.** The
  first run of the script flagged three violations:
  `Seihou.CLI.Completions.{Bash,Fish,Zsh}`. These shell-completion text
  generators import only `Data.Text` and `Seihou.Prelude`; nothing
  exec-only and no transitive trap. The audit captured by EP-1 had
  classified them as "shell-specific completion modules" and assumed
  they belonged in the executable, but the strict import-based rule
  disagreed. Fixed by promoting all three to
  `seihou-cli-internal`'s `exposed-modules` (a pure cabal edit plus
  three `git mv` from `src-exe/Seihou/CLI/Completions/` to
  `src/Seihou/CLI/Completions/`). The dispatcher
  `Seihou.CLI.Completions` stayed executable-side (transitively
  trapped via `Seihou.CLI.Commands`). After the move, the count of
  modules in the executable's `other-modules` dropped from 27 to 24.
  This is the first concrete payoff of the enforcement check: it
  caught a soft assumption the human audit had missed.

- **`Seihou.CLI.AgentLaunchExec` is the only "intentional" exemption.**
  It imports neither the four trapping deps nor any transitively
  trapped seihou module — it imports the library `Seihou.CLI.AgentLaunch`
  and wraps it with `findExecutable`/`rawSystem`/`exitWith`. By the
  strict closure rule, it is a violation. By design it lives next to
  the agent-prompt wrappers that consume it, so it stays
  executable-side via an `EXEMPT_MODULES` entry with an inline comment
  pointing at EP-3.

- **The script's repo-root resolution had to handle three callers.**
  Initial implementation used `BASH_SOURCE[0]` to compute `REPO_ROOT`,
  which is correct for direct invocation but resolves to `/nix/store/...`
  when pre-commit copies the script. The fix prefers `$PWD` (which
  pre-commit and `pkgs.runCommand` both set to the repo root) with a
  `BASH_SOURCE` fallback for ad-hoc invocations from elsewhere, plus a
  `SEIHOU_REPO_ROOT` env-var override for CI flexibility.

- **`pkgs.runCommand` requires explicit `nativeBuildInputs` for shell
  utilities.** The script uses `awk`, `grep`, `find`, `sed`, and
  `sort`. The Nix sandbox does not provide a default `PATH`, so the
  flake check declares all five (`gawk`, `gnugrep`, `findutils`,
  `gnused`, `coreutils`) plus `bash` itself.

- **`nix flake check`'s `pre-commit-check` derivation already
  exercises the new hook end-to-end.** Adding a hook to
  `pre-commit-check.hooks` causes `pre-commit run --all-files` to
  invoke it during `nix flake check`, so the deliberate-violation
  test verified both the standalone `cli-module-placement` derivation
  and the pre-commit wiring in one run.


## Decision Log

- Decision: Implement the check as a small Bash script (or POSIX-shell
  script) rather than a Haskell binary.
  Rationale: The check is a build-system concern, not a code-style concern.
  Parsing the cabal file's `other-modules` list and grepping each named
  source file for one of four imports is naturally a shell script. A
  Haskell binary would require a new test-suite or executable target,
  complicate `flake.nix`, and increase the build closure for what is
  fundamentally a one-shot text inspection. If the heuristic ever needs
  to handle module-name parsing edge cases (CPP-conditional imports,
  `import X qualified`), revisit the language choice; the path the script
  lives at and its CLI surface should remain stable.
  Date: 2026-04-26.

- Decision: Treat "imports another executable-only seihou module" as a
  fifth, transitive trapping criterion alongside the four explicit
  Haskell-package dependencies.
  Rationale: `Seihou.CLI.Commands` is trapped by `Options.Applicative`.
  Eighteen handler modules import `Commands` for their `Opts` types and
  are therefore transitively trapped. Stating the rule transitively in
  the script means we do not have to maintain a static list of trapped
  handlers; the script computes the closure. This matches the rule's
  formulation in `docs/dev/architecture/overview.md` section "CLI Module
  Placement Convention" and in sibling plan
  `docs/plans/19-restructure-cli-cabal-library-first.md`'s Decision Log.
  Date: 2026-04-26.

- Decision: Maintain a small `EXEMPT_MODULES` list in the script for
  modules that legitimately stay in the executable despite not matching
  the heuristic. `Paths_seihou_cli` is the only known exemption today
  (it is auto-generated by Cabal; the script cannot read its source
  because none exists on disk).
  Rationale: Exemptions are rare but real. A static list with inline
  comments keeps the rationale visible; a future exemption requires an
  explicit edit and a code-review conversation.
  Date: 2026-04-26.

- Decision: Hook the script into the existing `pre-commit-check.hooks`
  block in `flake.nix` rather than introducing a separate
  `.pre-commit-config.yaml`.
  Rationale: The repository already drives pre-commit via the
  `pre-commit-hooks.nix` flake input (lines 51-58 of `flake.nix` as of
  2026-04-26). Adding a hook there reuses the existing wiring and
  ensures `nix develop` automatically installs the updated hook.
  Introducing a `.pre-commit-config.yaml` would split the configuration
  surface across two files.
  Date: 2026-04-26.


## Outcomes & Retrospective

The convention is now mechanically guarded. Every PR that adds a new
helper to `executable seihou`'s `other-modules` will fail the
`cli-module-placement` check unless the helper imports one of the
recognised trapping dependencies, transitively imports an already-trapped
seihou module, or is added to `EXEMPT_MODULES` with an inline
justification.

What worked:

- The script's structure (extract → closure → check) maps cleanly
  onto the three-paragraph rule in the architecture doc, and the FAIL
  message echoes the same three options a contributor has for fixing
  a violation. The doc and the script stayed in lock-step.
- Wiring through `flake.nix`'s existing `pre-commit-check.hooks`
  block — rather than introducing a separate `.pre-commit-config.yaml` —
  meant `nix develop` regenerated `.git/hooks/pre-commit`
  automatically. No new flake input needed.
- The deliberate-violation test (`Seihou.CLI.RemoteVersion` in the
  executable's `other-modules`) drove `nix flake check` to fail with
  the exact `FAIL:` message the contributor would see, including the
  pointer at the architecture doc. The end-to-end loop is short.

What was unexpected:

- The masterplan's claim that "EP-4 starting position is now clean"
  was off by three modules. The script's first run flagged
  `Completions.{Bash,Fish,Zsh}` as violations. The fix was a
  one-commit promotion to the library plus a Surprises & Discoveries
  entry. This validates the masterplan's framing that the human audit
  could miss things and the mechanical check is the safety net.
- The original plan's script used `seihou-cli/src` as `SRC_DIR`. EP-2's
  source-dir split made `src-exe/` the right target. The plan body
  was authored before EP-2 landed and never refreshed — same lesson
  as the EP-3 retrospective.

Follow-ons (not blocking):

- The error message references `${BASH_SOURCE[0]}` literally, which
  resolves to a `/nix/store/...` path under pre-commit. A future
  improvement could detect this and report
  `nix/check-cli-module-placement.sh` instead. Low priority — the
  contextual hint and the `EXEMPT_MODULES` mention together still
  point a reader at the right file.
- If the convention's transitive-trap rule ever needs to recognise
  imports under `import qualified ... as Alias`, the
  `seihou_imports` function would need to handle `as` alias syntax.
  Currently any reasonable `import` line is accepted because we only
  use the module name (the first whitespace-separated token).


## Context and Orientation

This subsection orients a reader who has only this plan and the working
tree.

The repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` is
a multi-package Haskell (GHC2024) cabal workspace. This plan touches:

- `flake.nix` at the repo root — declares the flake's outputs including
  `checks.<system>` (consumed by `nix flake check`) and a
  `pre-commit-check` block driven by the `pre-commit-hooks` input. As of
  2026-04-26 the `checks` attribute contains `formatting` and
  `pre-commit-check`. The `pre-commit-check.hooks` block currently has
  one entry, `treefmt`.
- `nix/` — directory adjacent to `flake.nix` containing
  `haskell-overlay.nix`. The new script will live here as
  `nix/check-cli-module-placement.sh`. If `nix/` does not exist as a
  directory in the working tree, create it.
- `seihou-cli/seihou-cli.cabal` — the cabal file the script reads. After
  sibling plans 18-20 land, the `executable seihou`'s `other-modules`
  list contains roughly 25-27 entries, each annotated with a one-line
  cabal comment.

`Seihou.CLI.RemoteVersion` is a stable, library-exposed module with no
executable-only imports — a good fixture for the deliberate-violation
test in the Purpose section. It will not change as part of this plan.

The convention this plan enforces is documented at
`docs/dev/architecture/overview.md` section "CLI Module Placement
Convention" and mirrored in `CLAUDE.md` and `docs/dev/contributing.md`
(all created by sibling plan
`docs/plans/18-document-cli-library-first-convention.md`).

Key terms:

- **"Executable-only Haskell-package import"**: an import of one of the
  four Haskell modules whose presence justifies executable-only
  placement: `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
  `Paths_seihou_cli`.
- **"Transitive trap"**: a module imports another executable-only
  seihou module (most commonly `Seihou.CLI.Commands`). The transitive
  trap is what keeps eighteen handler modules in the executable target
  without requiring the script to maintain a static list of them.
- **"Closure computation"**: the script's algorithm for finding all
  trapped modules. It starts with the modules that have an
  executable-only Haskell-package import, then iteratively adds modules
  that import any already-trapped seihou module, until the set
  stabilises. Any module in `executable seihou`'s `other-modules` that
  is not in this closure (and is not on the `EXEMPT_MODULES` list) is a
  violation.


## Plan of Work

This plan has three milestones.


### Milestone 1: Implement the script

Scope: write `nix/check-cli-module-placement.sh`, a self-contained Bash
script that parses the cabal file, computes the executable-only closure,
and reports violations. Make the script executable (`chmod +x`).

What will exist at the end: the script exists, is executable, and
returns 0 against the current tree.

Acceptance: running

    bash nix/check-cli-module-placement.sh

prints a one-line summary like "OK: 26 modules in executable other-modules,
all justified" and exits 0.

The script:

    #!/usr/bin/env bash
    # nix/check-cli-module-placement.sh
    #
    # Enforces the CLI library-first module-placement convention. See
    # docs/dev/architecture/overview.md section "CLI Module Placement
    # Convention" for the rule. Reads seihou-cli/seihou-cli.cabal, walks
    # the executable's other-modules, and fails if an entry does not
    # import one of the four executable-only Haskell-package dependencies
    # (Options.Applicative, Data.FileEmbed, GitHash, Paths_seihou_cli)
    # and is not transitively trapped via importing another
    # executable-only seihou module.

    set -euo pipefail

    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CABAL_FILE="${REPO_ROOT}/seihou-cli/seihou-cli.cabal"
    SRC_DIR="${REPO_ROOT}/seihou-cli/src"
    DOC_REF="docs/dev/architecture/overview.md, section \"CLI Module Placement Convention\""

    # Modules that legitimately stay in the executable despite not matching
    # the import-based heuristic. Add to this list with an inline comment
    # justifying the exemption.
    EXEMPT_MODULES=(
      "Paths_seihou_cli" # generated by cabal; no source file on disk
    )

    # Step 1: extract the executable's other-modules list. The cabal file's
    # executable stanza begins with "^executable seihou" and runs to the
    # next stanza header or end of file. Within it, other-modules entries
    # are indented module names; comment lines start with "--".
    extract_executable_other_modules() {
      awk '
        /^executable seihou/ { in_exec = 1; next }
        in_exec && /^[a-zA-Z]/ { in_exec = 0 }
        in_exec && /^  other-modules:/ { in_om = 1; next }
        in_exec && in_om && /^  [a-zA-Z]/ { in_om = 0 }
        in_om && /^    [A-Z]/ {
          gsub(/[ \t]+/, "")
          print
        }
      ' "$CABAL_FILE"
    }

    # Step 2: given a module name (e.g. Seihou.CLI.Foo), compute its source
    # file path. Returns empty if no file exists (e.g. for Paths_seihou_cli).
    module_to_path() {
      local mod="$1"
      local rel="${mod//./\/}.hs"
      local path="${SRC_DIR}/${rel}"
      if [[ -f "$path" ]]; then
        echo "$path"
      fi
    }

    # Step 3: determine if a module has a direct executable-only import.
    has_direct_exec_only_import() {
      local path="$1"
      if [[ -z "$path" ]]; then
        return 1
      fi
      grep -E '^import (qualified )?(Options\.Applicative|Data\.FileEmbed|GitHash|Paths_seihou_cli)' "$path" >/dev/null
    }

    # Step 4: list the seihou modules that a file imports.
    seihou_imports() {
      local path="$1"
      grep -E '^import (qualified )?Seihou\.' "$path" \
        | sed -E 's/^import (qualified )?//' \
        | awk '{print $1}'
    }

    # Step 5: compute the closure of executable-only modules.
    # Starts with directly-trapped modules and iteratively adds any
    # seihou module that imports an already-trapped one.
    compute_closure() {
      local -a all_modules=()
      while IFS= read -r mod; do
        all_modules+=("$mod")
      done < <(find "$SRC_DIR" -name '*.hs' -print | sed -e "s|^${SRC_DIR}/||" -e 's|/|.|g' -e 's|\.hs$||')

      local -A trapped
      # Seed with directly-trapped modules.
      for mod in "${all_modules[@]}"; do
        local path
        path=$(module_to_path "$mod")
        if has_direct_exec_only_import "$path"; then
          trapped["$mod"]=1
        fi
      done

      # Fixpoint: repeatedly add modules that import a trapped module.
      local changed=1
      while [[ $changed -eq 1 ]]; do
        changed=0
        for mod in "${all_modules[@]}"; do
          if [[ -n "${trapped[$mod]:-}" ]]; then
            continue
          fi
          local path
          path=$(module_to_path "$mod")
          if [[ -z "$path" ]]; then
            continue
          fi
          while IFS= read -r imp; do
            if [[ -n "${trapped[$imp]:-}" ]]; then
              trapped["$mod"]=1
              changed=1
              break
            fi
          done < <(seihou_imports "$path")
        done
      done

      # Print the closure, one module per line.
      for mod in "${!trapped[@]}"; do
        echo "$mod"
      done | sort
    }

    # Step 6: check that every entry in the executable's other-modules is
    # either in the closure or on the exempt list.
    main() {
      local closure
      closure=$(compute_closure)

      local violations=()
      while IFS= read -r mod; do
        # Exempt?
        local exempt=0
        for ex in "${EXEMPT_MODULES[@]}"; do
          if [[ "$mod" == "$ex" ]]; then
            exempt=1
            break
          fi
        done
        if [[ $exempt -eq 1 ]]; then
          continue
        fi
        # In closure?
        if echo "$closure" | grep -Fxq "$mod"; then
          continue
        fi
        violations+=("$mod")
      done < <(extract_executable_other_modules)

      local total
      total=$(extract_executable_other_modules | wc -l | tr -d ' ')

      if [[ ${#violations[@]} -eq 0 ]]; then
        echo "OK: ${total} modules in executable other-modules, all justified."
        exit 0
      fi

      echo "FAIL: ${#violations[@]} module(s) in executable other-modules"
      echo "      have no recognised trapping dependency."
      echo
      echo "Violations:"
      for v in "${violations[@]}"; do
        echo "  - ${v}"
      done
      echo
      echo "Each module in 'executable seihou' must either:"
      echo "  1. Import one of: Options.Applicative, Data.FileEmbed,"
      echo "     GitHash, Paths_seihou_cli."
      echo "  2. Import a module that is already executable-only"
      echo "     (transitive trap, e.g. via Seihou.CLI.Commands)."
      echo "  3. Appear in the EXEMPT_MODULES list at the top of"
      echo "     ${BASH_SOURCE[0]}."
      echo
      echo "If the module is genuinely a pure helper, move it to"
      echo "library seihou-cli-internal's exposed-modules in"
      echo "seihou-cli/seihou-cli.cabal."
      echo
      echo "Rule: ${DOC_REF}."
      exit 1
    }

    main "$@"

Steps:

1. Create the directory `nix/` if it does not already exist:

       mkdir -p nix

2. Write the script above to `nix/check-cli-module-placement.sh`. Use a
   text editor or `cat << 'EOF' > nix/check-cli-module-placement.sh`.

3. Make the script executable:

       chmod +x nix/check-cli-module-placement.sh

4. Run it manually:

       bash nix/check-cli-module-placement.sh

   Expected output (post-EP-3 tree):

       OK: 26 modules in executable other-modules, all justified.

   The exact count depends on the post-EP-3 layout (the masterplan's
   Integration Point #2 estimates 25-27).

5. If the script reports violations against the clean post-EP-3 tree,
   inspect each one. Two kinds of false-positive are possible:

   - The script's `extract_executable_other_modules` `awk` block does
     not handle the cabal file's specific indentation. Adjust the
     `awk` regex to match.
   - A module imports `Options.Applicative` via a re-export that the
     simple grep misses. Inspect the file's full import block; if
     necessary, extend `has_direct_exec_only_import` to recognise the
     pattern.

   Capture any required adjustment in the Surprises & Discoveries
   section.


### Milestone 2: Wire the script into `nix flake check`

Scope: add a new entry to `flake.nix`'s `checks.<system>` attribute so
`nix flake check` runs the script.

What will exist at the end: `nix flake check` includes a
`cli-module-placement` check that succeeds.

Acceptance: running

    nix flake check

(against the current tree, in a `nix develop` shell or with `nix flake
check` directly) shows the new check among the others and reports
success.

Steps:

1. Open `flake.nix`. Locate the `checks` attribute (around line 49 as of
   2026-04-26):

       checks = {
         formatting = treefmtEval.config.build.check self;
         pre-commit-check = pre-commit-hooks.lib.${system}.run {
           src = ./.;
           hooks = {
             treefmt.package = formatter;
             treefmt.enable = true;
           };
         };
       };

2. Add a new attribute, `cli-module-placement`, that runs the script. In
   Nix flake checks, a check is a derivation; the simplest form uses
   `pkgs.runCommand`:

       checks = {
         formatting = treefmtEval.config.build.check self;
         pre-commit-check = pre-commit-hooks.lib.${system}.run {
           src = ./.;
           hooks = {
             treefmt.package = formatter;
             treefmt.enable = true;
           };
         };
         cli-module-placement = pkgs.runCommand "cli-module-placement-check"
           { src = self; nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.gawk pkgs.findutils ]; }
           ''
             cp -r $src ./repo
             chmod -R u+w ./repo
             cd ./repo
             bash nix/check-cli-module-placement.sh
             touch $out
           '';
       };

   Notes on the snippet:

   - `pkgs.runCommand` produces a trivial derivation that runs a shell
     script and writes to `$out`; the build succeeds if the script exits
     0 and fails otherwise.
   - The `nativeBuildInputs` list pins the tools the script uses
     (`bash`, `gnugrep`, `gawk`, `findutils`) so the check is
     hermetic regardless of the host system's defaults.
   - `cp -r $src ./repo` copies the flake source to a writable build
     directory because `$src` is read-only.

3. Run the check:

       nix flake check

   Expected: all checks succeed, including the new
   `cli-module-placement`. If the check fails, the build output names
   the script's `FAIL:` message.

4. Verify the check is wired by inspecting:

       nix flake show 2>&1 | rg "cli-module-placement"

   Expected: one match per system the flake supports.


### Milestone 3: Wire the script into pre-commit and finalise

Scope: extend the `pre-commit-check.hooks` block so the script also runs
at commit time. Update `CLAUDE.md` with a one-line pointer. Add the
CHANGELOG entry. Commit.

What will exist at the end: a deliberate violation, attempted via `git
commit`, is rejected with the script's `FAIL:` message. The convention
is now mechanically enforced at three places (the script directly,
`nix flake check`, and `git commit`).

Steps:

1. Edit `flake.nix`'s `pre-commit-check.hooks` block to add a custom
   hook entry. The `pre-commit-hooks.nix` flake input supports
   user-defined hooks via a `hooks.<name>` attribute set:

       pre-commit-check = pre-commit-hooks.lib.${system}.run {
         src = ./.;
         hooks = {
           treefmt.package = formatter;
           treefmt.enable = true;
           cli-module-placement = {
             enable = true;
             name = "cli-module-placement";
             entry = "${pkgs.bash}/bin/bash ${./nix/check-cli-module-placement.sh}";
             language = "system";
             pass_filenames = false;
             # The script reads the cabal file directly, so it does not
             # need the changed file list.
           };
         };
       };

   The `pass_filenames = false` is important: the script does not
   accept filenames; it always inspects the cabal file.

2. Re-enter the dev shell so the updated hook is installed:

       nix develop

   The `shellHook` line in `flake.nix` (around line 71) re-runs the
   `pre-commit-check.shellHook`, which installs the updated hook into
   `.git/hooks/pre-commit`.

3. Verify the hook is installed:

       cat .git/hooks/pre-commit | rg "cli-module-placement"

   Expected: one or more matches; the hook script references the new
   hook by name.

4. Run the deliberate-violation test from the Purpose section. In a
   scratch worktree (or accept that you will revert the change in the
   same shell):

       cp seihou-cli/seihou-cli.cabal seihou-cli/seihou-cli.cabal.bak
       sed -i.tmp '/^    Paths_seihou_cli$/a\
           Seihou.CLI.RemoteVersion' seihou-cli/seihou-cli.cabal
       rm -f seihou-cli/seihou-cli.cabal.tmp

       bash nix/check-cli-module-placement.sh

   Expected: the script fails with output naming `Seihou.CLI.RemoteVersion`
   among the violations and pointing at the convention doc.

   Also verify the pre-commit hook fires:

       git add seihou-cli/seihou-cli.cabal
       git commit -m "test: deliberate violation" 2>&1 || true

   Expected: the commit is rejected; the output includes the script's
   FAIL message.

   Restore the cabal file:

       mv seihou-cli/seihou-cli.cabal.bak seihou-cli/seihou-cli.cabal
       git add seihou-cli/seihou-cli.cabal

5. Update `CLAUDE.md` at the repo root: add one line under the "CLI
   Module Placement (library-first)" section pointing at the check:

       Enforced by `nix/check-cli-module-placement.sh` (run via
       `nix flake check` and the pre-commit hook).

6. Add a CHANGELOG entry to `docs/user/CHANGELOG.md`:

       - 2026-04-26: Added `nix/check-cli-module-placement.sh`, an
         enforcement script for the CLI library-first module-placement
         convention. The script runs as part of `nix flake check` and
         as a pre-commit hook; it fails when a module is added to
         `executable seihou`'s `other-modules` without a recognised
         trapping dependency.

7. Commit:

       git add nix/check-cli-module-placement.sh flake.nix CLAUDE.md \
               docs/user/CHANGELOG.md
       git commit -m "$(cat <<'EOF'
       feat(ci): enforce CLI library-first module placement

       Adds nix/check-cli-module-placement.sh, a Bash script that walks
       the executable target's other-modules and fails if an entry does
       not import one of Options.Applicative, Data.FileEmbed, GitHash,
       Paths_seihou_cli, or another already-trapped seihou module.

       Wires the script into flake.nix's checks attribute (so `nix
       flake check` runs it) and into the pre-commit-check.hooks block
       (so `git commit` rejects violations). Updates CLAUDE.md with a
       pointer to the check.

       Convention is documented at docs/dev/architecture/overview.md,
       section "CLI Module Placement Convention".

       MasterPlan: docs/masterplans/2-cli-library-first-convention.md
       ExecPlan: docs/plans/21-enforce-cli-library-first-convention.md
       Intention: intention_01kq63sz0ced98e23qvad7zpnp
       EOF
       )"


## Concrete Steps

The Plan of Work above contains the concrete steps interleaved with
narrative. Follow Milestone 1, then Milestone 2, then Milestone 3 in order.

The deliberate-violation test in Milestone 3 Step 4 is the single most
important manual check; it proves the enforcement actually fires. Do not
skip it.


## Validation and Acceptance

Acceptance is observable through three complementary checks.

Direct script acceptance:

    bash nix/check-cli-module-placement.sh

Returns "OK: N modules ..., all justified." and exits 0.

`nix flake check` acceptance:

    nix flake check

All checks (including the new `cli-module-placement`) succeed.

Pre-commit acceptance: the deliberate-violation test rejects the commit
with the script's `FAIL:` message; restoring the cabal file and
re-committing succeeds.

Behavioural confirmation: a hypothetical future contributor who wants to
add a new pure helper `Seihou.CLI.NewThing.hs` and adds it to
`executable seihou`'s `other-modules` (the wrong place) will:

1. See the violation when running `nix flake check`.
2. See the violation when running `git commit`.
3. Read the FAIL message, which names the module and points at
   `docs/dev/architecture/overview.md`.
4. Read the convention, learn the rule, and move the module to
   `library seihou-cli-internal`'s `exposed-modules`.

The end-to-end workflow is mechanical, fast (the script runs in well
under a second on a normal cabal file), and self-documenting.


## Idempotence and Recovery

The script is idempotent: running it repeatedly produces the same
output. It does not modify any file.

The `flake.nix` edits are local to two attribute blocks; if either edit
goes wrong, `git diff flake.nix` shows the change and `git checkout --
flake.nix` restores it.

The pre-commit hook is regenerated by `nix develop`; no manual cleanup
is needed if the hook configuration changes. If the hook fails on a
legitimate commit (false positive), the commit can be made with
`SKIP=cli-module-placement git commit ...` while the false positive is
investigated. Document any false positive in Surprises & Discoveries
and tighten the script accordingly.

If `nix` is unavailable on the contributor's machine, the script is
still runnable directly via `bash nix/check-cli-module-placement.sh`;
the script's only runtime dependencies are `bash`, `awk`, `grep`,
`find`, and `sort`, all available on any Unix-like system.


## Interfaces and Dependencies

Files created:

- `nix/check-cli-module-placement.sh` (~120 lines, executable).

Files edited:

- `flake.nix`: add `cli-module-placement` to the `checks` attribute;
  add a `cli-module-placement` hook to `pre-commit-check.hooks`.
- `CLAUDE.md`: add a one-line pointer to the check under the existing
  "CLI Module Placement (library-first)" section.
- `docs/user/CHANGELOG.md`: prepend one entry.

No source files edited. No new Haskell-package dependencies.

External flake dependencies used:

- `pkgs.runCommand` (already available via the existing `pkgs`
  binding).
- `pkgs.bash`, `pkgs.gnugrep`, `pkgs.gawk`, `pkgs.findutils` (standard
  nixpkgs packages).
- `pre-commit-hooks.lib.${system}.run` (already used by the existing
  `pre-commit-check`).

The script's interface (consumed by sibling artefacts):

- Inputs: reads `seihou-cli/seihou-cli.cabal` and every file under
  `seihou-cli/src/Seihou/`.
- Outputs: prints a one-line summary to stdout on success; prints a
  multi-line FAIL message on violation; exit code 0 on success, 1 on
  violation.
- Configuration: the `EXEMPT_MODULES` array at the top of the script
  is the single point of extension for legitimate exemptions.

The convention this plan enforces lives at:

- Canonical: `docs/dev/architecture/overview.md`, section "CLI Module
  Placement Convention" (created by sibling plan
  `docs/plans/18-document-cli-library-first-convention.md`).
- Quick reference: `CLAUDE.md` at the repo root.
- Encoded in cabal: `seihou-cli/seihou-cli.cabal` (annotated by sibling
  plan `docs/plans/19-restructure-cli-cabal-library-first.md`).
- Resolved legacy violations: sibling plan
  `docs/plans/20-extract-trapped-cli-helpers.md`.
