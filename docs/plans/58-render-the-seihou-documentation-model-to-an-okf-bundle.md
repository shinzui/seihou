---
id: 58
slug: render-the-seihou-documentation-model-to-an-okf-bundle
title: "Render the seihou documentation model to an OKF bundle"
kind: exec-plan
created_at: 2026-06-19T17:55:29Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Render the seihou documentation model to an OKF bundle

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is part of the MasterPlan at
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`. Read that
file for the overall initiative; this plan stands alone for implementation.

This is the heart of the feature: it turns the in-memory documentation model produced by
EP-57 (`docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md`) into an Open
Knowledge Format (OKF) bundle on disk, using the okf-core authoring API made available by
EP-56 (`docs/plans/56-make-okf-core-a-buildable-dependency-of-seihou.md`).

An OKF bundle is a directory of Markdown documents, each with a YAML frontmatter block
(metadata fenced by `---`) and a Markdown body; Markdown links between documents become a
navigable graph. This plan maps each seihou entity (module, recipe, blueprint, prompt) to one
OKF "concept document": it builds the frontmatter (type, title, description, tags, and a
`resource` pointer back to the authoritative `.dhall`), writes a prose body, and renders the
composition relationships as Markdown cross-links (a recipe links to the modules it composes;
a blueprint to its base modules; a module to its dependencies). It then validates the whole
set with okf-core's `validateBundle` and writes it with `writeBundle`.

The observable outcome: a pure function `renderDocBundle :: DocModel -> ([Concept],
[BundleValidationError])` (concepts plus any validation problems) and an IO function
`writeDocBundle :: FilePath -> DocModel -> IO (Either [BundleValidationError] ())` that writes
the bundle when valid; plus unit/golden tests proving a known model renders to the expected
concept IDs, frontmatter, and cross-links, and that the bundle validates clean. EP-59 wires
these behind the `seihou docs` command.


## Progress

- [ ] Add the concept-ID scheme helpers (`modules/<name>` etc.) and `resource` builder
- [ ] Render each entity kind to an `OKFDocument` (frontmatter + body) and then a `Concept` via `conceptFromDocument`
- [ ] Render cross-links (dependencies / recipe modules / base modules) with `renderConceptLink`
- [ ] Implement `renderDocBundle :: DocModel -> ([Concept], [BundleValidationError])`
- [ ] Implement `writeDocBundle :: FilePath -> DocModel -> IO (Either [BundleValidationError] ())`
- [ ] Unit/golden tests: concept IDs, frontmatter fields, cross-links, clean validation
- [ ] `cabal build all` and `cabal test seihou-cli-test` green


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Concept-ID scheme is `modules/<name>`, `recipes/<name>`, `blueprints/<name>`,
  `prompts/<name>`.
  Rationale: Names are unique within a kind, and all module references (dependencies, recipe
  modules, blueprint base modules) are by bare name, so a reference to module `X` always maps
  to concept `modules/X` — making cross-link targets trivially computable.
  Date: 2026-06-19

- Decision: Build each `Concept` via okf-core's `conceptFromDocument`, putting all metadata in
  the document's frontmatter, rather than constructing the `Concept` record directly.
  Rationale: `conceptFromDocument` derives the typed projection fields (`type_`, `title`,
  `description`, `resource`, `tags`) from the frontmatter, so they cannot drift from what is
  serialized. It is the okf-recommended in-memory producer entry point.
  Date: 2026-06-19

- Decision: Generate without a `timestamp` and validate with `PermissiveConformance` by
  default.
  Rationale: Seihou entities have no natural per-entity timestamp; omitting it keeps
  regenerated output deterministic. The richer fields still make the docs useful. (Strict mode
  + timestamp source are an EP-59 command concern.)
  Date: 2026-06-19


## Context and Orientation

All paths are relative to the seihou repository root
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

This plan consumes the model from EP-57 — `Seihou.CLI.Docs.Model` — whose key types are
(defined there; do not redefine):

```haskell
data DocKind = DocModuleKind | DocRecipeKind | DocBlueprintKind | DocPromptKind
data DocArtifact = DocModuleArtifact Module | DocRecipeArtifact Recipe
                 | DocBlueprintArtifact Blueprint | DocPromptArtifact AgentPrompt
data DocEntry = DocEntry { entryName :: Text, entryKind :: DocKind, entryVersion :: Maybe Text
                         , entryDescription :: Maybe Text, entryTags :: [Text], entryPath :: FilePath
                         , entryArtifact :: DocArtifact, entryModuleRefs :: [ModuleRef] }
