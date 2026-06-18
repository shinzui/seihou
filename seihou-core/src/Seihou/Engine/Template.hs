module Seihou.Engine.Template
  ( renderTemplate,
    renderTemplateText,
    expandConditionals,
    extractIfExprs,
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

-- | Extract the raw expression text from every @{{#if …}}@ opener in a
-- template body, in document order. Used by authoring-time lint to scan
-- template conditionals without expanding them; each returned string is
-- intended to be fed to 'parseExpr'. Nesting is irrelevant here — every
-- opener is reported, regardless of depth. A malformed (unterminated)
-- opener stops the scan, mirroring 'splitNextBlock'.
extractIfExprs :: Text -> [Text]
extractIfExprs = go
  where
    go t = case T.breakOn "{{#if " t of
      (_, "") -> []
      (_, match) ->
        let afterOpen = T.drop 6 match -- skip "{{#if "
         in case T.breakOn "}}" afterOpen of
              (_, "") -> [] -- unterminated opener; stop
              (exprRaw, rest) -> T.strip exprRaw : go (T.drop 2 rest)

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
--
-- When a block tag is the only non-whitespace on its line (a
-- \"standalone block\" in the Mustache/Handlebars sense), the
-- surrounding indentation and the line\'s terminating newline are
-- consumed as part of the tag so the expanded text does not leave a
-- blank line behind. This is what lets module authors format a
-- template with tags on their own lines and still get clean output.
expandAtTopLevel :: Map VarName VarValue -> Int -> Text -> Either [PlaceholderError] Text
expandAtTopLevel vars startLine input =
  case splitNextBlock input of
    NoBlockLeft -> Right input
    FoundIf before0 afterBlockOpen0 exprText ->
      let beforeLines = T.count "\n" before0
          openAt = startLine + beforeLines
          (before, afterBlockOpen, openerSkipped) =
            trimStandaloneAround before0 afterBlockOpen0
          bodyStart = openAt + openerSkipped
       in case parseExpr exprText of
            Left parseErr ->
              Left [MalformedIfExpression exprText openAt parseErr]
            Right expr -> do
              (thenText, elseText, afterBlock, consumedLines, closerSkipped) <-
                splitBranches openAt afterBlockOpen
              let selectedRaw =
                    if evalExpr vars expr then thenText else elseText
              selectedExpanded <- expandAtTopLevel vars bodyStart selectedRaw
              let afterLine = openAt + openerSkipped + consumedLines + closerSkipped
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
-- Returns @(thenBranch, elseBranch, afterCloseBlock, linesConsumedUpToAndIncludingClose, closerSkipped)@.
-- The @openLine@ parameter is the absolute source-line number of the
-- opener, used only when reporting 'UnterminatedIf'.
--
-- Standalone-block trim is applied to the top-level @{{#else}}@ (if
-- present) and to the matching @{{\/if}}@. @closerSkipped@ is 1 when
-- the closer\'s trailing newline was absorbed by standalone trim and
-- 0 otherwise; callers add it to their own post-block line counter
-- so chained blocks at the same level report accurate line numbers.
splitBranches ::
  Int ->
  Text ->
  Either [PlaceholderError] (Text, Text, Text, Int, Int)
splitBranches openLine bodyPlusTail = go 0 0 Nothing bodyPlusTail
  where
    -- depth: how many extra {{#if}} openers we've seen since the outer opener.
    -- accLen: how much of @bodyPlusTail@ we've consumed (character count).
    -- mElseAt: @Just accLen@ at the first top-level {{#else}}, if any.
    go :: Int -> Int -> Maybe Int -> Text -> Either [PlaceholderError] (Text, Text, Text, Int, Int)
    go _ _ _ t
      | T.null t = Left [UnterminatedIf openLine]
    go depth accLen mElseAt t
      | "{{/if}}" `T.isPrefixOf` t && depth == 0 =
          let (thenText0, elseText0) = case mElseAt of
                Nothing -> (T.take accLen bodyPlusTail, "")
                Just elseAt ->
                  ( T.take elseAt bodyPlusTail,
                    T.take (accLen - elseAt - elseTokenLen) (T.drop (elseAt + elseTokenLen) bodyPlusTail)
                  )
              afterClose0 = T.drop (accLen + ifCloseLen) bodyPlusTail
              consumedLines = lineOffset (T.take (accLen + ifCloseLen) bodyPlusTail)
              -- Trim standalone closer: the line's whitespace-before
              -- lives at the tail of whichever branch ended at it
              -- (elseText0 if present, otherwise thenText0), and the
              -- whitespace+newline-after lives at the head of afterClose0.
              (thenText, elseText, afterClose, closerSkipped) =
                case mElseAt of
                  Nothing ->
                    let (tt, ac, n) = trimStandaloneAround thenText0 afterClose0
                     in (tt, "", ac, n)
                  Just _ ->
                    -- First try to trim standalone {{#else}} between
                    -- thenText and elseText, then trim the closer.
                    let (tt, et0, _elseSkipped) = trimStandaloneAround thenText0 elseText0
                        (et, ac, n) = trimStandaloneAround et0 afterClose0
                     in (tt, et, ac, n)
           in Right (thenText, elseText, afterClose, consumedLines, closerSkipped)
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
      Either [PlaceholderError] (Text, Text, Text, Int, Int)
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

-- | Standalone-block trim: if the tag sitting between @before@ and
-- @after@ is the only non-whitespace content on its line, strip the
-- surrounding indentation and the trailing newline. Returns the
-- trimmed pair and the number of newlines the trim absorbed (0 or 1)
-- so the caller can keep source-line tracking accurate.
--
-- A tag qualifies as standalone iff:
--
-- * the tail of @before@ since the last newline (or since the start
--   of @before@ when there is no prior newline) consists only of
--   spaces and tabs, AND
-- * the head of @after@ up to and including the next newline consists
--   only of spaces and tabs followed by a newline — OR @after@ ends
--   before any newline appears and contains only spaces and tabs
--   (i.e. EOF with trailing whitespace).
trimStandaloneAround :: Text -> Text -> (Text, Text, Int)
trimStandaloneAround before after =
  case (stripTailWhitespace before, stripHeadWhitespaceNewline after) of
    (Just b', Just (a', consumed)) -> (b', a', consumed)
    _ -> (before, after, 0)

-- | Strip trailing spaces and tabs at the end of @t@ if the suffix
-- since the last newline (or from the start of @t@) contains only
-- whitespace. Returns 'Nothing' otherwise, so the caller can fall
-- back to the untrimmed text.
stripTailWhitespace :: Text -> Maybe Text
stripTailWhitespace t =
  let (beforeLastLine, lastLine) = T.breakOnEnd "\n" t
   in if T.all isSpaceOrTab lastLine
        then Just beforeLastLine
        else Nothing

-- | Strip leading spaces and tabs at the start of @t@ followed by a
-- single newline. Returns the remainder paired with the number of
-- newlines consumed (always 0 or 1). EOF after trailing whitespace
-- counts as a standalone match with 0 newlines consumed.
stripHeadWhitespaceNewline :: Text -> Maybe (Text, Int)
stripHeadWhitespaceNewline t =
  let (_ws, rest) = T.span isSpaceOrTab t
   in if T.null rest
        then Just ("", 0)
        else case T.uncons rest of
          Just ('\n', after) -> Just (after, 1)
          _ -> Nothing

isSpaceOrTab :: Char -> Bool
isSpaceOrTab c = c == ' ' || c == '\t'
