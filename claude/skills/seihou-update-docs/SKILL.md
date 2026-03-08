---
name: seihou-update-docs
description: Update seihou documentation after code changes. Checks docs/user/CHANGELOG.md for the last reviewed commit, analyzes git changes since then, and ensures new features and commands are documented.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Update seihou Documentation

This skill helps keep seihou documentation in sync with code changes by analyzing commits since the last documentation review.

**Project:** seihou — Composable, type-safe project scaffolding system

## When to Use

Activate when the user says things like:
- "Update the docs"
- "Check if docs are up to date"
- "Document recent changes"
- "Sync documentation with code"
- "/update-docs"

## Workflow

### Step 1: Check Last Reviewed Commit

Read the changelog to find the last reviewed commit:

```bash
cat docs/user/CHANGELOG.md
```

Look for the "Last Reviewed Commit" section which contains the commit hash that documentation was last synced to.

### Step 2: Get Commits Since Last Review

List all commits since the last reviewed commit:

```bash
git log --oneline LAST_COMMIT..HEAD
```

If there are no new commits, inform the user that documentation is up to date.

### Step 3: Analyze Changes

For each commit, examine the changes to identify:

1. **New features** — Look for changes in source directories: `seihou-core/src/, seihou-cli/src/`
2. **Changed behavior** — Look at commit messages and code changes
3. **New CLI commands** — Look for changes in `seihou-cli/src/Seihou/CLI/`
4. **Modified command options** — Look for parser/flag changes

```bash
# See what files changed
git diff --name-only LAST_COMMIT..HEAD

# See detailed changes for source directories
git diff LAST_COMMIT..HEAD -- seihou-core/src/, seihou-cli/src/
```

### Step 4: Identify Documentation Gaps

Compare changes against existing documentation:

**User Documentation** (`docs/user/`):
1. **CLI docs** — Command reference and usage guides
2. **Quickstart/README** — Getting started guide
3. **Feature docs** — Individual feature documentation

**Developer Documentation** (`docs/dev/`):
1. **Module docs** — Per-module documentation (domain model, business rules)
2. **Architecture** — System design and patterns
3. **Design decisions** — ADRs and design documents

Check if:
- New commands are listed in the command reference
- New options are documented in command-specific files
- New features have appropriate documentation
- Module docs are updated for domain changes
- Skills are updated if workflows changed

### Step 5: Update Documentation

For each identified gap:

1. **New commands**: Add to command reference and create/update the relevant command doc file

2. **New options**: Update the relevant command doc file with:
   - Option description
   - Usage examples
   - Any caveats or special behavior

3. **Domain changes**: Update the relevant module doc:
   - New commands/events in Domain Model section
   - New business rules
   - New subscriptions or integrations

4. **Behavioral changes**: Update relevant documentation to reflect new behavior

5. **Skills**: If the change affects a skill workflow, update the skill in `claude/skills/`

### Step 6: Update Changelog

After updating documentation, update `docs/user/CHANGELOG.md`:

1. Update the "Last Reviewed Commit" section with the latest commit hash
2. Add a new dated entry summarizing what was documented

Example format:
```markdown
## Last Reviewed Commit

```
abc1234 Latest commit message here
```

---

## Changelog

### YYYY-MM-DD

**Reviewed commits:** `LAST_COMMIT` through `NEW_COMMIT`

- [Summary of changes documented]
- [New commands/options added]
- [Features documented]

**Features documented:**
- [Feature 1 description]
- [Feature 2 description]

**Skills updated:** (if applicable)
- `skill-name`: [what was updated]
```

## Output Format

After completing the documentation update:

```
## Documentation Update Complete

### Commits Reviewed
- `abc1234` Commit message 1
- `def5678` Commit message 2
...

### Documentation Changes
- Updated `docs/user/...`: Added new feature documentation
- Updated `docs/dev/...`: Updated module documentation

### Changelog Updated
- Last reviewed commit: `NEW_COMMIT`
- Entry added for YYYY-MM-DD

### No Documentation Needed (if applicable)
- `abc1234` Internal refactoring, no user-facing changes
- `def5678` Test-only changes
```

## Git Trailers for Documentation Tracking

Use git trailers to link commits to documentation. This enables automated tracking and discovery.

### Using Trailers to Find Undocumented Changes

```bash
# Find feature commits that may need documentation
git log --oneline LAST_COMMIT..HEAD --grep="Feature-Doc:" --invert-grep | head -20

# Find commits with design docs (already documented)
git log --oneline LAST_COMMIT..HEAD --grep="Design-Doc:"
```

### Adding Trailers When Committing Documentation Updates

When committing documentation updates, use appropriate trailers:

```
Update module documentation for new feature

Add feature rules and subscription documentation to module docs.

Module-Doc: docs/dev/modules/<module>/README.md
Module: <module-name>
Change-Type: docs
```

### Standard Documentation Trailers

| Trailer | Use For |
|---------|---------|
| `Feature-Doc:` | User-facing feature documentation |
| `Design-Doc:` | Design decision documentation |
| `Module-Doc:` | Module doc updates |
| `Architecture-Doc:` | Architecture documentation updates |
| `Bug-Doc:` | Bug investigation/fix documentation |

## Important Notes

- Always read the actual code changes before updating documentation
- Keep documentation concise and focused on user-facing features
- Use consistent formatting with existing documentation
- Include practical examples where helpful
- Not all commits need documentation — internal refactoring, tests, and infrastructure changes often don't need doc updates
- When in doubt, check if a feature is user-facing before documenting
- Use git trailers to track documentation in commits for discoverability

## Files to Check

| Change Type | Documentation Files |
|-------------|---------------------|
| New CLI command | `docs/user/cli/README.md`, `docs/user/cli/<command>.md` |
| New command option | `docs/user/cli/<command>.md` |
| New domain feature | `docs/user/` and `docs/dev/modules/<module>/README.md` |
| New business rules | `docs/dev/modules/<module>/README.md` |
| Changed behavior | Relevant files in `docs/user/` and `docs/dev/` |
| New workflow | `claude/skills/*/SKILL.md` if affects skills |
| Architecture change | `docs/dev/architecture/*.md` |
| Design decision | `docs/dev/design/*.md` |
