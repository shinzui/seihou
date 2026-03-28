module Seihou.CLI.CommitMessage
  ( generateCommitMessage,
    stripCodeFence,
  )
where

import Control.Exception (SomeException, try)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Types (ModuleName (..))
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.IO (hClose)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, waitForProcess)

-- | Generate a commit message using Claude Code CLI.
-- Takes the module names applied and the staged diff.
-- Returns the AI-generated message, or a fallback if claude is unavailable.
generateCommitMessage :: [ModuleName] -> T.Text -> IO T.Text
generateCommitMessage modNames diffText = do
  claudePath <- findExecutable "claude"
  case claudePath of
    Nothing -> pure (fallbackMessage modNames)
    Just _ -> do
      result <- callClaude modNames diffText
      case result of
        Nothing -> pure (fallbackMessage modNames)
        Just msg
          | T.null (T.strip msg) -> pure (fallbackMessage modNames)
          | otherwise -> pure (stripCodeFence (T.strip msg))

callClaude :: [ModuleName] -> T.Text -> IO (Maybe T.Text)
callClaude modNames diffText = do
  let prompt = buildPrompt modNames diffText
      cp =
        (proc "claude" ["-p", T.unpack prompt])
          { std_out = CreatePipe,
            std_err = CreatePipe,
            std_in = NoStream
          }
  result <- try @SomeException $ do
    (_, Just hOut, Just hErr, ph) <- createProcess cp
    output <- TIO.hGetContents hOut
    _ <- TIO.hGetContents hErr
    exitCode <- waitForProcess ph
    hClose hOut
    hClose hErr
    pure (exitCode, output)
  case result of
    Left _ -> pure Nothing
    Right (ExitSuccess, output) -> pure (Just output)
    Right (ExitFailure _, _) -> pure Nothing

buildPrompt :: [ModuleName] -> T.Text -> T.Text
buildPrompt modNames diffText =
  T.unlines
    [ "Generate a concise git commit message for seihou scaffolding changes.",
      "",
      "Modules applied: " <> moduleList,
      "",
      "Staged changes:",
      diffText,
      "",
      "Rules:",
      "- Use conventional commit style (e.g., \"feat: ...\", \"chore: ...\")",
      "- Keep the subject line under 72 characters",
      "- Mention which seihou module(s) were applied",
      "- Output ONLY the commit message, nothing else",
      "- Do not wrap the output in backticks or code fences"
    ]
  where
    moduleList = T.intercalate ", " (map (.unModuleName) modNames)

-- | Strip markdown code-fence wrapping (``` ... ```) from text.
-- Handles optional language tags (e.g., ```text).
stripCodeFence :: T.Text -> T.Text
stripCodeFence txt =
  let ls = T.lines txt
      nonEmpty = filter (not . T.null . T.strip) ls
   in case nonEmpty of
        (first : rest)
          | "```" `T.isPrefixOf` first,
            not (null rest),
            T.strip (last rest) == "```" ->
              let -- Drop the opening fence line and closing fence line
                  body = drop 1 (take (length ls - 1) ls)
               in T.strip (T.unlines body)
        _ -> txt

fallbackMessage :: [ModuleName] -> T.Text
fallbackMessage [] = "seihou: apply modules"
fallbackMessage [m] = "seihou: apply module " <> m.unModuleName
fallbackMessage ms = "seihou: apply modules " <> T.intercalate ", " (map (.unModuleName) ms)
