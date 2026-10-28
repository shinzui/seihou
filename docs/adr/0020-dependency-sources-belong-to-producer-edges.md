# ADR 0020 — Dependency sources belong to producer edges and install owns acquisition

- Status: Accepted
- Date: 2026-10-28

## Context

Recipes and modules previously named their members without identifying a supplying
registry. Installing a recipe copied its directory but left developers to discover
and install transitive members. The installed cache remains keyed by bare name;
ADRs [0002](0002-artifact-identity-is-origin-url-plus-name.md) and
[0006](0006-the-install-cache-will-not-silently-substitute-an-artifact.md) require
origin checks before replacing that shared installation.

## Decision

A dependency edge carries an optional literal Git `source` alongside its module name
and generation variable bindings. The producer owns the supplying origin. No source
means the declaring registry during acquisition; there is no registry search or Mori
runtime dependency. Existing bare text and record declarations remain decodable.

Install acquires the combined closure of selected roots before changing the cache.
Repository identity uses the shared URL normalization rules; artifact identity is
origin plus name. Bindings distinguish generation instances, never acquired artifacts.
Conflicting origins under one name cannot be satisfied by force. Cache collisions
retain the explicit force override from ADR 0006.

Definitions are normalized while their source checkouts exist, so imports outside
an artifact directory do not dangle after installation. Payload path escapes and
symlinks are rejected. Replacements retain backups until success; handled failures
restore them, and failed recovery preserves its directory for inspection. This is
not a crash-atomic transaction across the entire cache.

Run and dry-run remain local. Explicit source requirements must match readable origin
metadata on the resolved dependency, even without a project manifest. An unproven
local shadow cannot satisfy them. Install materializes absent sources using the declaring origin. Older cached and
project-local legacy declarations keep ordinary discovery until reinstalled.
Synthetic dependencies introduced by recipe expansion or additional CLI modules do
not inherit the primary module's origin: only producer-declared edges do.

## Consequences

A normal recipe workflow is one install followed by one run. Reinstall repairs older
incomplete installations. Failure diagnostics carry the requested source and parent
chain. The manifest remains the only applied-state record; source requirements add
no lockfile and generation performs no acquisition. Upgrade the executable before
adopting a schema that emits the new field.

The schema, executable, and actual producer must be delivered together before a
consumer workflow can be called complete. Source tests and a fixture establish
implementation behavior, while published and installed versions need separate proof.
