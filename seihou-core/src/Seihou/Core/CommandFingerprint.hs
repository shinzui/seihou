module Seihou.Core.CommandFingerprint
  ( fingerprintCommand,
  )
where

import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import System.FilePath (normalise)

-- | Compute the stable identity of a rendered module command. Non-command
-- operations have no command fingerprint.
fingerprintCommand :: Operation -> Maybe CommandFingerprint
fingerprintCommand RunCommandOp {command, workDir, moduleName, occurrence} =
  Just . CommandFingerprint . hashContent $
    T.intercalate
      "\n"
      [ "module=" <> moduleName.unModuleName,
        "command=" <> command,
        "work-dir=" <> T.pack (normalise (maybe "." id workDir)),
        "occurrence=" <> T.pack (show occurrence)
      ]
fingerprintCommand _ = Nothing
