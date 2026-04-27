module Seihou.CLI.Completions
  ( handleCompletionsCommand,
  )
where

import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (CompletionsCommand (..))
import Seihou.CLI.Completions.Bash (generateBashCompletion)
import Seihou.CLI.Completions.Fish (generateFishCompletion)
import Seihou.CLI.Completions.Zsh (generateZshCompletion)

handleCompletionsCommand :: CompletionsCommand -> IO ()
handleCompletionsCommand = \case
  CompletionsBash -> TIO.putStrLn generateBashCompletion
  CompletionsZsh -> TIO.putStrLn generateZshCompletion
  CompletionsFish -> TIO.putStrLn generateFishCompletion
