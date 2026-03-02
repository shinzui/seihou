module Seihou.Effect.ProcessInterp
  ( runProcessIO,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Effect.Process (Process (..))
import System.Exit (ExitCode)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)

runProcessIO :: (IOE :> es) => Eff (Process : es) a -> Eff es a
runProcessIO = interpret $ \_ -> \case
  RunProcess cmd args workDir -> liftIO $ do
    let cp =
          (proc (T.unpack cmd) (map T.unpack args))
            { cwd = workDir
            }
    (exitCode, stdout, stderr) <- readCreateProcessWithExitCode cp ""
    pure (exitCode, T.pack stdout, T.pack stderr)
