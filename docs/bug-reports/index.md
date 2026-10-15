---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Bug Report

- [Targeted `seihou update` is broken on any manifest that predates `additiveOnly`, and the remedies it prints make it worse](additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md) - A single-module `seihou update <target>` fails closed on a co-owned `.gitignore` whenever the manifest predates the `FileRecord.additiveOnly` field, and the two remedies the error surfaces first broaden the write set and print opaque applicationId hashes instead of recording the additive fact.
- [`seihou install` installs a recipe or module without its declared dependencies, so the installed artifact cannot run](install-ignores-recipe-and-module-dependencies.md) - Installing a recipe (or module) from a registry with `seihou install --module <name>` installs only the named entry and never its transitive `modules`/`dependencies`, so the first `seihou run <name>` fails with "Module '<dep>' not found" even though the dependency is present in the same registry.

