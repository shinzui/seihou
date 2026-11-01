-- | Offline discovery of a recipe chain and its member origins. Acquisition
-- belongs to install/update; this loader never fetches or changes the cache.
module Seihou.Composition.RecipeChain (loadRecipeChain) where

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

loadRecipeChain :: FilePath -> [FilePath] -> Recipe -> FilePath -> IO (Either ModuleLoadError ExpandedRecipe)
loadRecipeChain projectRoot paths target targetDir = runExceptT $ do
  nodes <- visit [] target targetDir
  ExceptT $ pure $ either (Left . ValidationError targetName) Right (mergeRecipeChain nodes)
  where
    targetName = ModuleName (target ^. #name . #unRecipeName)
    failure :: T.Text -> ExceptT ModuleLoadError IO a
    failure msg = ExceptT (pure (Left (ValidationError targetName [msg <> ". Reinstall the derived recipe '" <> target ^. #name . #unRecipeName <> "' and its closure."])))
    visit active descriptor dir = do
      _ <- ExceptT $ pure $ either (Left . ValidationError targetName) Right (validateRecipe descriptor)
      origin <- liftIO (detectArtifactOrigin projectRoot dir)
      let name = descriptor ^. #name
      when (any (\(n, o) -> n == name && sameArtifactIdentity o origin) active) $
        failure ("Recipe base cycle: " <> T.intercalate " -> " (map ((^. #unRecipeName) . fst) (reverse active) <> [name ^. #unRecipeName]))
      parents <- case descriptor ^. #extends of
        Nothing -> pure []
        Just ref -> do
          found <- ExceptT (discoverRunnable paths (ModuleName (ref ^. #recipe . #unRecipeName)))
          case found of
            RunnableRecipe base baseDir -> do
              case ref ^. #source of
                Nothing -> pure ()
                Just required -> do
                  actual <- liftIO (readOriginInfo baseDir)
                  unless (maybe False (\info -> normalizeOriginUrl (info ^. #sourceUrl) == normalizeOriginUrl required) actual) $
                    failure ("Base '" <> ref ^. #recipe . #unRecipeName <> "' requires " <> required <> "; resolved origin is different or unknown")
              ExceptT $ pure $ either (Left . ValidationError targetName) Right (validateRecipeVersion ref base)
              visit ((name, origin) : active) base baseDir
            _ -> failure ("Expected recipe base '" <> ref ^. #recipe . #unRecipeName <> "'")
      ExceptT (verifyDependencySources paths dir (descriptor ^. #modules))
      members <- forM (descriptor ^. #modules) $ \dep -> do
        memberDir <- ExceptT (discoverModule paths (dep ^. #module_))
        memberOrigin <- liftIO (detectArtifactOrigin projectRoot memberDir)
        pure (ResolvedRecipeMember dep name origin dir memberOrigin)
      pure (parents <> [ResolvedRecipeNode descriptor origin dir members])
