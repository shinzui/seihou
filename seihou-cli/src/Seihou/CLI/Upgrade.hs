module Seihou.CLI.Upgrade
  ( handleUpgrade,
  )
where

import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (UpgradeOpts (..))
import Seihou.Prelude

handleUpgrade :: UpgradeOpts -> IO ()
handleUpgrade _uopts = do
  TIO.putStrLn "Not yet implemented."