data ModuleRef = ModuleRef { refName :: Text, refResolved :: Bool }
data DocModel = DocModel { docRepoName :: Text, docRepoDescription :: Maybe Text, docEntries :: [DocEntry] }
```

The okf-core authoring API this plan calls (exact signatures, from the okf repo — treat as
fixed). From `Okf.Document`:

```haskell
data OKFDocument = OKFDocument { frontmatter :: Frontmatter, body :: Text }
emptyFrontmatter :: Frontmatter
data OkfCommon = OkfCommon { commonType :: Text, commonTitle :: Maybe Text
                          , commonDescription :: Maybe Text, commonTimestamp :: Maybe Text }
okfCommon      :: OkfCommon -> Frontmatter
setResource    :: Text -> Frontmatter -> Frontmatter
setTags        :: [Text] -> Frontmatter -> Frontmatter
setField       :: Text -> Value -> Frontmatter -> Frontmatter   -- for extension keys, e.g. "version"
serializeDocument :: OKFDocument -> Text
```

From `Okf.ConceptId` (note: `ConceptId` is ABSTRACT — build via `parseConceptId`):

```haskell
parseConceptId          :: Text -> Either ConceptIdError ConceptId
renderConceptLinkTarget :: ConceptId -> Text          -- "/modules/x.md"
renderConceptLink       :: ConceptId -> Text -> Text   -- "[label](/modules/x.md)"
```

From `Okf.Bundle`:

```haskell
data Concept = Concept { id :: ConceptId, sourcePath :: FilePath, document :: OKFDocument
                       , type_ :: Text, title :: Maybe Text, description :: Maybe Text
                       , resource :: Maybe Text, tags :: [Text] }
conceptFromDocument :: ConceptId -> OKFDocument -> Concept   -- derives typed fields from the document
writeBundle :: FilePath -> [Concept] -> IO ()                -- writes root/<conceptId>.md; does NOT clear or validate
```

From `Okf.Validation`:

```haskell
data ValidationProfile = PermissiveConformance | StrictAuthoring
data BundleValidationError = DocumentInvalid ConceptId ValidationError
                           | DanglingReference ConceptId ConceptId
                           | DuplicateConceptId ConceptId
validateBundle :: ValidationProfile -> [Concept] -> [BundleValidationError]
```

Three okf-core gotchas to handle in seihou code (seihou uses `lens`/`generic-lens` and enables
`OverloadedRecordDot`):

- `Okf.Document.setField` clashes with the lens `setField` re-exported by seihou's prelude/lens
  imports. Import `Okf.Document` qualified (e.g. `import Okf.Document qualified as Okf`) or
  with `hiding`, in the render module.
- `Okf.Bundle.Concept` has a field `id` that clashes with Prelude `id`; read it via
  `conceptIdOf` (also exported) or `OverloadedRecordDot` (`concept.id`). Avoid bare `id`.
- `parseConceptId` returns `Either ConceptIdError ConceptId`. The IDs this plan generates
  (`modules/<name>` etc.) are always valid *when names obey OKF segment rules* (start with a
  letter/digit/underscore; may contain `.`/`-`). Seihou module names like `nix-haskell-flake`
  are valid. Handle the `Left` case as an internal error (it indicates a name with an illegal
  character such as a leading hyphen) — surface it rather than silently dropping the entity.

okf-core link resolution: only `.md` links resolve, and bundle-absolute (`/path.md`) links
resolve independent of the source document's directory. `renderConceptLink` emits exactly that
form, so cross-links between any two concepts in the bundle resolve.

Seihou test conventions (same as EP-57): tasty + tasty-hspec + hspec; a spec module exports
`tests :: IO TestTree` and is added to `seihou-cli/test/Main.hs` and the test stanza
`other-modules`.

Build/test: `nix develop`; `cabal build all`; `cabal test seihou-cli-test`.


## Plan of Work

Single milestone: a render module plus tests. Create
`seihou-cli/src/Seihou/CLI/Docs/Render.hs`:

```haskell
module Seihou.CLI.Docs.Render
  ( conceptIdFor
  , renderDocBundle
  , writeDocBundle
  ) where
```

Step 1 — concept IDs and resource. Add helpers:

```haskell
-- The OKF concept-ID text for an entry, e.g. "modules/nix-haskell-flake".
conceptIdTextFor :: DocKind -> Text -> Text
conceptIdTextFor kind name = kindDir kind <> "/" <> name
 where
  kindDir DocModuleKind = "modules"
  kindDir DocRecipeKind = "recipes"
  kindDir DocBlueprintKind = "blueprints"
  kindDir DocPromptKind = "prompts"

