module Seihou.Engine.Template
  ( renderTemplate,
    valueToText,
    renderDestPath,
    renderCommand,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Prelude

-- | Convert a variable value to its text representation for template output.
valueToText :: VarValue -> Text
valueToText (VText t) = t
valueToText (VBool True) = "true"
valueToText (VBool False) = "false"
valueToText (VInt n) = T.pack (show n)
valueToText (VList vs) = T.intercalate "," (map valueToText vs)

-- | Render a template by substituting @{{placeholder}}@ occurrences.
-- The escape sequence @\\{{@ produces a literal @{{@ in the output.
-- Returns either a list of errors or the rendered text.
renderTemplate :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderTemplate template vars =
  let lns = T.splitOn "\n" template
      results = zipWith (renderLine vars) [1 ..] lns
      (allErrors, renderedLines) = partitionResults results
   in if null allErrors
        then Right (T.intercalate "\n" renderedLines)
        else Left (concat allErrors)

-- | Render destination path placeholders (same substitution logic).
renderDestPath :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderDestPath = renderTemplate

-- | Render placeholders in a shell command string.
-- Same substitution as 'renderTemplate' but named for clarity at call sites.
renderCommand :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderCommand = renderTemplate

-- | Render a single line, returning errors or the rendered text.
renderLine :: Map VarName VarValue -> Int -> Text -> Either [PlaceholderError] Text
renderLine vars lineNum line =
  case scanLine vars lineNum line of
    ([], rendered) -> Right rendered
    (errs, _) -> Left errs

-- | Scan a line for placeholders and substitute them.
-- Returns accumulated errors and the rendered text.
scanLine :: Map VarName VarValue -> Int -> Text -> ([PlaceholderError], Text)
scanLine vars lineNum = go
  where
    go :: Text -> ([PlaceholderError], Text)
    go txt
      | T.null txt = ([], "")
      | "\\{{" `T.isPrefixOf` txt =
          -- Escape sequence: produce literal {{
          let (errs, rest) = go (T.drop 3 txt)
           in (errs, "{{" <> rest)
      | "{{" `T.isPrefixOf` txt =
          -- Placeholder: find the closing }}
          let after = T.drop 2 txt
           in case T.breakOn "}}" after of
                (_, "") ->
                  -- No closing }}, treat as malformed
                  let raw = T.take 20 txt
                      (errs, rest) = go (T.drop 2 txt)
                   in (MalformedPlaceholder raw lineNum : errs, rest)
                (varNameText, remaining) ->
                  let trimmed = T.strip varNameText
                      name = VarName trimmed
                      restAfter = T.drop 2 remaining -- skip the }}
                   in case Map.lookup name vars of
                        Just val ->
                          let (errs, rest) = go restAfter
                           in (errs, valueToText val <> rest)
                        Nothing ->
                          let (errs, rest) = go restAfter
                           in (UnresolvedPlaceholder name lineNum : errs, rest)
      | otherwise =
          -- Find the next {{ or \{{ occurrence
          case findNextPlaceholder txt of
            Nothing -> ([], txt)
            Just idx ->
              let (before, after) = T.splitAt idx txt
                  (errs, rest) = go after
               in (errs, before <> rest)

-- | Find the index of the next placeholder start (@{{@ or @\\{{@).
findNextPlaceholder :: Text -> Maybe Int
findNextPlaceholder txt = go 0 txt
  where
    go :: Int -> Text -> Maybe Int
    go idx t
      | T.null t = Nothing
      | "\\{{" `T.isPrefixOf` t = Just idx
      | "{{" `T.isPrefixOf` t = Just idx
      | otherwise = go (idx + 1) (T.drop 1 t)

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr step ([], [])
  where
    step (Left e) (errs, oks) = (e : errs, oks)
    step (Right a) (errs, oks) = (errs, a : oks)
