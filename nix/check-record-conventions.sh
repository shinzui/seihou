#!/usr/bin/env bash
# nix/check-record-conventions.sh
#
# Enforces the record conventions. See docs/dev/architecture/overview.md,
# section "Record Conventions", for the rule. Six things are checked:
#
#   1. No .cabal stanza enables OverloadedRecordDot.
#   2. Every .cabal default-extensions block lists DeriveAnyClass,
#      DuplicateRecordFields, NoFieldSelectors, OverloadedLabels and
#      OverloadedStrings.
#   3. Every `data` record field carries a ! strictness annotation.
#      (`newtype` fields are exempt: GHC rejects a strictness annotation
#      on a newtype constructor outright.)
#   4. No record update `{ field = ... }` expression — a brace whose head
#      is a lowercase identifier or a closing paren. Record *construction*
#      (uppercase head) and record *patterns* are both fine.
#   5. No bare `deriving (` clause without a strategy keyword.
#   6. seihou-core/src/Seihou/Prelude.hs does not import Data.Generics.Labels.
#
# Deliberately NOT checked: missing Generic derives, which the compiler
# already catches the moment a #label fails to resolve, and field-name
# prefixes, which no text match can tell apart from a descriptive name.

set -euo pipefail

# Locate the repo root. Three callers exercise this path:
#   1. Direct invocation from the repo root (most common).
#   2. `pkgs.runCommand` in flake.module.nix, which cds into the copied source.
#   3. The pre-commit hook, where the script lives in /nix/store/... but
#      pre-commit sets the working directory to the repo root.
if [[ -n "${SEIHOU_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$SEIHOU_REPO_ROOT"
elif [[ -f "$PWD/seihou-core/seihou-core.cabal" ]]; then
  REPO_ROOT="$PWD"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

DOC_REF='docs/dev/architecture/overview.md, section "Record Conventions"'
PRELUDE="seihou-core/src/Seihou/Prelude.hs"

CABAL_FILES=(
  "seihou-core/seihou-core.cabal"
  "seihou-cli/seihou-cli.cabal"
  "seihou-okf-extension/seihou-okf-extension.cabal"
)

REQUIRED_EXTENSIONS=(
  DeriveAnyClass
  DuplicateRecordFields
  NoFieldSelectors
  OverloadedLabels
  OverloadedStrings
)

# Record updates on types seihou does not own. These third-party types have
# no Generic instance, so there is no #label to set and record update syntax
# is the only option. Each site carries an inline comment saying so; add to
# this list with the same justification.
EXEMPT_UPDATE_FIELDS=(
  cwd std_in std_out std_err env  # System.Process.CreateProcess
  executable readable writable searchable  # System.Directory.Permissions
  systemPrompt modelId effort workingDir extraDirs  # baikai InteractiveLaunchRequest
)

failures=0

fail() {
  failures=$((failures + 1))
  echo "$@"
}

hs_files() {
  find "${REPO_ROOT}/seihou-core" "${REPO_ROOT}/seihou-cli" "${REPO_ROOT}/seihou-okf-extension" \
    -name '*.hs' -not -path '*/dist-newstyle/*' -print \
    | sort
}

rel() {
  echo "${1#"${REPO_ROOT}"/}"
}

# Shared awk prelude: strip(l) blanks out string literals and line comments so
# that the checks below match code and not prose. Block comments are tracked
# with a state flag by the callers that need it. Every check works on the
# stripped text but reports the original line.
read -r -d '' AWK_STRIP <<'AWK' || true
function strip(l,   out) {
  out = l
  gsub(/"(\\.|[^"\\])*"/, "\"\"", out)
  sub(/--.*$/, "", out)
  return out
}
function blockstate(l,   n) {
  # returns the stripped line, maintaining INBLOCK across calls
  if (INBLOCK) {
    if (index(l, "-}")) { INBLOCK = 0; return substr(l, index(l, "-}") + 2) }
    return ""
  }
  n = index(l, "{-")
  if (n > 0 && substr(l, n, 3) != "{-#") {
    if (index(l, "-}") > n) return substr(l, 1, n - 1) substr(l, index(l, "-}") + 2)
    INBLOCK = 1
    return substr(l, 1, n - 1)
  }
  return l
}
AWK