-- Parse it into an okf ConceptId (internal error on illegal names).
conceptIdFor :: DocKind -> Text -> Either Text ConceptId   -- Left = bad name
```

The `resource` value for an entry is `"seihou://" <> docRepoName <> "/" <> entryPath`.

Step 2 — frontmatter. For each `DocEntry` build a `Frontmatter`:

```haskell
frontmatterFor :: DocEntry -> Frontmatter
frontmatterFor e =
  maybeSetVersion
    . Okf.setTags (entryTags e)
    . Okf.setResource (resourceFor e)
    $ Okf.okfCommon Okf.OkfCommon
        { Okf.commonType = typeFor (entryKind e)            -- "SeihouModule" | "SeihouRecipe" | "SeihouBlueprint" | "SeihouPrompt"
        , Okf.commonTitle = Just (entryName e)
        , Okf.commonDescription = entryDescription e
        , Okf.commonTimestamp = Nothing                      -- deterministic: no timestamp by default
        }
 where
  maybeSetVersion = maybe id (\v -> Okf.setField "version" (String v)) (entryVersion e)
```

(`String` is `Data.Aeson.String`; import `Data.Aeson (Value (..))`. `id` here is Prelude `id`,
fine in this position.)

Step 3 — body. Write `bodyFor :: DocEntry -> Text` that produces Markdown prose. Shared
structure: an `# <name>` heading, the description, a `**Version:** <v>` line if present, and a
kind-specific section. The cross-link sections are the important part — render each module
reference as a Markdown link to its concept:

```haskell
moduleLink :: Text -> Text
moduleLink name =
  case conceptIdFor DocModuleKind name of
    Right cid -> Okf.renderConceptLink cid name
    Left _ -> "`" <> name <> "`"            -- fall back to code span on an illegal name
```

Kind-specific sections:

- Module: a "## Dependencies" section listing `moduleLink` for each `entryModuleRefs`; a
  "## Variables" section summarizing `vars` (name, required, validation) from the
  `DocModuleArtifact`; optionally an "## Exports" list. Keep tables small; the authoritative
  detail lives in the `.dhall` (linked via `resource`).
- Recipe: a "## Composes" section listing `moduleLink` for each composed module
  (`entryModuleRefs`).
- Blueprint: a "## Base modules" section listing `moduleLink` for each base module; a short
  note that it is agent-driven; optionally the first lines of the `prompt` or a "## Reference
  files" list from `files`.
- Prompt: a short summary; optionally `allowedTools` / `launch` info from the `AgentPrompt`.

Only `entryModuleRefs` produce graph edges. A ref with `refResolved == False` should still be
rendered (so the docs show the intended dependency) — but note that an unresolved ref will
become a `DanglingReference` in validation (Step 5), which is the desired signal.

