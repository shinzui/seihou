---
id: 5
slug: first-public-release-readiness
title: "First public release readiness"
kind: master-plan
created_at: 2026-06-05T14:33:53Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
---

# First public release readiness

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

After this initiative, Seihou is ready for a credible first public open-source and Hackage release. A downstream user can unpack the `seihou-core` and `seihou-cli` source distributions, build the CLI without missing files, inspect licensing and package metadata on Hackage, and follow public documentation that describes implemented behavior rather than internal plans or proposed designs.

The initiative covers the code and documentation risks found during the June 5, 2026 audit: missing embedded assets in the CLI source distribution, unsafe rendered filesystem paths, unsafe migration and removal paths, non-atomic manifest writes, partial recipe expansion, missing Hackage metadata and license, and public documentation cleanup. It does not cut or publish the release itself. The existing `release` skill remains responsible for version bumping, final gates, upload, tags, and GitHub release creation after this MasterPlan is complete.


## Decomposition Strategy

The work is decomposed by release-blocking concern rather than by source directory. Each child ExecPlan produces an independently verifiable behavior: a tarball build succeeds, generated paths are constrained, migrations and removals reject unsafe paths, manifest writes are atomic, empty recipes fail gracefully, Cabal metadata passes Hackage checks, and public documentation no longer points users at stale or private material.

Seven child plans are used because the audit found seven distinct classes of work with different validation gates. Combining them would make implementation hard to resume and would blur safety fixes with documentation and packaging. The first five plans are code/package correctness; the final two are release presentation and public-facing polish.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-1 | Package embedded CLI assets for Hackage | docs/plans/41-package-embedded-cli-assets-for-hackage.md | None | None | Complete |
| EP-2 | Constrain rendered generation paths | docs/plans/42-constrain-rendered-generation-paths.md | None | EP-3 | Not Started |
| EP-3 | Validate migration and removal paths | docs/plans/43-validate-migration-and-removal-paths.md | None | EP-2 | Not Started |
| EP-4 | Make manifest writes atomic | docs/plans/44-make-manifest-writes-atomic.md | None | None | Not Started |
| EP-5 | Make recipe expansion total | docs/plans/45-make-recipe-expansion-total.md | None | None | Not Started |
| EP-6 | Add Hackage metadata and license | docs/plans/46-add-hackage-metadata-and-license.md | None | EP-1 | Not Started |
| EP-7 | Clean public documentation for release | docs/plans/47-clean-public-documentation-for-release.md | EP-6 | EP-1, EP-2, EP-3, EP-4, EP-5 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix.


## Dependency Graph

EP-1 can begin immediately. It fixes a confirmed Hackage source distribution build failure by packaging files that are embedded by Template Haskell in the CLI executable. EP-6 has a soft dependency on EP-1 because both touch Cabal metadata, but either can be implemented first if the implementer carefully merges Cabal edits.

EP-2 and EP-3 can proceed in either order, but they share a path-safety concept. EP-2 owns rendered generation destination and command work-directory validation. EP-3 owns author-declared migration and removal paths. If one plan creates a shared path-safety helper, the other should reuse it rather than creating an incompatible duplicate.

EP-4 and EP-5 are independent code hardening plans. EP-4 changes the manifest writer implementation and tests atomic write behavior. EP-5 makes recipe expansion total and ensures invalid recipes surface as structured errors instead of crashes.

EP-7 depends hard on EP-6 because README and public docs should name the final license and package metadata. It has soft dependencies on EP-1 through EP-5 because public documentation should accurately describe the safety and packaging behavior after those changes, but it can start with a draft inventory before every code plan is complete.


## Integration Points

Path safety is shared by EP-2 and EP-3. The shared artifact should be a small helper in `seihou-core`, either in `Seihou.Core.Module` or a new focused module, that decides whether a project-relative path is safe. It must reject absolute paths and any path segment equal to `..`; it should not reject a harmless string merely because two dots appear inside a filename such as `README.v2.md`. EP-2 applies the helper after destination and command work-directory interpolation. EP-3 applies the helper to migration and removal declarations before disk mutation.

`seihou-cli/seihou-cli.cabal` is shared by EP-1 and EP-6. EP-1 adds `extra-source-files` entries for embedded help and prompt assets. EP-6 adds release metadata, dependency bounds, license information, and possibly source repository metadata. The later plan should preserve the earlier `extra-source-files` entries.

`README.md` is shared by EP-6 and EP-7. EP-6 updates the license pointer after adding the actual license file. EP-7 updates the user-facing command and documentation links, and should preserve the accurate license text added by EP-6.

Release validation is shared by all plans. The final acceptance for the whole MasterPlan is a clean local build/test/check sequence, `cabal check` for both packages, and a build from freshly generated `sdist` tarballs using only the source distributions plus Hackage-resolved dependencies.


## Progress

- [x] EP-1: Add embedded CLI help and prompt assets to the source distribution.
- [x] EP-1: Prove the `seihou-cli` tarball builds far enough to compile embedded files.
- [ ] EP-2: Add post-render safety checks for generated file paths and command work directories.
- [ ] EP-2: Add regression tests for variable-expanded `..` and absolute paths.
- [ ] EP-3: Validate migration and removal paths before destructive operations.
- [ ] EP-3: Add regression tests for unsafe move/delete/remove declarations.
- [ ] EP-4: Replace manifest double-write with an actual atomic temp-write and rename flow.
- [ ] EP-4: Add tests or a focused smoke check that verifies temp files do not remain after normal writes.
- [ ] EP-5: Make recipe expansion handle empty module lists without partial functions.
- [ ] EP-5: Validate recipe discovery/run paths so invalid recipes fail with user-facing errors.
- [ ] EP-6: Add Hackage metadata, dependency bounds, and a real license file.
- [ ] EP-6: Make `cabal check` pass for both public packages.
- [ ] EP-7: Remove stale internal/proposed public documentation links and claims.
- [ ] EP-7: Run final release-readiness validation from source distributions.


## Surprises & Discoveries

The audit found that `cabal sdist all` succeeds even when the CLI source distribution is incomplete. The failure only appears when building from the tarball: `src-exe/Seihou/CLI/Help.hs` tries to embed `help/agent.md`, but `help/agent.md` is absent from the tarball.

The audit also found that the local `just test` gate passed with 850 core tests and 226 CLI tests. The release-readiness blockers are therefore not broad test failures; they are targeted safety, packaging, and documentation issues.

During EP-1 validation, the unpacked source distribution build emitted existing `-Wx-partial` warnings in `seihou-core/src/Seihou/Composition/Recipe.hs` for `head` and `tail`. This confirms the EP-5 scope, and it did not block the EP-1 package asset fix.


## Decision Log

- Decision: Track release-readiness as seven child ExecPlans.
  Rationale: The audit findings are independently verifiable and touch different concerns. Separate plans make it possible to implement safety fixes, packaging fixes, and documentation cleanup without mixing unrelated changes.
  Date: 2026-06-05

- Decision: Treat path safety as a shared integration point rather than duplicating ad hoc checks.
  Rationale: Generated paths, command work directories, migrations, and removals all need the same definition of a safe project-relative path. One helper reduces drift and makes future audits simpler.
  Date: 2026-06-05

- Decision: Leave actual release cutting out of scope.
  Rationale: The repository already has a dedicated release skill. This initiative prepares the repository so that release workflow can run without predictable Hackage or public-doc blockers.
  Date: 2026-06-05


## Outcomes & Retrospective

To be filled during and after implementation.
