---
name: seihou-release
description: Prepare and create a new release by updating cabal versions, CHANGELOG, and creating a GitHub release.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Skill, AskUserQuestion
---

# Seihou Release

This skill orchestrates the release process by analyzing changes since the last release, suggesting a version number, updating cabal files and the changelog, and creating a GitHub release.

**Project:** seihou — Composable, type-safe project scaffolding system

## When to Use

Activate when the user says things like:
- "Create a release"
- "Prepare a release"
- "Make a new release"
- "Release the changes"
- "/release"

## Workflow

### Step 1: Pre-flight Checks

Before starting, verify the working tree is clean:

```bash
git status --porcelain
```

If there are uncommitted changes, warn the user and suggest committing or stashing first.

### Step 2: Get Latest Release Information

Find the latest GitHub release and its tag:

```bash
gh release list --limit 1 --json tagName,publishedAt
```

Get the current version from the cabal files:

```bash
grep "^version:" seihou-cli/seihou-cli.cabal
grep "^version:" seihou-core/seihou-core.cabal
```

If there are no prior releases, this is the first release. Use the current cabal version as the baseline and all commits as the change set.

### Step 3: Analyze Changes Since Last Release

Get all commits since the last release tag:

```bash
git log --oneline LAST_TAG..HEAD
```

If there is no prior release, use:

```bash
git log --oneline
```

If there are no new commits since the last release, inform the user there's nothing to release.

For detailed change analysis:

```bash
# See what files changed
git diff --stat LAST_TAG..HEAD

# See commit details
git log --pretty=format:"%h %s" LAST_TAG..HEAD
```

Categorize changes by type:
- **Breaking changes**: API changes, removed features, behavior changes
- **New features**: New commands, new options, new functionality (e.g. new generation strategies, new module system features)
- **Improvements**: Enhancements to existing features
- **Bug fixes**: Error corrections, edge case handling
- **Documentation**: Doc updates (usually don't warrant version bump alone)
- **Internal**: Refactoring, tests, infrastructure (don't warrant version bump)

Note: `docs/user/CHANGELOG.md` is a **documentation review log**, not a release changelog — don't confuse the two. The release changelog lives at `CHANGELOG.md` in the repo root.

### Step 4: Suggest Version Number

Based on semantic versioning (MAJOR.MINOR.PATCH.BUILD):

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Breaking changes | MAJOR | 0.1.0.0 -> 1.0.0.0 |
| New features | MINOR | 0.1.0.0 -> 0.2.0.0 |
| Bug fixes, improvements | PATCH | 0.1.0.0 -> 0.1.1.0 |
| Build/metadata only | BUILD | 0.1.0.0 -> 0.1.0.1 |

While seihou is pre-1.0, feel free to bump MINOR for any user-visible change and reserve MAJOR for a 1.0 release.

Present the suggested version to the user with reasoning:

```
## Suggested Version: X.Y.Z.W

### Changes Summary
- N new features
- N improvements
- N bug fixes
- N breaking changes

### Rationale
[Explain why this version bump is appropriate]
```

Ask the user to confirm or specify a different version.

### Step 5: Update Version in Cabal Files

Update the version in both cabal files:

1. `seihou-cli/seihou-cli.cabal`
2. `seihou-core/seihou-core.cabal`

Use the Edit tool to update the `version:` line in each file.

Also update any internal dependency version constraints if the packages depend on each other (e.g., the `seihou-core` dependency in `seihou-cli.cabal`).

### Step 6: Update CHANGELOG.md

The release changelog lives at `CHANGELOG.md` in the repo root. If it does not exist yet, create it with the standard format below.

Move items from `[Unreleased]` to a new version section with today's date. If this is the first release, populate based on the change analysis.

Format for `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [X.Y.Z.W] - YYYY-MM-DD

### Added
- **Feature Name**: Description

### Changed
- Change description

### Fixed
- Bug fix description
```

### Step 7: Format Code

Run the formatter to ensure cabal files are properly formatted:

```bash
just format
```

### Step 8: Build and Test

Ensure the project builds successfully:

```bash
just build
```

Run tests to verify:

```bash
just test
```

If build or tests fail, stop and inform the user of the issues.

### Step 9: Commit Release Changes

Create a commit with the version bump and changelog updates:

```bash
git add seihou-cli/seihou-cli.cabal seihou-core/seihou-core.cabal CHANGELOG.md
git commit -m "Release vX.Y.Z.W"
```

### Step 10: Create Git Tag

Create an annotated tag for the release:

```bash
git tag -a vX.Y.Z.W -m "Release vX.Y.Z.W"
```

### Step 11: Push Changes

Push the commit and tag to the remote:

```bash
git push && git push --tags
```

### Step 12: Create GitHub Release

Create the GitHub release with release notes:

```bash
gh release create vX.Y.Z.W --title "vX.Y.Z.W" --notes "$(cat <<'EOF'
## Major Features

- **Feature Name**: Description

## Improvements

- Improvement description

## Bug Fixes

- Bug fix description
EOF
)"
```

The release notes should be a concise summary of user-facing changes, organized by category.

## Output Format

```
## Release Complete

### Version
- Previous: vX.Y.Z.W
- New: vA.B.C.D

### Changes Included
- N commits since last release
- N new features
- N improvements
- N bug fixes

### Files Updated
- `seihou-cli/seihou-cli.cabal`: version -> A.B.C.D
- `seihou-core/seihou-core.cabal`: version -> A.B.C.D
- `CHANGELOG.md`: Added [A.B.C.D] section

### Git Operations
- Commit: abc1234 "Release vA.B.C.D"
- Tag: vA.B.C.D
- Pushed: Yes

### GitHub Release
- URL: https://github.com/owner/repo/releases/tag/vA.B.C.D
- Status: Created
```

## Important Notes

- **Don't skip the build step** — ensure the release actually compiles
- **User confirmation required** before creating the GitHub release
- **No releases for internal-only changes** — if all changes are refactoring/tests/infrastructure, suggest not releasing
- **Keep release notes user-focused** — don't include internal implementation details
- **Tag format**: Use `vX.Y.Z.W` format (with 'v' prefix)
- **Both cabal packages** share the same version number
- If there are uncommitted changes before starting, warn the user and suggest committing or stashing first
- Always run `just format` before committing to satisfy the pre-commit hook
- Do **not** touch `docs/user/CHANGELOG.md` during a release — it is a doc-review log, not a release changelog

## Version Suggestion Guidelines

When suggesting a version:

1. **If there are breaking changes**: Bump MAJOR (or MINOR while pre-1.0)
2. **If there are new features without breaking changes**: Bump MINOR
3. **If there are only fixes/improvements**: Bump PATCH
4. **If there are only build/metadata changes**: Bump BUILD (rare)

Present the user with:
- The suggested version with clear reasoning
- A summary of changes grouped by type
- Option to choose a different version if they disagree

## Common Patterns

### Release Notes Categories

Standard categories for release notes:

- **Major Features**: Significant new functionality
- **Improvements**: Enhancements to existing features
- **Bug Fixes**: Corrections to incorrect behavior
- **Breaking Changes**: Changes that may affect existing usage (for MAJOR versions)

### Handling No Changes

If `git log LAST_TAG..HEAD` shows no commits:

```
No new commits since the last release (vX.Y.Z.W).

There's nothing to release at this time.
```

### First Release

For the very first release (no prior tags):

1. Use all commits as the change set
2. Create `CHANGELOG.md` from scratch
3. The release notes should give a high-level overview of seihou's capabilities (composable modules, generation strategies, Dhall-driven scaffolding, incremental manifest, etc.)
