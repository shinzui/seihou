# ADR 0005 — Legacy manifests convert through an explicit command, and the compatibility guard has no removal date

- Status: Accepted
- Date: 2026-07-28
- Amended: 2026-09-18 — `seihou manifest repair-origins` is a second explicit,
  inference-bearing manifest command under the same rule
  (`docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md`).

## Context

Schema version 6 removed the absolute filesystem paths that every earlier
manifest recorded
([ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)).
Manifests at version 5 and earlier are already committed in people's
repositories, so they have to keep working somehow.

The conversion is not mechanical. Turning
`/Users/shinzui/.config/seihou/installed/haskell-base` into a `RemoteOrigin`
means recovering a git URL that the recorded path never contained, from the
*current* machine's install metadata — which may disagree with what the original
author had, or may be missing entirely. The conversion is an inference, and its
result is written into a file that is committed and that every later command
trusts.

## Decision

Conversion is an explicit command — `seihou manifest upgrade` — that prints
every conversion it makes. It is never an automatic upgrade on first read.

This explicit boundary applies to inference-bearing conversion. A later
adjacent schema step that is deterministic and lossless may be staged by a
command that requires its capability, provided the command validates the final
document and commits the manifest atomically with its other changes. The
classification and ordered-step requirements are defined by
[ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md).

Until it is run, a schema-5-or-earlier manifest fails to decode.
`Seihou.Manifest.Types.checkManifestVersion` refuses it with a message naming
the command, rather than misreading it or silently converting it.

Where inference cannot establish an upstream, the entry becomes a `LocalOrigin`
carrying only the artifact's name, and the report says so. A partial conversion
that honestly marks what it could not determine is more useful than no
conversion, and `LocalOrigin` is exactly the constructor meaning "provenance
unknown", so nothing downstream is misled.

Before writing, the command checks the converted manifest against what is
installed on this machine and refuses if anything is missing or stale, because
that is the case where inference is weakest and where committing a guess would
lose an upstream URL for everyone. `--force` writes anyway.

**The version guard and the converter have no removal date.** They stay until
there is positive evidence that no legacy manifests remain in use.

## Consequences

The inference is visible and reviewable. `--dry-run` shows the report without
writing, the result is an ordinary git diff, and `git checkout --` undoes it.
That is the whole reason it is a command rather than a decode path.

Refusing to read an old manifest is a hard break for existing projects, and it
is deliberate. The alternative — reading it and guessing — would reintroduce, at
the moment of conversion, exactly the silent substitution the schema change
exists to remove.

The converted document is the *rewritten original*, not a re-encoded
`Manifest`. Only the three keys holding paths are replaced; every other field
survives byte for byte, including any a later schema version added. It is
validated by decoding into a `Manifest` before the write, so a conversion that
would produce an unreadable manifest fails without touching the file.

Nobody should invent a deprecation schedule for the legacy path. It is a
self-contained module (`Seihou.CLI.ManifestUpgrade`) with no runtime cost to
anything else, so there is no pressure to date its removal, and a date announced
without evidence is a promise to break somebody's repository for no gain.
Deleting it is safe only when someone can say why no legacy manifest remains —
and if that day comes, the reason belongs in a revision to this record.

Positive decoding coverage for schema versions 1 through 5 lives with the
converter, in `seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs`, not with the
manifest decoder — those versions are no longer decodable by the ordinary
decoder at all, so what can be asserted about them is that they convert.

*Amended 2026-09-18 (`docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md`):*
the same rule governs `seihou manifest repair-origins`, which replaces origins
recorded as a path on one machine (see the 2026-09-18 amendment to
[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)).
Choosing a remote for such a path is inference, from the checkout's `origin`
remote or the installed copy's recorded source. The command therefore never runs
implicitly. It prints each proposal with its evidence, has `--dry-run`, and
writes nothing for a path whose evidence conflicts or is missing unless the user
supplies `--set NAME=URL`. It differs from `seihou manifest upgrade` in two
ways. It works on a decoded manifest at the current schema and refuses an older
one, naming `seihou manifest upgrade`, because the step to schema 7 is lossless
and cheap. It also rewrites by URL rather than by record, so every record under
one path receives the same new identity
([ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)).

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
  — distinguishes deterministic adjacent upgrades from inference-bearing
  conversion.
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`
- `docs/user/manifest-upgrade.md`
