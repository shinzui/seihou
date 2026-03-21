# Documentation Changelog

## Last Reviewed Commit

```
f115d6b Add seihou remove command for reversible module removal
```

---

## Changelog

### 2026-03-21 (remove command)

**Reviewed commits:** `cf7aeac` through `f115d6b`

- Added `docs/cli/remove.md` — CLI reference for the new `seihou remove` command
- Updated `docs/user/module-authoring.md` — added `removable` field to module.dhall format reference, added "Removing modules" section with reversibility guidance
- Updated `docs/user/getting-started.md` — added "Removing a module" to the Other commands section
- Updated `docs/dev/design/proposed/cli-commands.md` — added `seihou remove` command spec, moved from future enhancements to documented, updated command count to eighteen
- Updated `docs/dev/architecture/overview.md` — added `Remove.hs` to project tree (engine + CLI), updated Filesystem effect description

**Features documented:**
- `seihou remove <module> [--dry-run] [--force] [--verbose]` command for reversible module removal
- `removable : Bool` field in module.dhall (default `False`) — opt-in for module removal
- `RemoveFile` and `RemoveDirectoryIfEmpty` Filesystem effect operations
- Removal plan classification: safe (unchanged), conflict (modified), gone (deleted)

**No documentation needed:**
- `cf7aeac` Fix bool value comparison in conditional expressions (bug fix, no user-facing doc impact)

### 2026-03-21 (schema URL imports)

**Reviewed commits:** `87ab9c9` through `a184a71`

- Updated `docs/user/module-authoring.md` — schema package section now shows URL-based imports from `seihou-schema` GitHub repo; schema-upgrade section documents `MissingSchemaImport` detection
- Updated `docs/cli/schema-upgrade.md` — added missing schema import to the list of handled transformations
- Updated `seihou-cli/help/modules.md` — schema package section updated to show URL import pattern
- Updated `seihou-cli/data/assist-prompt.md` — schema package example uses URL import
- Updated `seihou-cli/data/bootstrap-prompt.md` — schema package example uses URL import

**Features documented:**
- Schema is now published at `github.com/shinzui/seihou-schema` and imported via pinned HTTPS URL with integrity hash
- `seihou new-module` generates modules with schema URL imports and record completion (`S.Module::`)
- `seihou schema-upgrade` detects and injects missing schema imports (`MissingSchemaImport`)
- `update-seihou-schema` Claude Code skill for bumping the schema pin

**No documentation needed:**
- `a184a71` Finalize publish-schema-repo plan (plan doc)
- `1ffde57` Fix update-seihou-schema skill location (tooling)
- `8bd9e04` Create update-seihou-schema skill (tooling)
- `c4b9bc3` Update Nix build to handle schema submodule (infrastructure)
- `e65cc51` Remove schema/ from tracking (internal git change)

### 2026-03-21

**Reviewed commits:** `378dafc` through `8daa78c`

- Added `docs/cli/schema-upgrade.md` — CLI reference for the new `seihou schema-upgrade` command
- Updated `docs/user/module-authoring.md` — standardized dependency format to record form, added schema package and record completion section, added schema-upgrade section
- Updated `docs/user/getting-started.md` — updated scaffold boilerplate to use record-form deps, added schema-upgrade to "Other commands"
- Updated `seihou-cli/help/modules.md` — added dependency record form examples, schema package section, schema-upgrade to common commands

**Features documented:**
- `seihou schema-upgrade [PATH] [--dry-run] [--all]` command for upgrading module.dhall files to current schema
- Dhall schema package (`schema/package.dhall`) with record completion (`::`) support
- Standardized dependency format: `{ module : Text, vars : List { name : Text, value : Text } }`

**No documentation needed:**
- `da7591a` Audit and update all docs to reflect current codebase state (meta — already captured in 2026-03-20 entry)
- `d849d19` Show help when seihou is invoked without a command (UX improvement, no doc change needed)

