module Seihou.Engine.Section
  ( SectionMarker (..),
    renderSectionOpen,
    renderSectionClose,
    wrapInSection,
    applyTextPatch,
  )
where

import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Prelude

-- | A section marker identifies content contributed by a module.
data SectionMarker = SectionMarker
  { sectionPrefix :: Text,
    sectionModule :: ModuleName
  }
  deriving stock (Eq, Show)

-- | Render an opening section marker line.
-- Result: @"# --- seihou:haskell-base ---\\n"@
renderSectionOpen :: SectionMarker -> Text
renderSectionOpen marker =
  sectionPrefix marker <> " --- seihou:" <> unModuleName (sectionModule marker) <> " ---\n"

-- | Render a closing section marker line.
-- Result: @"# --- /seihou:haskell-base ---\\n"@
renderSectionClose :: SectionMarker -> Text
renderSectionClose marker =
  sectionPrefix marker <> " --- /seihou:" <> unModuleName (sectionModule marker) <> " ---\n"

-- | Wrap content in section markers.
wrapInSection :: SectionMarker -> Text -> Text
wrapInSection marker content =
  renderSectionOpen marker <> content <> ensureTrailingNewline content <> renderSectionClose marker
  where
    ensureTrailingNewline t
      | T.null t = ""
      | T.last t == '\n' = ""
      | otherwise = "\n"

-- | Apply a patch operation to existing content.
--
-- @applyTextPatch patchOp moduleName commentPrefix existingContent newContent@
--
-- Returns the merged content or an error.
applyTextPatch :: PatchOp -> ModuleName -> Text -> Text -> Text -> Either Text Text
applyTextPatch AppendFile _ _ existing new =
  Right (ensureTrailingNewline existing <> new)
applyTextPatch PrependFile _ _ existing new =
  Right (ensureTrailingNewline new <> existing)
applyTextPatch AppendSection modName prefix existing new =
  let marker = SectionMarker {sectionPrefix = prefix, sectionModule = modName}
   in Right (ensureTrailingNewline existing <> wrapInSection marker new)

-- | Ensure text ends with a newline. Returns the text unchanged if it already
-- ends with one, or with an appended newline if not. Returns empty text unchanged.
ensureTrailingNewline :: Text -> Text
ensureTrailingNewline t
  | T.null t = t
  | T.last t == '\n' = t
  | otherwise = t <> "\n"
