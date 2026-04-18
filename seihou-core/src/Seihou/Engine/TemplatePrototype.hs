-- | Experimental "Prototype C" template renderer for the
-- Dhall-as-templating evaluation in
-- @docs/plans/8-evaluate-dhall-as-templating-language.md@.
--
-- Extends the production placeholder engine in
-- 'Seihou.Engine.Template' with inline conditional blocks:
--
-- >  {{#if <expr>}}...{{/if}}
-- >  {{#if <expr>}}...{{#else}}...{{/if}}
--
-- where @<expr>@ is the expression language in 'Seihou.Core.Expr'
-- (supports @IsSet@, @Eq@, @&&@, @||@, @!@, @true@, @false@, and
-- parentheses).
--
-- The prototype supports at most one level of nesting. Deeper
-- nesting, richer expressions, or richer block types are explicitly
-- out of scope; this module exists to measure the cost of the
-- simplest alternative that plausibly eliminates the split-flake
-- duplication.
--
-- This module is reachable only from tests — it does not touch
-- 'Seihou.Engine.Template', 'Seihou.Engine.Plan', or the 'Strategy'
-- enum.
module Seihou.Engine.TemplatePrototype
  ( renderTemplatePrototype,
    PrototypeError (..),
  )
where

import Data.Text qualified as T
import Seihou.Core.Expr (evalExpr, parseExpr)
import Seihou.Core.Types
import Seihou.Engine.Template (renderTemplate)
import Seihou.Prelude

-- | Errors that can arise during prototype rendering.
-- Kept separate from 'PlaceholderError' so production code is not
-- coupled to this experimental surface.
data PrototypeError
  = -- | @{{#if …}}@ with no matching @{{/if}}@; line is the opener.
    UnterminatedIf Int
  | -- | @{{/if}}@ or @{{#else}}@ encountered outside any @{{#if}}@.
    OrphanBlockToken Text Int
  | -- | The expression inside a @{{#if …}}@ failed to parse.
    MalformedIfExpression Text Int Text
  | -- | Nesting depth exceeded the prototype's 1-level limit.
    NestingTooDeep Int
  | -- | Errors from the inner placeholder pass of a rendered branch.
    BranchPlaceholderErrors [PlaceholderError]
  deriving stock (Eq, Show)

-- | Render a template source extended with @{{#if}}/{{#else}}/{{/if}}@
-- blocks. The prototype first expands conditional blocks, then runs
-- the ordinary 'renderTemplate' over the resulting text so that
-- @{{var}}@ substitution behaviour is unchanged.
renderTemplatePrototype ::
  Text ->
  Map VarName VarValue ->
  Either [PrototypeError] Text
renderTemplatePrototype template vars =
  case expandConditionals vars template of
    Left errs -> Left errs
    Right expanded ->
      case renderTemplate expanded vars of
        Left placeholderErrs -> Left [BranchPlaceholderErrors placeholderErrs]
        Right t -> Right t

-- | First-pass: find top-level @{{#if …}}@ blocks and replace them
-- with the text of the selected branch (or empty if no branch is
-- selected). The surviving text is handed to 'renderTemplate' by the
-- caller for @{{var}}@ expansion.
expandConditionals :: Map VarName VarValue -> Text -> Either [PrototypeError] Text
expandConditionals vars = go 0 1
  where
    -- depth tracks the current nesting level so we can reject depth > 1.
    go :: Int -> Int -> Text -> Either [PrototypeError] Text
    go depth startLine input =
      case splitNextBlock input of
        NoBlockLeft ->
          -- No more block tokens; but any stray {{/if}} or {{#else}} beyond
          -- this point is orphaned.
          case findOrphan startLine input of
            Nothing -> Right input
            Just err -> Left [err]
        FoundIf before afterBlockStart openLine exprText ->
          let consumedLines = T.count "\n" before
              openAt = startLine + consumedLines
              branchStart = openAt
           in if depth >= 1
                then Left [NestingTooDeep openAt]
                else case parseExpr exprText of
                  Left parseErr ->
                    Left [MalformedIfExpression exprText openAt parseErr]
                  Right expr -> do
                    (thenText, elseText, afterText, afterLine) <-
                      splitThenElse branchStart afterBlockStart openLine
                    thenExpanded <- go (depth + 1) branchStart thenText
                    elseExpanded <- go (depth + 1) branchStart elseText
                    let selected =
                          if evalExpr vars expr
                            then thenExpanded
                            else elseExpanded
                    rest <- go depth afterLine afterText
                    pure (before <> selected <> rest)
        FoundOrphan tok orphanLine ->
          Left [OrphanBlockToken tok (startLine + orphanLine)]

-- | Find any stray closing tokens in a conditional-free piece of
-- text. Used only at the top-level.
findOrphan :: Int -> Text -> Maybe PrototypeError
findOrphan startLine input =
  case splitNextBlock input of
    FoundIf {} ->
      -- Should not reach here in practice because expandConditionals
      -- consumed every {{#if}} it saw.
      Nothing
    FoundOrphan tok orphanLine ->
      Just (OrphanBlockToken tok (startLine + orphanLine))
    NoBlockLeft -> Nothing

-- | Raw tokenisation result.
data NextBlock
  = -- | No block tokens in the remaining input.
    NoBlockLeft
  | -- | An @{{#if …}}@ block. @before@ is text preceding the opener;
    -- @after@ is everything after the closing @}}@ of the opener
    -- (i.e. the body plus whatever follows the matching @{{/if}}@);
    -- @openLine@ is the line offset of the opener from the start of
    -- the input; @expr@ is the raw expression text.
    FoundIf
      { foundBefore :: Text,
        foundAfter :: Text,
        foundOpenLine :: Int,
        foundExpr :: Text
      }
  | -- | A @{{#else}}@ or @{{/if}}@ encountered before any matching
    -- @{{#if}}@ at the current depth.
    FoundOrphan Text Int

-- | Scan @input@ for the next block token.
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
                      openLine = lineOffset (T.take pos input)
                   in FoundIf
                        { foundBefore = before,
                          foundAfter = afterCloseTag,
                          foundOpenLine = openLine,
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

-- | Split the body that follows an @{{#if …}}@ opener into
-- (then-branch, else-branch, tail-after-{{/if}}, line offset of tail).
-- Supports one level of nesting: a nested @{{#if}}@ is not consumed
-- here; it is detected by 'expandConditionals' and rejected via
-- 'NestingTooDeep'.
splitThenElse ::
  Int ->
  Text ->
  Int ->
  Either [PrototypeError] (Text, Text, Text, Int)
splitThenElse openLine bodyPlusTail _openSourceLine =
  -- Find the matching {{/if}} at the same nesting level. Because the
  -- prototype caps nesting at 1, any {{#if}} encountered inside the
  -- body is already a depth-2 error; but we still have to skip its
  -- matching {{/if}} so the outer close token is the right one.
  go 0 0 bodyPlusTail
  where
    go :: Int -> Int -> Text -> Either [PrototypeError] (Text, Text, Text, Int)
    go _ _ t
      | T.null t = Left [UnterminatedIf openLine]
    go depth accLen t
      | "{{/if}}" `T.isPrefixOf` t && depth == 0 =
          let consumed = T.take accLen bodyPlusTail
              tailText = T.drop 7 t
              (thenText, elseText) = splitElse consumed
              tailLineOffset = openLine + lineOffset (T.take (accLen + 7) bodyPlusTail)
           in Right (thenText, elseText, tailText, tailLineOffset)
      | "{{/if}}" `T.isPrefixOf` t =
          advance (depth - 1) accLen t 7
      | "{{#if " `T.isPrefixOf` t =
          advance (depth + 1) accLen t 6
      | "{{#else}}" `T.isPrefixOf` t =
          advance depth accLen t 9
      | otherwise =
          advance depth accLen t 1

    advance :: Int -> Int -> Text -> Int -> Either [PrototypeError] (Text, Text, Text, Int)
    advance depth accLen t n =
      let step = T.take n t
          rest = T.drop n t
       in go depth (accLen + T.length step) rest

-- | Split a body on @{{#else}}@ at the current nesting level. If the
-- token is absent the whole body is the then-branch and the else
-- branch is empty.
splitElse :: Text -> (Text, Text)
splitElse body = case T.breakOn "{{#else}}" body of
  (thenPart, rest)
    | T.null rest -> (body, "")
    | otherwise -> (thenPart, T.drop 9 rest)

-- | Number of newlines in @t@; used to compute line offsets from
-- byte positions.
lineOffset :: Text -> Int
lineOffset = T.count "\n"
