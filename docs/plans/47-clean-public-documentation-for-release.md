---
id: 47
slug: clean-public-documentation-for-release
title: "Clean public documentation for release"
kind: exec-plan
created_at: 2026-06-05T14:34:26Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Clean public documentation for release

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, the public documentation reads like documentation for a released tool, not an internal implementation notebook. Users can start from `README.md`, follow user and CLI guides, and avoid stale links to proposed designs, private paths, or historical plan logs.

This plan does not delete useful development history by default. It decides what belongs in public user docs, what can remain in clearly internal developer docs, and what should be excluded from release-facing links.


## Progress

- [ ] Inventory public-facing docs for stale, proposed, private, and internal references.
- [ ] Update `README.md` to point at implemented user docs and the real license.
- [ ] Update CLI docs that mention future work as if it has not landed.
- [ ] Remove release-facing links to `docs/dev/design/proposed` where stable user docs exist.
- [ ] Decide how to handle `docs/user/CHANGELOG.md` as an internal doc-review log.
- [ ] Run documentation grep checks and smoke CLI help output.


## Surprises & Discoveries

The audit found `docs/cli/new-blueprint.md` still says `seihou agent run` is "landing in EP-31" even though the command exists.


## Decision Log

- Decision: Treat README, `docs/user`, `docs/cli`, and embedded `seihou-cli/help` topics as public release-facing docs.
  Rationale: These are the paths users are likely to read from Hackage, GitHub, or `seihou help`.
  Date: 2026-06-05


## Outcomes & Retrospective

To be filled during and after implementation.


## Context and Orientation

The repository has several documentation tiers:

- `README.md` is the public first page.
- `docs/user/` contains user guides.
- `docs/cli/` contains command references.
- `seihou-cli/help/` contains Markdown embedded into the CLI binary.
- `docs/dev/`, `docs/plans/`, and `docs/masterplans/` are developer and planning material.

The audit found release-facing docs that link users to proposed internal design docs, mention future execution plans, or include private absolute paths in internal plan history. Internal plans can remain if the repository owner wants public development history, but the main user journey should not depend on them.


## Plan of Work

Milestone 1 inventories public docs. Search only release-facing paths first:

```bash
rg -n "docs/dev|docs/plans|proposed|/Users/shinzui|Keikaku|EP-[0-9]+|landing in|TODO|FIXME|LICENSE file" README.md docs/user docs/cli seihou-cli/help
```

Classify each hit as one of: correct internal/developer reference, stale public reference, private path leak, or harmless example text.

Milestone 2 fixes README. Update the blueprint section so it points to `docs/user/blueprints.md` and relevant `docs/cli/*.md` command references instead of `docs/dev/design/proposed/blueprints.md`. Ensure the License section matches the license added by `docs/plans/46-add-hackage-metadata-and-license.md`.

Milestone 3 fixes user and CLI docs. Replace future-tense text with implemented behavior. In particular, update `docs/cli/new-blueprint.md` so it no longer says the agent runner is "landing in EP-31". Where `docs/user/templating.md` links to proposed design docs, prefer stable user docs or clearly label those links as developer design background.

Milestone 4 handles `docs/user/CHANGELOG.md`. This file is currently a detailed doc-review log with references to internal plans and master plans. Decide whether to rename it to a developer-facing path, keep it but remove it from public navigation, or rewrite it into a concise user changelog. The implementation should avoid presenting it as ordinary end-user documentation unless it is cleaned up.

Milestone 5 validates embedded help. Run `seihou help` topics from a local build or `cabal run seihou -- help <topic>` to ensure embedded help still renders and does not point at stale docs.


## Concrete Steps

Run the inventory:

```bash
rg -n "docs/dev|docs/plans|proposed|/Users/shinzui|Keikaku|EP-[0-9]+|landing in|TODO|FIXME|LICENSE file" README.md docs/user docs/cli seihou-cli/help
```

Run help smoke checks:

```bash
cabal run seihou -- help blueprints
cabal run seihou -- help agent
cabal run seihou -- help templating
```

Run a broad docs grep after edits:

```bash
rg -n "/Users/shinzui|Keikaku|landing in|docs/dev/design/proposed" README.md docs/user docs/cli seihou-cli/help
```

The expected result is either no output, or only consciously retained developer-background references that are explained in the surrounding prose.


## Validation and Acceptance

Acceptance requires:

- `README.md` has no stale proposed-design link in its primary user path.
- `README.md` names the actual license file and chosen license.
- `docs/cli/new-blueprint.md` describes `seihou agent run` as implemented.
- Public user docs do not contain private absolute paths.
- Embedded help topics still build and render.
- Any retained links to developer docs are clearly secondary background, not required user instructions.


## Idempotence and Recovery

Documentation edits are safe to retry. If a grep hit is intentionally retained, record the rationale in Surprises & Discoveries so a future auditor does not repeatedly rediscover it. Avoid deleting plan history unless the repository owner explicitly chooses to remove internal planning docs from the public repo.


## Interfaces and Dependencies

This plan depends hard on `docs/plans/46-add-hackage-metadata-and-license.md` for final license wording. It has soft dependencies on the safety and packaging plans because docs should describe the behavior that actually ships. It touches Markdown files only unless embedded help changes require Cabal asset packaging already covered by EP-1.