# ---------------------------------------------------------------- 1 and 2
#
# Walk each default-extensions block. A block starts at "  default-extensions:"
# and runs to the first line that is not a four-space-indented extension name.
check_cabal_extensions() {
  local cabal blocks
  for cabal in "${CABAL_FILES[@]}"; do
    local path="${REPO_ROOT}/${cabal}"
    if [[ ! -f "$path" ]]; then
      echo "ERROR: cabal file not found at ${cabal}" >&2
      exit 2
    fi
    blocks=$(awk '
      /^  default-extensions:[[:space:]]*$/ { n++; start = FNR; list = ""; inblk = 1; next }
      inblk && /^    [A-Za-z]/ { gsub(/[ \t]/, ""); list = list " " $0; next }
      inblk { print start "|" list; inblk = 0 }
      END { if (inblk) print start "|" list }
    ' "$path")

    if [[ -z "$blocks" ]]; then
      echo "ERROR: parsed zero default-extensions blocks from ${cabal}." >&2
      echo "       Check the awk parser in this script against the file's format." >&2
      exit 2
    fi

    while IFS='|' read -r line list; do
      if [[ " $list " == *" OverloadedRecordDot "* ]]; then
        fail "error: OverloadedRecordDot is enabled"
        fail "  ${cabal}:${line}: default-extensions"
        fail "Field access goes through generic-lens labels (record ^. #field),"
        fail "not through GHC's record dot. See ${DOC_REF}."
        fail ""
      fi
      local ext
      for ext in "${REQUIRED_EXTENSIONS[@]}"; do
        if [[ " $list " != *" $ext "* ]]; then
          fail "error: required extension ${ext} is missing"
          fail "  ${cabal}:${line}: default-extensions"
          fail "Every stanza must enable: ${REQUIRED_EXTENSIONS[*]}."
          fail "See ${DOC_REF}."
          fail ""
        fi
      done
    done <<<"$blocks"
  done
}

# ---------------------------------------------------------------- 3
#
# Every field of a `data` record needs a ! annotation. The awk below tracks
# whether it is inside a `data` declaration (newtype declarations are skipped
# entirely) and reports any "name ::" whose type does not begin with !.
check_strict_fields() {
  local out
  out=$(hs_files | while IFS= read -r f; do
    awk -v file="$(rel "$f")" "$AWK_STRIP"'
      # A GADT-syntax declaration ("data Foo m a where") has constructor
      # signatures, not record fields, so it is skipped entirely.
      /^data[[:space:]].*[[:space:]]where[[:space:]]*$/ { indata = 0; next }
      /^data[[:space:]]/    { indata = 1; next }
      /^newtype[[:space:]]/ { indata = 0; next }
      /^[^[:space:]]/       { indata = 0 }
      indata {
        s = strip(blockstate($0))
        # A field occurrence sits after "{", "," or the start of the line.
        while (match(s, /(^|[{,])[[:space:]]*[a-z_][A-Za-z0-9_'"'"']*([[:space:]]*,[[:space:]]*[a-z_][A-Za-z0-9_'"'"']*)*[[:space:]]*::[[:space:]]*/)) {
          rest = substr(s, RSTART + RLENGTH)
          if (substr(rest, 1, 1) != "!") {
            print file ":" FNR ": " $0
            break
          }
          s = rest
        }
      }
    ' "$f"
  done)
  if [[ -n "$out" ]]; then
    fail "error: record field is not strict"
    while IFS= read -r l; do fail "  $l"; done <<<"$out"
    fail "Every field of a data record must carry a ! annotation."
    fail "(newtype fields are exempt; GHC rejects the annotation there.)"
    fail "See ${DOC_REF}."
    fail ""
  fi
}

# ---------------------------------------------------------------- 4
#
# A record UPDATE is a `{ field =` brace whose head is a lowercase identifier
# or a closing paren. Construction (uppercase head) and patterns are allowed.
check_record_updates() {
  local out exempt_re
  exempt_re="$(printf '%s|' "${EXEMPT_UPDATE_FIELDS[@]}")"
  exempt_re="${exempt_re%|}"
  out=$(hs_files | while IFS= read -r f; do
    awk -v file="$(rel "$f")" -v exempt="$exempt_re" "$AWK_STRIP"'
      {
        s = strip(blockstate($0))
        if (match(s, /(^|[^A-Za-z0-9_.'"'"'])([a-z_][A-Za-z0-9_'"'"']*|\))[[:space:]]*\{[[:space:]]*[a-z_][A-Za-z0-9_'"'"']*[[:space:]]*=/)) {
          hit = substr(s, RSTART, RLENGTH)
          if (match(hit, "\\{[[:space:]]*(" exempt ")[[:space:]]*=")) next
          print file ":" FNR ": " $0
        }
      }
    ' "$f"
  done)
  if [[ -n "$out" ]]; then
    fail "error: record update syntax"
    while IFS= read -r l; do fail "  $l"; done <<<"$out"
    fail "Update records with lens setters: rec & #field .~ value"
    fail "(?~ for a Maybe field, %~ for a function, at/ix for a Map)."
    fail "Record construction and record patterns are fine; only update"
    fail "syntax is not. If the type is third-party and has no Generic"
    fail "instance, add its field names to EXEMPT_UPDATE_FIELDS in"
    fail "${BASH_SOURCE[0]} with a comment naming the type."
    fail "See ${DOC_REF}."
    fail ""
  fi
}

# ---------------------------------------------------------------- 5
check_deriving_strategies() {
  local out
  out=$(hs_files | while IFS= read -r f; do
    awk -v file="$(rel "$f")" "$AWK_STRIP"'
      {
        s = strip(blockstate($0))
        if (s ~ /(^|[^A-Za-z])deriving[[:space:]]*\(/ &&
            s !~ /deriving[[:space:]]+(stock|anyclass|newtype|via)[[:space:]]/) {
          print file ":" FNR ": " $0
        }
      }
    ' "$f"
  done)
  if [[ -n "$out" ]]; then
    fail "error: deriving clause without an explicit strategy"
    while IFS= read -r l; do fail "  $l"; done <<<"$out"
    fail "Write deriving stock (...), deriving anyclass (...) or"
    fail "deriving newtype (...). A bare deriving (...) is ambiguous"
    fail "once DeriveAnyClass is enabled. See ${DOC_REF}."
    fail ""
  fi
}

# ---------------------------------------------------------------- 6
check_prelude_orphan() {
  local path="${REPO_ROOT}/${PRELUDE}"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: prelude not found at ${PRELUDE}" >&2
    exit 2
  fi
  if grep -nE '^import .*Data\.Generics\.Labels' "$path" >/dev/null; then
    fail "error: the shared prelude imports Data.Generics.Labels"
    fail "  $(grep -nE '^import .*Data\.Generics\.Labels' "$path" | sed "s|^|${PRELUDE}:|")"
    fail "generic-lens's IsLabel instance is an orphan, and orphan instances"
    fail "propagate transitively, so importing it here forces the generic-lens"
    fail "reading of #label onto every module that uses the prelude. Each"
    fail "module that needs #label imports it itself. See ${DOC_REF}."
    fail ""
  fi
}

main() {
  check_cabal_extensions
  check_strict_fields
  check_record_updates
  check_deriving_strategies
  check_prelude_orphan

  if [[ $failures -eq 0 ]]; then
    echo "OK: record conventions hold."
    exit 0
  fi
  exit 1
}

main "$@"
