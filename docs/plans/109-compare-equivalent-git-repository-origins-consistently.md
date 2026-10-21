---
id: 109
slug: compare-equivalent-git-repository-origins-consistently
title: "Compare equivalent Git repository origins consistently"
kind: exec-plan
created_at: 2026-10-21T12:58:00Z
intention: "intention_01m5f8kpfceex8yk92nxedesvk"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-21T12:58:00Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T13:53:02Z
      mode: "update"
      note: "Specify parse-before-normalize boundaries, classify raw update comparisons, and tighten validation evidence."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T13:53:22Z
      verdict: "approved"
      note: "Approved revised plan after checking code consumers, ADRs, upstream URL documentation, fixtures, and test selectors; implementation tests remain pending."
---

# Compare equivalent Git repository origins consistently

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

An existing project records `git@github.com:shinzui/seihou-modules.git`, while the
installed `git-init` module records `https://github.com/shinzui/seihou-modules.git`.
`seihou status` reports an origin mismatch even though these are two access methods
for the same repository. After this change, ordinary status, generation guards,
installation checks, repair evidence, and migration receipt checks agree about
repository identity. Different repositories must still be distinguished.

The acceptance workflow starts with that existing manifest and installed module,
without changing either URL. After obtaining the fixed executable, the developer runs:

```bash
seihou status
```

The false warning disappears. Repeated status calls and fresh worktrees need no
adoption command, flags, manifest edits, reinstall, or cache preparation. Status
remains read-only and offline by default. A missing installation retains its existing
diagnostic; equivalence does not fabricate provenance. Fix the shared comparison
rather than suppressing the warning in the renderer.


## Progress

- [ ] M1: The reported status workflow passes through a shared, conservative repository comparator, with the unchanged manifest and a genuine mismatch as a negative control.
- [ ] M2: Install checks, repair evidence, guards, and migration receipts use the same rules; edge cases and equivalence laws pass focused regressions.
- [ ] M3: Documentation and ADRs describe the contract, required checks pass, and the fixed executable is verified through the user's ordinary command. Record release and installation evidence separately from source-build evidence.


## Surprises & Discoveries

Validation on 2026-10-21 confirmed the separate guard/install and repair comparison
paths. It also found raw origin equality in
`seihou-cli/src/Seihou/CLI/Update/Source.hs` and
`seihou-cli/src/Seihou/CLI/Update/Types.hs`, which a search for the existing helper
names alone misses. Their distinct purposes are classified below.

The existing cosmetic helper operates on the whole string. Applying it before
parsing can erase a path component (`owner/repo/.git` becomes `owner/repo`) or
change a query ending in `.git`. The new comparator must parse first and normalize
only the appropriate components; retaining the helper for old callers does not make
it suitable as the parser's preprocessing step.


## Decision Log

- Decision: Add one pure repository-equivalence API in core and route identity decisions through it. Keep stored and clone URLs intact.
  Rationale: URL identity and connection instructions serve different purposes. Rewriting an SSH URL to HTTPS can change authentication and break access.
  Date: 2026-10-21

- Decision: Recognize documented public GitHub transport equivalents explicitly; compare other endpoints conservatively using their full connection and path information.
  Rationale: Arbitrary SSH and HTTPS servers can expose different namespaces, and arbitrary ports or SSH users can select different repositories. Robustness requires negative cases as well as recognizing the reported pair. Additional hosting providers require documented mapping rules and tests, not blanket scheme removal.
  Date: 2026-10-21

- Decision: Existing supported manifests and migration receipts receive the comparison fix on read, without a serialized format change or automatic rewrite.
  Rationale: This corrects recognition of existing repository identities; it adds no stored fact or new manifest representation. Document this boundary against ADR 0014. If implementation needs a stored identity field or changes receipt meaning beyond URL equivalence, follow that ADR's adjacent-version upgrade requirements rather than silently expanding this decision.
  Date: 2026-10-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou records where applied artifacts came from in `.seihou/manifest.json`.
`RemoteOrigin` identifies a repository URL and an artifact name. `ProjectOrigin`
identifies a project-relative path, while `LocalOrigin` carries a name without proven
provenance. This plan changes comparison of remote URLs, not those trust levels.

