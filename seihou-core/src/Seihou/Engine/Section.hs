module Seihou.Engine.Section
  ( SectionMarker (..),
    renderSectionOpen,
    renderSectionClose,
    wrapInSection,
    removeSection,
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
  marker.sectionPrefix <> " --- seihou:" <> marker.sectionModule.unModuleName <> " ---\n"

-- | Render a closing section marker line.
-- Result: @"# --- /seihou:haskell-base ---\\n"@
renderSectionClose :: SectionMarker -> Text
renderSectionClose marker =
  marker.sectionPrefix <> " --- /seihou:" <> marker.sectionModule.unModuleName <> " ---\n"

-- | Wrap content in section markers.
wrapInSection :: SectionMarker -> Text -> Text
wrapInSection marker content =
  renderSectionOpen marker <> content <> ensureTrailingNewline content <> renderSectionClose marker
  where
    ensureTrailingNewline t
      | T.null t = ""
      | T.last t == '\n' = ""
      | otherwise = "\n"

-- | Remove a module's section from file content.
--
-- Strips all lines between the opening and closing section markers (inclusive)
-- for the given module name. The comment prefix (e.g., @"#"@) determines
-- the marker format. If no matching markers are found, the content is returned
-- unchanged. Cleans up resulting double blank lines.
removeSection :: ModuleName -> Text -> Text -> Text
removeSection modName prefix content =
  let marker = SectionMarker {sectionPrefix = prefix, sectionModule = modName}
      openTag = T.stripEnd (renderSectionOpen marker)
      closeTag = T.stripEnd (renderSectionClose marker)
      ls = T.lines content
      filtered = dropSection openTag closeTag ls
      cleaned = collapseBlankLines filtered
   in if null cleaned
        then ""
        else T.unlines cleaned
  where
    dropSection _ _ [] = []
    dropSection open close (l : rest)
      | T.stripEnd l == open =
          -- Skip until we find the close tag
          case dropWhile (\x -> T.stripEnd x /= close) rest of
            [] -> [] -- Close tag not found, drop remaining
            (_ : after) -> dropSection open close after
      | otherwise = l : dropSection open close rest

    collapseBlankLines [] = []
    collapseBlankLines [x] = [x]
    collapseBlankLines (x : y : rest)
      | T.null (T.strip x) && T.null (T.strip y) = collapseBlankLines (y : rest)
      | otherwise = x : collapseBlankLines (y : rest)

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
