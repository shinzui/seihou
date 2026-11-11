-- | @seihou new-judgement NAME@: scaffold a judgement artifact.
module Seihou.CLI.NewJudgement (handleNewJudgement) where

import Control.Monad (unless, when)
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (NewJudgementOpts (..))
import Seihou.CLI.SchemaVersion (schemaHash, schemaUrl)
import Seihou.Core.Module (isValidModuleName)
import Seihou.Core.Scaffold (judgementDhall, judgementExamplesJson)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesPathExist)
import System.Exit (exitFailure)

handleNewJudgement :: NewJudgementOpts -> IO ()
handleNewJudgement opts = do
  let name = opts ^. #name
      outputDir = fromMaybe (".seihou" </> "modules" </> T.unpack name) (opts ^. #path)
  unless (isValidModuleName name) $ do
    TIO.putStrLn ("Invalid judgement name '" <> name <> "'. Judgement names must match [a-z][a-z0-9-]*.")
    exitFailure
  exists <- doesPathExist outputDir
  when exists $ do
    TIO.putStrLn ("'" <> T.pack outputDir <> "' already exists; choose another name or --path. Nothing was written.")
    exitFailure
  createDirectoryIfMissing True outputDir
  TIO.writeFile (outputDir </> "judgement.dhall") (judgementDhall name schemaUrl schemaHash)
  TIO.writeFile (outputDir </> "examples.json") judgementExamplesJson
  TIO.putStr . T.unlines $
    [ "Created " <> T.pack (outputDir </> "judgement.dhall"),
      "Created " <> T.pack (outputDir </> "examples.json"),
      "Next: describe the concern in the instructions field, replace the placeholder example, then run",
      "  seihou validate-judgement " <> name,
      "  seihou judgement eval " <> name,
      "  seihou run " <> name
    ]
