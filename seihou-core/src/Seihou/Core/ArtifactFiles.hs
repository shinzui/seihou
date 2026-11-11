-- | The definition files that identify an artifact directory's kind, and the
-- ambiguity rule introduced with judgements.
--
-- Before judgements, a directory holding several definition files resolved by
-- a fixed precedence (module > recipe > blueprint > prompt). Judgements do not
-- join that precedence: a @judgement.dhall@ that shares its directory with any
-- other definition file is reported as ambiguous instead of being silently
-- hidden by, or silently hiding, the other artifact.
module Seihou.Core.ArtifactFiles
  ( definitionFiles,
    presentDefinitionFiles,
    judgementAmbiguity,
    renderAmbiguousArtifact,
  )
where

import Control.Monad (filterM)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Every artifact definition file, in the historical precedence order.
definitionFiles :: [FilePath]
definitionFiles = ["module.dhall", "recipe.dhall", "blueprint.dhall", "prompt.dhall", "judgement.dhall"]

-- | The definition files present directly in a directory, in 'definitionFiles'
-- order.
presentDefinitionFiles :: FilePath -> IO [FilePath]
presentDefinitionFiles dir = filterM (doesFileExist . (dir </>)) definitionFiles

-- | @Just files@ when the directory holds a @judgement.dhall@ together with at
-- least one other definition file; 'Nothing' otherwise. Combinations that do
-- not involve a judgement keep their existing precedence and are not reported.
judgementAmbiguity :: FilePath -> IO (Maybe [FilePath])
judgementAmbiguity dir = do
  present <- presentDefinitionFiles dir
  pure $
    if "judgement.dhall" `elem` present && length present > 1
      then Just present
      else Nothing

-- | One-line diagnostic for an ambiguous artifact directory.
renderAmbiguousArtifact :: ModuleName -> FilePath -> [FilePath] -> Text
renderAmbiguousArtifact name dir files =
  "ambiguous artifact '"
    <> name ^. #unModuleName
    <> "' at "
    <> T.pack dir
    <> ": it contains "
    <> T.intercalate ", " (map T.pack files)
    <> "; an artifact directory must hold exactly one definition file"
