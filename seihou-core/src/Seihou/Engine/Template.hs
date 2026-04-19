module Seihou.Engine.Template
  ( renderTemplate,
    renderTemplateText,
    expandConditionals,
    valueToText,
    renderDestPath,
    renderCommand,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Expr (evalExpr, parseExpr)
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

-- | Render a template body supporting both @{{placeholder}}@ substitution
-- and @{{#if}}\/{{#else}}\/{{\/if}}@ conditional blocks with unbounded
-- nesting. Expression syntax inside @{{#if …}}@ is the same grammar used
-- by a step's @when@ clause ('Seihou.Core.Expr.parseExpr').
--
-- Runs in two passes: 'expandConditionals' consumes block tokens and
-- emits plain template text, then 'renderTemplate' performs @{{var}}@
-- substitution on the expanded text.
--
-- Intended for template bodies only. Destination paths and shell
-- commands stay on 'renderDestPath' \/ 'renderCommand'.
renderTemplateText :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderTemplateText template vars =
  case expandConditionals vars template of
    Left errs -> Left errs
    Right expanded -> renderTemplate expanded vars

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

-- | First-pass expander: consume @{{#if}}\/{{#else}}\/{{\/if}}@ block
-- tokens and emit plain template text with only the selected branches
-- retained. Supports arbitrary nesting depth.
--
-- Exported for test access; in production code the recommended entry
-- point is 'renderTemplateText'.
expandConditionals :: Map VarName VarValue -> Text -> Either [PlaceholderError] Text
expandConditionals vars = expandAtTopLevel vars 1

-- | Expand at the top level: produce text until we hit @{{\/if}}@ or
-- @{{#else}}@ (which at top level are orphans). Only the selected
-- branch is expanded; the untaken branch is discarded, so errors
-- inside it do not surface.
expandAtTopLevel :: Map VarName VarValue -> Int -> Text -> Either [PlaceholderError] Text
expandAtTopLevel vars startLine input =
  case splitNextBlock input of
    NoBlockLeft -> Right input
    FoundIf before afterBlockOpen exprText ->
      let beforeLines = T.count "\n" before
          openAt = startLine + beforeLines
       in case parseExpr exprText of
            Left parseErr ->
              Left [MalformedIfExpression exprText openAt parseErr]
            Right expr -> do
              (thenText, elseText, afterBlock, consumedLines) <-
                splitBranches openAt afterBlockOpen
              let selectedRaw =
                    if evalExpr vars expr then thenText else elseText
              selectedExpanded <- expandAtTopLevel vars openAt selectedRaw
              let afterLine = openAt + consumedLines
              rest <- expandAtTopLevel vars afterLine afterBlock
              pure (before <> selectedExpanded <> rest)
    FoundOrphan tok beforeLines ->
      Left [OrphanBlockToken tok (startLine + beforeLines)]

-- | Raw tokenisation result for the top-level scan.
data NextBlock
  = -- | No block tokens in the remaining input.
    NoBlockLeft
  | -- | An @{{#if …}}@ block. @before@ is text preceding the opener;
    -- @after@ is everything after the closing @}}@ of the opener
    -- (i.e. the body plus whatever follows the matching @{{/if}}@);
    -- @expr@ is the raw expression text.
    FoundIf
      { foundBefore :: Text,
        foundAfter :: Text,
        foundExpr :: Text
      }
  | -- | A @{{#else}}@ or @{{/if}}@ encountered before any matching
    -- @{{#if}}@ at the current depth. The 'Int' is the line offset
    -- (0-based) from the start of the scanned region.
    FoundOrphan Text Int

-- | Scan @input@ for the next block token at the outer level (i.e. for
-- the purpose of locating the next @{{#if}}@ opener, or an orphan if
-- one occurs first).
splitNextBlock :: Text -> NextBlock
splitNextBlock input = scan 0 input
  where
    scan :: Int -> Text -> NextBlock
    scan pos t
      | T.null t = NoBlockLeft
      | "{{#if " `T.isPrefixOf` t =
          let before = T.take pos input
              afterOpen = T.drop 6 t -- skip "{{#if "
           in case T.breakOn "}}" afterOpen of
                (_, "") -> NoBlockLeft -- malformed; let higher-level handle
                (exprRaw, rest) ->
                  let expr = T.strip exprRaw
                      afterCloseTag = T.drop 2 rest -- skip "}}"
                   in FoundIf
                        { foundBefore = before,
                          foundAfter = afterCloseTag,
                          foundExpr = expr
                        }
      | "{{/if}}" `T.isPrefixOf` t =
          FoundOrphan "{{/if}}" (lineOffset (T.take pos input))
      | "{{#else}}" `T.isPrefixOf` t =
          FoundOrphan "{{#else}}" (lineOffset (T.take pos input))
      | otherwise =
          let headChar = T.take 1 t
              rest = T.drop 1 t
           in scan (pos + T.length headChar) rest

-- | Given the text immediately after an @{{#if …}}@ opener, find the
-- matching @{{\/if}}@ (honouring nested @{{#if}}@\/@{{\/if}}@ pairs) and
-- split the body at a top-level @{{#else}}@ if one is present.
--
-- Returns @(thenBranch, elseBranch, afterCloseBlock, linesConsumedUpToAndIncludingClose)@.
-- The @openLine@ parameter is the absolute source-line number of the
-- opener, used only when reporting 'UnterminatedIf'.
splitBranches ::
  Int ->
  Text ->
  Either [PlaceholderError] (Text, Text, Text, Int)
splitBranches openLine bodyPlusTail = go 0 0 Nothing bodyPlusTail
  where
    -- depth: how many extra {{#if}} openers we've seen since the outer opener.
    -- accLen: how much of @bodyPlusTail@ we've consumed (character count).
    -- mElseAt: @Just accLen@ at the first top-level {{#else}}, if any.
    go :: Int -> Int -> Maybe Int -> Text -> Either [PlaceholderError] (Text, Text, Text, Int)
    go _ _ _ t
      | T.null t = Left [UnterminatedIf openLine]
    go depth accLen mElseAt t
      | "{{/if}}" `T.isPrefixOf` t && depth == 0 =
          let (thenText, elseText) = case mElseAt of
                Nothing -> (T.take accLen bodyPlusTail, "")
                Just elseAt ->
                  ( T.take elseAt bodyPlusTail,
                    T.take (accLen - elseAt - elseTokenLen) (T.drop (elseAt + elseTokenLen) bodyPlusTail)
                  )
              afterClose = T.drop (accLen + ifCloseLen) bodyPlusTail
              consumedLines = lineOffset (T.take (accLen + ifCloseLen) bodyPlusTail)
           in Right (thenText, elseText, afterClose, consumedLines)
      | "{{/if}}" `T.isPrefixOf` t =
          advance (depth - 1) accLen mElseAt t ifCloseLen
      | "{{#if " `T.isPrefixOf` t =
          advance (depth + 1) accLen mElseAt t ifOpenPrefixLen
      | "{{#else}}" `T.isPrefixOf` t && depth == 0 =
          let newElseAt = case mElseAt of
                Just existing -> Just existing
                Nothing -> Just accLen
           in advance depth accLen newElseAt t elseTokenLen
      | "{{#else}}" `T.isPrefixOf` t =
          advance depth accLen mElseAt t elseTokenLen
      | otherwise =
          advance depth accLen mElseAt t 1

    advance ::
      Int ->
      Int ->
      Maybe Int ->
      Text ->
      Int ->
      Either [PlaceholderError] (Text, Text, Text, Int)
    advance depth accLen mElseAt t n =
      let step = T.take n t
          rest = T.drop n t
       in go depth (accLen + T.length step) mElseAt rest

    ifOpenPrefixLen = T.length ("{{#if " :: Text)
    ifCloseLen = T.length ("{{/if}}" :: Text)
    elseTokenLen = T.length ("{{#else}}" :: Text)

-- | Number of newlines in @t@; used to compute line offsets from
-- byte positions.
lineOffset :: Text -> Int
lineOffset = T.count "\n"
