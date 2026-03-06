module Seihou.Effect.Console
  ( Console (..),
    putText,
    putError,
    getLine,
    confirm,
    isInteractive,
  )
where

import Seihou.Prelude
import Prelude hiding (getLine)

data Console :: Effect where
  PutText :: Text -> Console m ()
  PutError :: Text -> Console m ()
  GetLine :: Console m Text
  Confirm :: Text -> Console m Bool
  IsInteractive :: Console m Bool

type instance DispatchOf Console = Dynamic

putText :: (Console :> es) => Text -> Eff es ()
putText msg = send (PutText msg)

putError :: (Console :> es) => Text -> Eff es ()
putError msg = send (PutError msg)

getLine :: (Console :> es) => Eff es Text
getLine = send GetLine

confirm :: (Console :> es) => Text -> Eff es Bool
confirm prompt = send (Confirm prompt)

isInteractive :: (Console :> es) => Eff es Bool
isInteractive = send IsInteractive