`seihou-core/src/Seihou/Core/ArtifactIdentity.hs` owns `sameArtifactIdentity` and
`normalizeOriginUrl`. The latter only trims whitespace, trailing slashes, and a
terminal `.git`. `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` uses that normalization
in `originRelation`; status receives the resulting verdict through `summarizeCheck`.
`seihou-cli/src/Seihou/CLI/InstallShared.hs` uses the same string equality in
`classifyInstallCollision` before replacing an installation.

`seihou-cli/src/Seihou/CLI/ManifestRepairOrigins.hs` separately defines
`sameRepository` and `repositoryKey`. Those strip schemes, users, and numeric ports
for repair evidence. They recognize the reported pair, but erase distinctions that
matter on general Git servers. Plan 98,
`docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md`,
explicitly limited that comparison to repair evidence and preferred the installed
URL spelling to satisfy the stricter guard. Do not copy this helper unchanged.

`seihou-core/src/Seihou/Manifest/Types.hs` uses `sameArtifactIdentity` for receipt
lookup and upsert. `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` uses it for
pending migration filtering and owner matching. These must continue agreeing, so
switching transports neither reruns completed work nor creates another receipt for
one edge. `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` reaches the guard
when certifying shared-write evidence and must benefit as well.

`seihou-cli/src/Seihou/CLI/RecordedRelease.hs` hashes `normalizeOriginUrl` for a
temporary clone directory, then clones the original URL. That is a connection cache,
not an identity verdict. Keep its current transport-specific key: failure or credentials
for one connection method must not be hidden by sharing another's cached connection.
Repair's grouping of machine-local paths likewise remains lexical.

`seihou-cli/src/Seihou/CLI/Update/Source.hs` keys clones by the recorded connection
URL. Its `verifyRemoteRequirements` checks that a candidate was staged from that
exact requested URL; candidates inherit it directly from the clone operation. Keep
that construction check and clone keys exact. `insertCandidate` rejects duplicate
artifact names across staged catalogs before this check. Consequently, combining
multiple recorded URL spellings of one catalog in a single update can still produce
an ambiguity; this plan does not redesign candidate staging or promise to fix that
separate workflow. `seihou-cli/src/Seihou/CLI/Update/Types.hs` compares stored origins
structurally in `isUpdateNoOp` to detect a manifest change; retain that equality
so a changed URL spelling is not hidden from the apply decision.

Relevant local decisions are [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md)
(identity includes artifact name and comparison is shared),
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md)
(genuine substitutions and older versions still block generation),
[ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md)
(different-source installs refuse before deleting anything), and
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
(new serialized semantics require versioned upgrades). The local ADR corpus uses
ordinary Markdown; `mori.dhall` does not declare it as a profiled OKF bundle.

