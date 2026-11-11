-- | The judgement gate for Seihou's own automatic commits (@seihou run
-- --commit@, @seihou update --commit@, @seihou migrate --commit@).
--
-- The order is the contract: the caller stages its files; every active
-- judgement then runs on everything Git will commit, including unrelated
-- pre-staged files; only after a pass is the commit message produced, which
-- may send the staged diff to an AI; and immediately before @git commit@ the
-- index identity is compared with the one that was approved, and reviewed
-- again if it changed. Nothing is unstaged or rolled back on a block.
--
-- No approval outlives this process. The ordinary pre-commit hook still runs
-- its own check on the final index, so a commit through the hook is reviewed
-- twice; that is the price of not trusting a cross-process receipt.
module Seihou.CLI.Judgement.CommitGate
  ( CommitBlocked (..),
    gatedCommit,
    renderBlocked,
  )
where

import Data.Generics.Labels ()
import Seihou.CLI.Judgement.Check
import Seihou.CLI.Judgement.Evidence (captureStaged, gitBytes)
import Seihou.Core.Judgement (defaultCoverageLimits)
import Seihou.Prelude

data CommitBlocked
  = -- | A judgement blocked, needs review or failed; the exit code and report.
    CommitBlocked !Int !Text
  | -- | The commit itself failed after the gate passed.
    CommitFailed !Text
  deriving stock (Eq, Show, Generic)

-- | The message for a blocked automatic commit.
renderBlocked :: CommitBlocked -> Text
renderBlocked = \case
  CommitBlocked _ report ->
    report
      <> "Changes applied; commit blocked. The generated changes remain in the working tree and staged.\n"
      <> "Fix or confirm them, then run seihou check and commit with git commit.\n"
  CommitFailed err -> "git commit failed: " <> err <> "\n"

-- | Gate, then produce the message, then commit.
gatedCommit :: FilePath -> IO Text -> (Text -> IO (Either Text ())) -> IO (Either CommitBlocked ())
gatedCommit root mkMessage commit =
  loadActiveJudgements root >>= \case
    Left err -> pure (Left (CommitBlocked 1 (err <> "\n")))
    Right [] -> mkMessage >>= fmap (first CommitFailed) . commit
    Right active -> do
      services <- productionServices root
      let gate = do
            before <- identity
            out <- runCheck services active (CheckRequest Nothing Nothing False False)
            pure (out, before)
          approved (out, ident) = out ^. #exitCode == 0 && maybe False (const True) ident
      first' <- gate
      if not (approved first')
        then pure (Left (CommitBlocked (nonzero (fst first' ^. #exitCode)) (fst first' ^. #output)))
        else do
          message <- mkMessage
          now <- identity
          final <-
            if now == snd first'
              then pure first'
              else gate
          if not (approved final)
            then pure (Left (CommitBlocked (nonzero (fst final ^. #exitCode)) ("The staged changes changed during review; they were reviewed again.\n" <> fst final ^. #output)))
            else first CommitFailed <$> commit message
  where
    identity = either (const Nothing) (Just . (^. #identity)) <$> captureStaged defaultCoverageLimits (gitBytes root)
    nonzero c = if c == 0 then 1 else c