### 2026-03-20

**Reviewed commits:** `fe1819a` through `378dafc`

- Full documentation audit: all dev docs, user docs, and product specs reviewed against codebase
- Updated status on 4 design docs from "Proposed" to "Implemented" (architecture, composition, generation-strategies, manifest)
- Updated roadmap status from "In Progress" to "Done"; added milestones M10–M14
- Updated CLI commands doc with 5 new commands: outdated, upgrade, help, completions, agent
- Fixed Command ADT to match actual code (17 constructors)
- Added `version` field to Module type in module-system.md and module-authoring.md
- Added `FromParent` to variable resolution precedence chain (9 tiers, not 8)
- Fixed PatchOp type in composition doc (3 constructors, not 5)
- Fixed CompositionWarning type to match code (ContentMerged, not UnusedExport)
- Fixed Strategy type in generation-strategies doc (no StructuredFormat parameter)
- Added RegistryEvalError to ModuleLoadError
- Updated architecture overview project layout tree with all current files
- Added parameterized dependency documentation to module-authoring.md and variable-resolution.md
- Added outdated/upgrade/completions/help sections to getting-started.md
- Added parent bindings to config-and-variables.md resolution hierarchy
- Updated parser tree in cli-commands.md

**Documentation status:**
- `docs/user/getting-started.md`: Updated with outdated, upgrade, completions, help commands
- `docs/user/module-authoring.md`: Updated with version field, parameterized dependencies, FromParent
- `docs/user/config-and-variables.md`: Updated with 9-tier resolution hierarchy including parent bindings
- `docs/user/registries-and-multi-module-repos.md`: Up to date (no changes needed)
- `docs/dev/architecture/overview.md`: Updated status, project layout tree
- `docs/dev/design/proposed/cli-commands.md`: Updated with all 17 commands
- `docs/dev/design/proposed/module-system.md`: Updated Module type, Dependency type, Dhall schema
- `docs/dev/design/proposed/variable-resolution.md`: Updated with FromParent source
- `docs/dev/design/proposed/composition-and-layering.md`: Updated PatchOp, CompositionWarning
- `docs/dev/design/proposed/generation-strategies.md`: Updated Strategy type
- `docs/dev/design/proposed/manifest-and-incrementality.md`: Status updated
- `docs/dev/roadmap/v1-milestones.md`: Updated status, added M10–M14
- `docs/dev/versioning.md`: Up to date (no changes needed)

**No documentation needed:**
- `0f532a9` Add .seihou/manifest.json.tmp to gitignore (internal)
- `afb9678` Add seihou-update-docs skill (tooling)
- `fe1819a` Add documentation changelog (meta)
- `18148c6` Add ExecPlan for help topics (plan doc)
- `721d46d` Mark parameterized dependencies plan as complete (plan doc)
- `8d3527c` Add git worktree tools to agent allowed tools (tooling)
- `6b27cf1` Grant agent setup full git and seihou permissions (tooling)

### 2026-03-07

**Reviewed commits:** `94e0052` (init) through `b6baa4f`

- Initial documentation review covering all commits to date
- All user-facing features are documented

**Documentation status:**
- `docs/user/getting-started.md`: Complete end-to-end guide covering all CLI commands
- `docs/user/module-authoring.md`: Complete module format reference (variables, steps, strategies, commands, composition)
- `docs/user/config-and-variables.md`: Configuration scopes, variable resolution, and context-aware variables
- `docs/user/registries-and-multi-module-repos.md`: Registry metadata and multi-module repository support
- `docs/dev/versioning.md`: Version embedding with git SHA (dual-path: TH + Nix CPP)
- `docs/dev/architecture/overview.md`: System architecture and effect stack

**No documentation needed:**
- `49775a7` Add result to gitignore (internal)
- `ded95f8` Add haskell-nix for GHC 9.12 tool patches (infrastructure)
