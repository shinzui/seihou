module Seihou.Core.CommandFingerprint
  ( fingerprintCommand,
    checkoutCommandsFromOperations,
    checkoutCommandOperation,
    isCheckoutCommand,
  )
where

import Control.Lens ((^.))
import Data.Generics.Labels ()
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
      [ "module=" <> moduleName ^. #unModuleName,
        "command=" <> command,
        "work-dir=" <> T.pack (normalise (maybe "." id workDir)),
        "occurrence=" <> T.pack (show occurrence)
      ]
fingerprintCommand _ = Nothing

-- | Capture declarations from the complete compiled plan, even when execution is disabled.
checkoutCommandsFromOperations :: [Operation] -> [CheckoutCommand]
checkoutCommandsFromOperations operations =
  [ CheckoutCommand moduleName occurrence command workDir
  | RunCommandOp {moduleName, occurrence, command, workDir, lifecycle = CheckoutCommandLifecycle} <- operations
  ]

checkoutCommandOperation :: CheckoutCommand -> Operation
checkoutCommandOperation CheckoutCommand {moduleName, occurrence, command, workDir} =
  RunCommandOp {moduleName, occurrence, command, workDir, lifecycle = CheckoutCommandLifecycle}

isCheckoutCommand :: Operation -> Bool
isCheckoutCommand RunCommandOp {lifecycle = CheckoutCommandLifecycle} = True
isCheckoutCommand _ = False
