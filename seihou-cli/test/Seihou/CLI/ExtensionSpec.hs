module Seihou.CLI.ExtensionSpec (tests) where

import Control.Exception (bracket_)
import Seihou.CLI.Extension
import System.Directory
  ( getPermissions,
    setOwnerExecutable,
    setPermissions,
  )
import System.Environment (getEnv, setEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Extension" spec

spec :: Spec
spec = do
  describe "extensionExecutableName" $ do
    it "uses the seihou extension executable naming convention" $ do
      extensionExecutableName "okf" `shouldBe` "seihou-okf-extension"

  describe "runExtension" $ do
    it "reports a missing executable by its resolved name" $ do
      result <- runExtension (ExtensionRunOpts "missing-extension-spec" ["--help"])
      result `shouldBe` Left (ExtensionNotFound "missing-extension-spec" "seihou-missing-extension-spec-extension")

    it "forwards arguments to the resolved extension executable unchanged" $
      withSystemTempDirectory "seihou-extension-spec" $ \dir -> do
        let exePath = dir </> "seihou-okf-extension"
            argsPath = dir </> "args.txt"
        writeFile exePath $
          unlines
            [ "#!/bin/sh",
              "printf '%s\\n' \"$@\" > " <> show argsPath
            ]
        permissions <- getPermissions exePath
        setPermissions exePath (setOwnerExecutable True permissions)
        withPrependedPath dir $ do
          result <- runExtension (ExtensionRunOpts "okf" ["docs", "--dir", "."])
          result `shouldBe` Right ()
        readFile argsPath `shouldReturn` "docs\n--dir\n.\n"

    it "reports the extension exit code when the executable fails" $
      withSystemTempDirectory "seihou-extension-failure-spec" $ \dir -> do
        let exePath = dir </> "seihou-okf-extension"
        writeFile exePath "#!/bin/sh\nexit 42\n"
        permissions <- getPermissions exePath
        setPermissions exePath (setOwnerExecutable True permissions)
        withPrependedPath dir $ do
          result <- runExtension (ExtensionRunOpts "okf" [])
          result `shouldBe` Left (ExtensionExited "okf" (ExitFailure 42))

withPrependedPath :: FilePath -> IO a -> IO a
withPrependedPath dir action = do
  originalPath <- getEnv "PATH"
  bracket_
    (setEnv "PATH" (dir <> ":" <> originalPath))
    (setEnv "PATH" originalPath)
    action
