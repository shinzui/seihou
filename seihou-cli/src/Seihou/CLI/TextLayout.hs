-- | Fixed-width text layout shared by the CLI's summary views.
--
-- Summary commands (@seihou status@, @seihou list@) render unbounded free text
-- at a fixed width rather than the terminal's width, so the same data always
-- renders the same way and tests can assert on it (see
-- docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md).
-- This module is the single place that decides how such text is cut or
-- wrapped; each caller keeps its own width constant beside its use.
module Seihou.CLI.TextLayout
  ( truncateForSummary,
    wrapParagraphs,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

-- | Collapse every run of internal whitespace to a single space and cut the
-- result to @width@ characters, marking a cut with a trailing ellipsis.
--
-- @seihou status@ is a scannable summary, and the manifest is the record (see
-- docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md). Two
-- values the summary renders are unbounded free text kept in full in
-- @.seihou/manifest.json@ — a migration receipt's not-applicable reason and a
-- blueprint's stored user prompt — and this is the single place that decides how
-- much of such a value the summary shows, so the two cannot drift apart.
--
-- The result is never longer than @width@: a cut keeps at most @width - 1@
-- characters and spends the last on the ellipsis. A cut that lands mid-gap has
-- its trailing space stripped, so the output reads @\"... already…\"@ rather than
-- @\"... already …\"@.
truncateForSummary :: Int -> Text -> Text
truncateForSummary width text
  | T.length oneLine <= width = oneLine
  | otherwise = T.stripEnd (T.take (width - 1) oneLine) <> "…"
  where
    oneLine = T.unwords (T.words text)

-- | Greedily word-wrap text to lines of at most @width@ characters.
--
-- The input is split into paragraphs at blank lines (lines that are empty
-- after stripping). Whitespace inside a paragraph is collapsed exactly as
-- 'truncateForSummary' collapses it, then the paragraph is filled word by
-- word. Paragraphs are separated in the output by one empty line.
--
-- A single word longer than @width@ is placed on a line of its own, unbroken:
-- cutting a URL or a path in two is worse than one over-long line. Empty or
-- all-whitespace input yields @[]@.
wrapParagraphs :: Int -> Text -> [Text]
wrapParagraphs width text =
  joinParagraphs (map (fill . concatMap T.words) (paragraphs (T.lines text)))
  where
    joinParagraphs :: [[Text]] -> [Text]
    joinParagraphs = go . filter (not . null)
      where
        go [] = []
        go [p] = p
        go (p : ps) = p <> [""] <> go ps

    -- Group consecutive non-blank lines; blank lines separate groups.
    paragraphs :: [Text] -> [[Text]]
    paragraphs ls = case dropWhile isBlank ls of
      [] -> []
      rest ->
        let (para, after) = break isBlank rest
         in para : paragraphs after

    isBlank = T.null . T.strip

    fill :: [Text] -> [Text]
    fill [] = []
    fill (w : ws) = go w ws
      where
        go current [] = [current]
        go current (next : more)
          | T.length current + 1 + T.length next <= width = go (current <> " " <> next) more
          | otherwise = current : go next more