The source repository supplying the reported module is `mori://shinzui/seihou-modules`;
its module reference is `mori://shinzui/seihou-modules/templates/git-init`.
No producer change is required. GitHub documents HTTPS and SSH as repository access
methods in [About remote repositories](https://docs.github.com/en/get-started/git-basics/about-remote-repositories)
and explicitly documents `ssh.github.com:443` in
[Using SSH over the HTTPS port](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port).
[Git's URL syntax documentation](https://git-scm.com/docs/git-clone#_git_urls)
distinguishes scp-style `user@host:path` from scheme URLs and local paths. In
particular, scp-style paths on general SSH servers can be relative to a user's home;
they cannot universally be equated with absolute SSH URL paths.


## Plan of Work

### M1: Shared comparison and the ordinary status workflow


Before broadening coverage, identify an actual affected consumer from the user's
workspace using Mori and read-only inspection of its manifest and installation.
Record its executable path/version and the existing warning. Run the source-built
executable against the same unchanged state after the fix. Do not run repair-origins,
change remotes, or reinstall modules to make acceptance pass. If no affected checkout
is identifiable, record that limitation and use an isolated binary regression with
the exact reported URLs; leave real-consumer delivery evidence open.

Add `sameRepositoryOrigin :: Text -> Text -> Bool` to
`seihou-core/src/Seihou/Core/ArtifactIdentity.hs`. Internally compare tagged keys
for recognized hosted repositories, other parsed network endpoints, and opaque input.
Tagged keys prevent an unparseable string from accidentally matching a parsed URL.
Use a total parser: every input produces a deterministic key without exceptions.
Keep `normalizeOriginUrl` as the existing cosmetic helper; do not turn its result
into a clone URL or broaden every cache and path-grouping call implicitly.

After trimming surrounding whitespace, parse the original text before applying
cosmetic normalization. Recognize scheme URLs only for `https`, `http`, `ssh`, and
`git`; unsupported schemes fall back to opaque input. Separate authority, path,
query, and fragment, retaining the distinction between an absent delimiter and an
empty query or fragment. Validate an explicit port as nonempty ASCII decimal digits
with a value from 1 through 65535 before normalizing default ports. Do not decode
escapes, resolve dot segments, collapse internal slashes, or reinterpret a rejected
scheme URL as scp syntax. In particular, recognize local and Windows paths before
considering scp syntax.

For public GitHub, accept HTTPS on `github.com` with absent port or port 443,
SSH on `github.com` with user `git` and absent port or port 22, scp-style
`git@github.com:OWNER/REPO`, and SSH with user `git` on `ssh.github.com:443`.
These map to one GitHub repository key with owner and repository components.
Normalize scheme and DNS hostname case, surrounding whitespace, optional terminal
`.git`, and trailing slashes. HTTPS user information changes authentication rather
than GitHub repository identity; ignore it only after successfully parsing and
validating the real authority. SSH users other than `git`, missing SSH users, and
other ports do not enter the GitHub equivalence class.

Recognized GitHub paths must contain exactly two nonempty ordinary ASCII components
using letters, digits, hyphens, underscores, or dots, excluding `.` and `..`.
Preserve component case as a conservative policy. Reject queries, fragments,
percent escapes, embedded whitespace, extra path components, and doubled internal
slashes from this recognized class; do not silently clean them into a trusted match.
Do not infer equivalence for redirects, renamed repositories, HTTP or git-protocol
URLs, lookalike domains, DNS aliases, local Git configuration, or user SSH aliases.
Only the documented SSH endpoint above is a host alias.

For the GitHub key, remove the one structural leading slash from a scheme URL's
path, then trailing slashes, require exactly two components, and strip at most one
terminal `.git` from the repository component. Validate both resulting components,
including nonemptiness. Scp form must have `OWNER/REPO` directly after the colon;
an absolute or tilde-prefixed scp path is outside this hosted mapping. Thus
`https://github.com/owner/repo/.git`, `https://github.com/owner/.git`, and
`https://github.com//owner/repo` cannot become recognized GitHub identities through
cleanup. Reject a query or fragment delimiter even when its value is empty.

For other well-formed network URLs, retain scheme, user information, non-default
port, and complete path; lowercase scheme and DNS hostname and normalize only that
scheme's default port (`https:443`, `http:80`, `ssh:22`, `git:9418`). Preserve path
case, escapes, query, and fragment information. Retain existing `.git`/trailing-slash
cosmetic compatibility on the path component alone; never strip a suffix from query
or fragment text. Never discard arbitrary numeric ports or globally remove users.
Represent generic scp forms separately, retaining the user (including its absence),
lowercased DNS host, and path with its relative/absolute distinction intact; apply
the same path-only cosmetic normalization. Keep generic scp-style paths distinct
from absolute SSH URL paths and from HTTPS, even when host and apparent path match.
Handle bracketed IPv6 authorities
without splitting an address at its first colon; unsupported or malformed syntax
falls back conservatively. Local paths, `file:` inputs, Windows drive paths, and
unrecognized forms use an opaque key with existing cosmetic normalization and never
match a parsed remote. Do not resolve symlinks or consult the network or filesystem.

Use the comparator in `sameArtifactIdentity` while retaining artifact-name equality,
and in `ManifestGuard.originRelation` while retaining its match/different/unverifiable
outcomes and version checks. Add a binary status regression to
`seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs`, using
`seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs` for isolated installation state.
Arrange the differing URL spellings as the fixture's starting state, then exercise
ordinary `status`. Assert no mismatch and byte-identical project manifest and
installed metadata. Changing the owner or repository must restore the mismatch.
This milestone is accepted when that public-command proof and the focused comparator
tests pass, including the actual consumer when available.

### M2: Consistent decisions and adversarial regression coverage


Switch `classifyInstallCollision` to the core comparator. Replace repair's private
parser with the same API; retain `sameRepository` as a delegating wrapper if useful
to avoid unnecessary interface churn. Repair may still choose the installed spelling
for its output, but no longer relies on it to placate the guard. Its numeric-port and
user stripping behavior must become conservative outside documented mappings.

Audit identity comparisons with the search in Concrete Steps. Classify lexical
serialization, cache keys, and repair path grouping explicitly instead of replacing
every equality, including the update construction and change-detection checks
described in Context and Orientation. Verify shared-write certification reaches the
updated comparator.
Exercise receipt lookup, upsert, and pending-edge filtering with SSH-recorded receipts
and an HTTPS-installed blueprint, and in reverse. Existing completed work stays done;
an equivalent URL does not append a second receipt. Unrelated origins and artifacts
remain distinct. Do not add a background receipt rewrite or cleanup operation.

Extend `seihou-core/test/Seihou/Core/ArtifactIdentitySpec.hs` with table-driven
positive and negative cases for the policy above. Cover both comparison directions,
reflexivity, symmetry, and transitivity over representative equivalence classes.
Test hostile authorities such as `github.com.evil.example` and
`https://github.com@evil.example/owner/repo.git`, invalid/empty/out-of-range ports,
IPv6, empty host or path, repeated separators, unknown schemes, local paths, and
nonstandard SSH users. Verify different generic SSH users and ports remain different.
Ensure malformed input cannot gain equivalence to a recognized GitHub repository.
Include cleanup traps such as a third `.git` path component, an empty repository
after suffix removal, empty query/fragment delimiters, and
`https://example.com/repo?ref=topic.git` versus
`https://example.com/repo?ref=topic` (different). Include generic relative and absolute
scp paths and unknown schemes as negative controls.
Preserve `.git`/slash compatibility and unchanged project/local-origin behavior.

Add behavior regressions in `seihou-cli/test/Seihou/CLI/ManifestGuardSpec.hs`,
`seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs`,
`seihou-cli/test/Seihou/CLI/ManifestRepairOriginsSpec.hs`,
`seihou-core/test/Seihou/Manifest/TypesSpec.hs`, and
`seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs` as appropriate. An equivalent
install is `SameSource` without `--force`; a genuinely different source still refuses
before changing its marker files. Matching origins with an older version still refuse
generation. For status with empty install state, retain the existing absent-producer
summary instead of claiming a verified match. M2 is accepted when all affected
subsystems pass these regressions with a single repository-comparison definition.

### M3: Document and verify delivery


Amend ADR 0002 with the supported equivalence rules and the separation between
identity and connection URLs. Amend ADR 0006 if its normalization explanation needs
updating. Explain why this comparison correction adds no serialized schema or adoption
step under ADR 0014. Update `docs/cli/status.md`, the provenance paragraph in
`docs/cli/install.md`, and both `CHANGELOG.md` and `docs/user/CHANGELOG.md`. Locate
relevant embedded help through `seihou-cli/help/` before editing; there is currently
no standalone `seihou-cli/help/status.md`. Documentation must describe the conservative
boundary for other servers and avoid recommending repair commands for equivalent URLs.

Run the full package tests and project checks, then repeat the real-consumer command
against unchanged project state. Record the source executable path, version, revision,
and observed output. Inspect the current installed executable separately. Keep delivery
open until an authorized release/installation supplies the fix to the executable the
user ordinarily runs; follow the repository's release skill when a release is authorized.
The present request authorizes validating and updating this plan, not implementation,
publishing, or installation.
At handoff state exactly which of source, release, and installed verification passed.


## Concrete Steps

From the repository root, inspect the current identity consumers and build the actual
executable used for binary tests:

```bash
rg -n 'normalizeOriginUrl|sameArtifactIdentity|sameRepository|repositoryKey' seihou-core seihou-cli
rg -n '(sourceUrl|originUrl|targetOrigin|#origin)' seihou-core/src seihou-cli/src
command -v seihou
seihou --version
cabal build all
cabal list-bin exe:seihou
cabal test seihou-core --test-options='-p "ArtifactIdentity"'
cabal test seihou-cli --test-options='-p "shared manifest across developers"'
```

Use the absolute executable path printed by `cabal list-bin` when checking an affected
consumer; changing directory before invoking `cabal run` would select that consumer's
package context. First discover its path with Mori rather than guessing. In that
consumer directory, run the existing installed `seihou status`, then the absolute
source executable with `status`, without editing state between them. Record both
outputs and confirm that status changed no files. The expected difference is removal
of the reported `git-init` origin mismatch; unrelated warnings may legitimately remain.

Focused integration checks and final gates, from this repository root:

```bash
cabal test seihou-cli --test-options='-p "ManifestGuard"'
cabal test seihou-cli --test-options='-p "InstallCollision"'
cabal test seihou-cli --test-options='-p "ManifestRepairOrigins"'
cabal test seihou-core --test-options='-p "Seihou.Manifest.Types"'
cabal test seihou-cli --test-options='-p "BlueprintMigration"'
cabal test all
nix fmt -- --fail-on-change
nix flake check
git diff --check
```

Each focused command must run a nonzero number of tests and report success; a
successful invocation selecting zero tests is not evidence. The binary regression
uses the Cabal-built executable located by
`seihou-cli/test/Seihou/CLI/SeihouBinary.hs`, never an installed fallback. The fixture
currently seeds a generic `demo` source; explicitly arrange the reported GitHub
URLs before the status assertion, without changing its existing callers' defaults.

Record meaningful-boundary commits on the current branch with Conventional Commit
messages and these trailers:

```text
ExecPlan: docs/plans/109-compare-equivalent-git-repository-origins-consistently.md
Intention: intention_01m5f8kpfceex8yk92nxedesvk
```


## Validation and Acceptance

The exact reported SSH/HTTPS pair, the explicit `ssh://git@github.com:22/` form,
and the documented `ssh://git@ssh.github.com:443/` endpoint compare equal for the
same owner and repository. Different owners, repository names, artifact names,
nonstandard ports, unknown aliases, and unrelated hosts remain distinguishable.
The generic-server cases preserve users and path semantics. The focused tests and
full checks above must pass.

Through the compiled binary, the unchanged pre-fix project loses its false status
warning in one ordinary command. Reverse the manifest/installation transport spelling
and obtain the same result. Status never modifies the manifest, install metadata,
or generated files, and requires no live GitHub access. Repeat with an empty installed
cache to verify existing missing-producer behavior. A genuine mismatch still reports
its existing actionable diagnostic; an older same-origin version still triggers the
generation guard. Equivalent install checks need no force flag. Completed migration
receipts survive transport changes without rerunning an edge or adding a new receipt.

No test may silently repair origins, change project remotes, or install an alternative
spelling as a prerequisite for the successful status command. Test fixture creation
can model existing state, but must be described as such. Record real-consumer evidence
before claiming the user's installed workflow fixed. A passing source build alone
completes source acceptance, not release or installation acceptance.


## Idempotence and Recovery

Comparison is pure, offline, and repeatable. Reading existing records does not rewrite
them. Store and clone the original URL, preserving its authentication and transport.
Opaque values continue comparing conservatively rather than causing parser exceptions.
Temporary test repositories and isolated installation homes must not alter the user's
real install cache. Source checks and status are safe to repeat. Installing an older
binary restores the old warning behavior because no migration or repair changed the
underlying manifest. Genuine origin and downgrade overrides retain their current flow.


## Interfaces and Dependencies

The public core interface is additive:

```haskell
-- seihou-core/src/Seihou/Core/ArtifactIdentity.hs
sameRepositoryOrigin :: Text -> Text -> Bool
sameArtifactIdentity :: ArtifactOrigin -> ArtifactOrigin -> Bool
normalizeOriginUrl :: Text -> Text
```

Keep parsed key constructors private and use different constructors for recognized
GitHub identities, generic endpoints, and opaque inputs. Respect the repository's
strict fields, explicit deriving strategies, and generic-lens record conventions.
Core must not depend on the CLI, Git execution, configuration, DNS, or network calls.
No new dependency is planned. If a parser dependency becomes necessary, locate its
source and documentation through Mori and verify its released API before selecting
bounds; do not guess an API or traverse `/nix/store`.

No unfinished plan blocks this work. Plan 98's repair behavior is background context;
the comparison contract here supersedes its overly permissive repair-only parser.
This plan does not change fetching, remote resolution, persistent schema layout, or
the trust represented by `LocalOrigin` and `ProjectOrigin`.


Revision note (2026-10-21): Validated the named comparison consumers, ADRs, fixture,
test group names, Mori template reference, and linked Git/GitHub documentation.
Specified parsing before normalization and added adversarial examples to prevent
cleanup from manufacturing equivalence. Broadened the comparison audit and documented
the exact update checks and remaining mixed-URL catalog limitation. No implementation
milestone is complete. `cabal list-bin exe:seihou` resolved the source build path;
the focused core test invocation triggered dependency rebuilds and was interrupted,
so this plan review records no passing runtime tests.
