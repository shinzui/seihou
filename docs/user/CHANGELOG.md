# Changelog

## 0.2.0.0 - 2026-06-06

This release-readiness snapshot prepares Seihou for its first public Hackage
release. It adds BSD-3-Clause licensing and complete package metadata, packages
the CLI's embedded help and prompt files in source distributions, and hardens
filesystem writes and path validation before generation, migration, removal,
and manifest updates.

User-visible documentation now describes the shipped module, recipe, blueprint,
prompt, agent, migration, registry, and configuration behavior. The detailed historical
documentation-review log is developer-facing.

### Added

- BSD-3-Clause license files for the repository and both Cabal packages.
- Hackage metadata for `seihou-core` and `seihou-cli`.
- Source distribution packaging for embedded CLI help topics and agent prompt
  templates.
- Agent-driven blueprints as the third runnable artifact kind, with user guides
  and CLI command references.
- First-class prompts as the fourth runnable artifact kind, with authoring,
  validation, running, registry, list, and install documentation.

### Changed

- Manifest persistence now writes through an atomic temp-file-and-rename flow.
- Recipe expansion now reports invalid recipes as structured errors instead of
  relying on partial list operations.
- `seihou migrate` uses a gap-tolerant migration walker that applies declared
  migrations in range and advances the manifest to the target version.

### Fixed

- Generated file paths and command working directories reject absolute paths,
  blank paths, and `..` path segments.
- Migration and removal declarations reject unsafe filesystem paths before disk
  mutation.
- Public documentation no longer directs users through internal design docs or
  internal implementation plans for normal workflows.
