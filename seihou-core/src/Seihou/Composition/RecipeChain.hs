-- | Offline discovery of a recipe chain and its member origins. Acquisition
-- belongs to install/update; this loader never fetches or changes the cache.
module Seihou.Composition.RecipeChain (loadRecipeChain, recordRecipeChain) where

import Control.Lens ((^.))
import Control.Monad (forM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Composition.Recipe
import Seihou.Composition.Resolve (verifyDependencySources)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl, sameArtifactIdentity)
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin, readOriginInfo)
import Seihou.Core.Module (discoverModule, discoverRunnable)
import Seihou.Core.Recipe (validateRecipe, validateRecipeVersion)
import Seihou.Core.Types
import Seihou.Dhall.Eval (normalizeDhallFile)
import Seihou.Manifest.Hash (hashContent)
import System.FilePath ((</>))

loadRecipeChain :: FilePath -> [FilePath] -> Recipe -> FilePath -> IO (Either ModuleLoadError ExpandedRecipe)
loadRecipeChain projectRoot paths target targetDir = do
  result <- runExceptT $ do
    nodes <- visit [] target targetDir
    ExceptT $ pure $ either (Left . ValidationError targetName) Right (mergeRecipeChain nodes)
  case result of
    Right expanded -> pure (Right expanded)
    Left err -> do
      info <- readOriginInfo targetDir
      let repair = case info of
            Just origin -> "Retry: seihou install " <> origin ^. #sourceUrl <> " --module " <> target ^. #name . #unRecipeName
            Nothing -> "Restore the required local recipes and members, or install the derived recipe from its declaring registry."
      pure (Left (ValidationError targetName ["Recipe '" <> target ^. #name . #unRecipeName <> "': " <> describe err, repair]))
  where
    targetName = ModuleName (target ^. #name . #unRecipeName)
    failure :: T.Text -> ExceptT ModuleLoadError IO a
    failure msg = ExceptT (pure (Left (ValidationError targetName [msg])))
    visit active descriptor dir = do
      _ <- ExceptT $ pure $ either (Left . ValidationError targetName) Right (validateRecipe descriptor)
      origin <- liftIO (detectArtifactOrigin projectRoot dir)
      let name = descriptor ^. #name
      when (any (\(n, o) -> n == name && sameArtifactIdentity o origin) active) $
        failure ("Recipe base cycle: " <> T.intercalate " -> " (map ((^. #unRecipeName) . fst) (reverse active) <> [name ^. #unRecipeName]))
      parents <- case descriptor ^. #extends of
        Nothing -> pure []
        Just ref -> do
          foundResult <- liftIO (discoverRunnable paths (ModuleName (ref ^. #recipe . #unRecipeName)))
          found <- case foundResult of
            Left err -> failure ("Base chain " <> T.intercalate " -> " (map ((^. #unRecipeName) . fst) (reverse ((name, origin) : active)) <> [ref ^. #recipe . #unRecipeName]) <> ": " <> describe err)
            Right value -> pure value
          case found of
            RunnableRecipe base baseDir -> do
              case ref ^. #source of
                Nothing -> pure ()
                Just required -> do
                  actual <- liftIO (readOriginInfo baseDir)
                  unless (maybe False (\info -> normalizeOriginUrl (info ^. #sourceUrl) == normalizeOriginUrl required) actual) $
                    failure ("Base '" <> ref ^. #recipe . #unRecipeName <> "' requires " <> required <> "; resolved origin is different or unknown")
              case validateRecipeVersion ref base of
                Left errors -> failure ("Base '" <> ref ^. #recipe . #unRecipeName <> "' from " <> maybe "local discovery" id (ref ^. #source) <> ": " <> T.intercalate "; " errors)
                Right () -> pure ()
              visit ((name, origin) : active) base baseDir
            _ -> failure ("Expected recipe base '" <> ref ^. #recipe . #unRecipeName <> "'")
      ExceptT (verifyDependencySources paths dir (descriptor ^. #modules))
      members <- forM (descriptor ^. #modules) $ \dep -> do
        memberDir <- ExceptT (discoverModule paths (dep ^. #module_))
        memberOrigin <- liftIO (detectArtifactOrigin projectRoot memberDir)
        pure (ResolvedRecipeMember dep name origin dir memberOrigin)
      pure (parents <> [ResolvedRecipeNode descriptor origin dir members])

-- Keep local discovery failures useful without exposing Haskell constructors.
describe :: ModuleLoadError -> T.Text
describe (ModuleNotFound (ModuleName name) _) = "Required recipe or member '" <> name <> "' was not found locally"
describe (DhallEvalError _ reason) = "Cannot evaluate descriptor: " <> reason
describe (DhallDecodeError _ reason) = "Cannot decode descriptor: " <> reason
describe (ValidationError _ reasons) = T.intercalate "; " reasons
describe (CircularDependency names) = "Dependency cycle: " <> T.intercalate " -> " [name | ModuleName name <- names]
describe (MissingSourceFile (ModuleName name) path) = "Member '" <> name <> "' is missing " <> T.pack path
describe (RegistryEvalError source reason) = "Cannot evaluate registry '" <> source <> "': " <> reason

-- | Descriptor evidence is normalized Dhall, independent of import/cache paths.
recordRecipeChain :: ExpandedRecipe -> IO [AppliedRecipeNode]
recordRecipeChain expanded = forM (expanded ^. #chain) $ \node -> do
  canonical <- normalizeDhallFile (node ^. #directory </> "recipe.dhall")
  pure (AppliedRecipeNode (node ^. #definition . #name) (node ^. #origin) (node ^. #definition . #version) (hashContent canonical))