Step 4 — concepts. For each `DocEntry`, build
`OKFDocument (frontmatterFor e) (bodyFor e)`, then `conceptFromDocument cid doc` where `cid`
comes from `conceptIdFor (entryKind e) (entryName e)`. Collect `[Concept]`. If any
`conceptIdFor` is `Left`, collect those as render errors (see `renderDocBundle`'s result).

Step 5 — assemble + validate:

```haskell
renderDocBundle :: DocModel -> ([Concept], [BundleValidationError])
renderDocBundle model =
  let concepts = ...                    -- Step 4
      problems = validateBundle PermissiveConformance concepts
   in (concepts, problems)

writeDocBundle :: FilePath -> DocModel -> IO (Either [BundleValidationError] ())
writeDocBundle outDir model =
  let (concepts, problems) = renderDocBundle model
   in if null problems
        then Right <$> writeBundle outDir concepts
        else pure (Left problems)
```

Note `validateBundle PermissiveConformance` still reports `DanglingReference` and
`DuplicateConceptId` (those are bundle-structural, independent of profile) — so a recipe
referencing a module that is not in the registry is caught here. That is the correctness
guarantee the MasterPlan promises.

(`writeBundle` does not clear the output directory; EP-59's command is responsible for
clearing/creating `outDir` before calling `writeDocBundle` so regeneration is pristine. This
plan's `writeDocBundle` only writes; document that contract in a Haddock comment.)

Step 6 — exports + cabal. Add `Seihou.CLI.Docs.Render` to `seihou-cli-internal`
`exposed-modules`.

Step 7 — tests. Create `seihou-cli/test/Seihou/CLI/Docs/RenderSpec.hs`. Build a small
`DocModel` in memory (you can construct `DocEntry`/`DocArtifact` values directly with minimal
`Module`/`Recipe` records, or call EP-57's `loadDocModel` on EP-57's fixture registry). Assert:

- `renderDocBundle` produces one concept per entry with the expected concept IDs
  (`modules/<name>`, …).
- A module concept's serialized document (`serializeConcept` or `serializeDocument . document`)
  contains `type: SeihouModule`, the title, and the `resource:` line.
- A recipe concept's body contains a resolvable link to each composed module — assert the
  body contains the substring `](/modules/<name>.md)`.
- For a well-formed model, `renderDocBundle`'s `[BundleValidationError]` is empty.
- For a model containing an unresolved module ref, the errors contain a `DanglingReference`.

Add the spec to `seihou-cli/test/Main.hs` and the test stanza `other-modules`.


## Concrete Steps

From the seihou repository root, inside the dev shell:

```bash
nix develop
cabal build all
cabal test seihou-cli-test
```

Expected new test output:

```text
Seihou.CLI.Docs.Render
  renderDocBundle
    emits one concept per entry with the modules/ recipes/ ... id scheme [✔]
    renders resolvable cross-links to composed modules [✔]
    validates clean for a well-formed model [✔]
    reports a DanglingReference for an unresolved module ref [✔]
```

End-to-end spot-check against the real registry (write a bundle, then validate it with the
okf CLI if available):

```bash
cabal repl seihou-cli-internal
```

```haskell
ghci> import Seihou.CLI.Docs.Model
ghci> import Seihou.CLI.Docs.Render
ghci> Right m <- loadDocModel "/Users/shinzui/Keikaku/bokuno/seihou-modules"
ghci> writeDocBundle "/tmp/seihou-okf-demo" m
Right ()
```

```bash
# if the okf CLI is on PATH or via the okf repo:
okf validate /tmp/seihou-okf-demo        # expect: OK: N concepts
okf graph /tmp/seihou-okf-demo --json    # expect edges like haskell-library -> nix-haskell-flake
```


## Validation and Acceptance

Acceptance is behavioral:

1. `cabal test seihou-cli-test` passes the new `RenderSpec`, proving the model renders to
   concepts with the documented ID scheme, frontmatter, and resolvable cross-links.
2. `renderDocBundle` returns no `BundleValidationError`s for a well-formed model and returns a
   `DanglingReference` when a module reference does not resolve — proving referential
   integrity is enforced before writing.
3. The REPL spot-check writes a bundle from the real `seihou-modules` registry and (if the okf
   CLI is available) `okf validate` reports OK and `okf graph` shows the
   `haskell-library → nix-haskell-flake` dependency edge — proving the cross-links round-trip
   through okf's own graph extractor.


## Idempotence and Recovery

`renderDocBundle` is pure and deterministic (no timestamps), so repeated renders of the same
model produce byte-identical concepts; `writeDocBundle` overwrites the per-concept files it
writes. If `okf validate` reports a dangling reference on real data, that is a true defect in
the registry (a dependency naming a missing module) — report it; it is not a bug in this code.
If a concept ID fails to parse (illegal name), surface it as a render error rather than
crashing. No global state; reverting the render module and spec removes the feature cleanly.


## Interfaces and Dependencies

Depends on okf-core (made available by EP-56) and on `Seihou.CLI.Docs.Model` (EP-57). Also
uses `Data.Aeson (Value (..))` for extension-field values and `Data.Text`. No new package
dependencies beyond `okf-core` (added in EP-56) and `aeson` (already a seihou dependency).

Functions that must exist at the end of this plan, in
`seihou-cli/src/Seihou/CLI/Docs/Render.hs`:

```haskell
conceptIdFor   :: DocKind -> Text -> Either Text ConceptId
renderDocBundle :: DocModel -> ([Concept], [BundleValidationError])
writeDocBundle  :: FilePath -> DocModel -> IO (Either [BundleValidationError] ())
```

Relationship to other plans (see the MasterPlan's Integration Points):

- This plan owns integration points 3 (concept-ID scheme + cross-link convention) and 4
  (frontmatter + validation-profile conventions).
- Hard deps: EP-56 (okf-core buildable) and EP-57 (the `DocModel`).
- EP-59 (`docs/plans/59-add-the-seihou-docs-command-with-fixtures-tests-and-user-docs.md`)
  calls `writeDocBundle`/`renderDocBundle` from the command handler and asserts against the
  same concept-ID scheme; keep them in lockstep.
- Shares `seihou-cli/test/Main.hs` and the test stanza `other-modules` with EP-57 and EP-59:
  append the new spec; do not reorder existing ones.
