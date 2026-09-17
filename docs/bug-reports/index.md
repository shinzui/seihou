---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Bug Report

- [Targeted `seihou update` is broken on any manifest that predates `additiveOnly`, and the remedies it prints make it worse](additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md) - On a manifest written before FileRecord.additiveOnly, a single-module `seihou update <target>` fails closed on `.gitignore`; the two remedies the error surfaces first — `--include-shared-owners` and "select every owner" — broaden the write set and print opaque applicationId hashes instead of recording the additive fact, and the `CrossApplicationLastWriter` warning both paths emit is raw derived `Show` output.
