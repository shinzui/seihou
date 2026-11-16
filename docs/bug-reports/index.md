---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Bug Report

- [A blueprint baseline applies its modules' files but silently skips their commands](a-blueprint-baseline-silently-skips-its-modules-commands.md) - `seihou agent run` applies `baseModules` without running the modules' Apply commands, which `seihou run` of the same module runs, and neither the guide nor the run output says so, so a baseline whose commands check or complete the generated files leaves them unchecked.
- [`seihou agent --debug run` records the blueprint as applied, though no agent ran](a-debug-blueprint-run-records-the-blueprint-as-applied.md) - Rendering a runnable blueprint's prompt with `seihou agent --debug run <blueprint>` writes a `blueprint` record (name, origin, version, appliedAt) into `.seihou/manifest.json` that cannot be told from a real application, so a repository where someone only inspected a prompt claims a blueprint it never received, while migration debug leaves the manifest untouched.
- [A recipe cannot enforce a variable that global config sets, so a TAN repository is created under a personal GitHub account](a-recipe-cannot-enforce-a-variable-that-global-config-sets.md) - A recipe has no way to hold a module variable to a fixed value once the user sets it in global config. Dependency var bindings reject camelCase names such as `git.githubOwner`, and a recipe VarDecl's pattern validation silently accepts unrecognized patterns from every source, including config. `seihou run tan-keiro-project` with `git.createGithub=true` therefore creates the repository under whatever owner the user configured globally, not the organization the recipe declares.
- [Targeted `seihou update` is broken on any manifest that predates `additiveOnly`, and the remedies it prints make it worse](additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md) - A single-module `seihou update <target>` fails closed on a co-owned `.gitignore` whenever the manifest predates the `FileRecord.additiveOnly` field, and the two remedies the error surfaces first broaden the write set and print opaque applicationId hashes instead of recording the additive fact.
- [`seihou install` installs a recipe or module without its declared dependencies, so the installed artifact cannot run](install-ignores-recipe-and-module-dependencies.md) - Installing a recipe (or module) from a registry with `seihou install --module <name>` installs only the named entry and never its transitive `modules`/`dependencies`, so the first `seihou run <name>` fails with "Module '<dep>' not found" even though the dependency is present in the same registry.
