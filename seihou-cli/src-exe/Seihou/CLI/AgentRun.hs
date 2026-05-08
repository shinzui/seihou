-- | Agent runner for blueprints. See EP-31
-- (docs/plans/31-blueprint-agent-runner.md).
module Seihou.CLI.AgentRun
  ( handleAgentRun,
  )
where

import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (BlueprintRunOpts (..))
import Seihou.Prelude
import System.Exit (exitFailure)

handleAgentRun :: Bool -> BlueprintRunOpts -> IO ()
handleAgentRun _debug _opts = do
  TIO.putStrLn "[error] 'seihou agent run' is not yet implemented (EP-31 milestone 1 stub)."
  exitFailure
