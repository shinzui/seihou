{-# LANGUAGE TemplateHaskell #-}

-- | @seihou run NAME@ when NAME is a judgement: preview, collect consent and
-- adopt. The bundled catalogue is embedded here because it needs
-- "Data.FileEmbed"; everything else lives in "Seihou.CLI.Judgement.Adopt".
module Seihou.CLI.RunJudgement
  ( bundledJudgementSource,
    runJudgementAdoption,
    resolveReferencedJudgements,
    planReferencedJudgements,
  )
where

import Control.Monad (forM, unless, when)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (RunOpts (..))
import Seihou.CLI.Judgement.Adopt
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.Expr (evalExpr, parseExpr)
import Seihou.Core.Judgement (DataPolicy (..), JudgementDefinition, JudgementRef)
import Seihou.Core.Module (discoverRunnable)
import Seihou.Core.Types (JudgementOwner (..), JudgementSource (..), ModuleLoadError (..), ModuleName (..), Runnable (..), VarName, VarValue)
import Seihou.Dhall.Eval (evalJudgementFromText, evalJudgementRefsFromFile)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hFlush, hIsTerminalDevice, stdin, stdout)

-- | The Dhall source of a judgement built into this binary, by name.
bundledJudgementSource :: ModuleName -> Maybe (FilePath, Text)
bundledJudgementSource name = case name ^. #unModuleName of
  "security-review" -> Just ("<bundled>/security-review/judgement.dhall", TE.decodeUtf8 $(embedFile "data/judgements/security-review/judgement.dhall"))
  _ -> Nothing

-- | Preview and adopt; never returns.
runJudgementAdoption :: RunOpts -> JudgementSource -> JudgementDefinition -> IO a
runJudgementAdoption opts source def = do
  unless (null (opts ^. #additional)) $
    abort "A judgement is adopted on its own; it cannot be composed with additional modules."
  root <- getCurrentDirectory
  inputs <- gatherAdoptionInputs >>= either abort pure
  interactive <- hIsTerminalDevice stdin
  let configured = inputs ^. #configuredPolicy
  if opts ^. #dryRun
    then do
      plan <- planAdoption root inputs (Just (fromMaybe ApprovedRemote configured)) DirectAdoption source def >>= either abort pure
      TIO.putStr (renderAdoptionPlan plan)
      when (configured /= Just ApprovedRemote) $
        TIO.putStrLn "Adoption will ask you to permit sending staged changes to that route, or needs seihou config set judgement.dataPolicy approved-remote when not interactive."
      TIO.putStrLn "Dry run: nothing was written."
      exitSuccess
    else do
      consent <- case configured of
        Just p -> pure (Just p)
        Nothing
          | interactive -> do
              preview <- planAdoption root inputs (Just ApprovedRemote) DirectAdoption source def >>= either abort pure
              TIO.putStr (renderAdoptionPlan preview)
              TIO.putStr ("Activate it and permit sending staged changes to " <> preview ^. #routeLabel <> "? [y/N] ")
              hFlush stdout
              answer <- T.toLower . T.strip <$> TIO.getLine
              if answer `elem` ["y", "yes"] then pure (Just ApprovedRemote) else abort "Nothing was activated."
          | otherwise -> pure Nothing
      plan <- planAdoption root inputs consent DirectAdoption source def >>= either abort pure
      when (configured == Just ApprovedRemote || not interactive) $ TIO.putStr (renderAdoptionPlan plan)
      applyAdoption plan >>= either abort pure
      TIO.putStrLn ("Judgement '" <> plan ^. #active . #definition . #name <> "' is active. seihou check runs it on every commit.")
      exitSuccess
  where
    abort msg = TIO.putStrLn (T.stripEnd msg) >> exitFailure

-- | The judgements a composition references: every @judgements@ entry of each
-- given @module.dhall@ or @recipe.dhall@ whose @when@ holds for that
-- artifact's variables, resolved once per name through the search paths and
-- then the bundled catalogue.
resolveReferencedJudgements :: FilePath -> [FilePath] -> [(FilePath, Map VarName VarValue)] -> IO (Either Text [(JudgementSource, JudgementDefinition)])
resolveReferencedJudgements root searchPaths sources = do
  collected <- forM sources $ \(file, vars) ->
    evalJudgementRefsFromFile file <&> \case
      Left _ -> Right []
      Right refs -> traverse (\r -> (,r) <$> holds vars r) refs <&> \pairs -> [r | (True, r) <- pairs]
  case sequence collected of
    Left err -> pure (Left err)
    Right refss -> do
      let names = Map.keys (Map.fromList [(r ^. #name, ()) | r <- concat refss])
      fmap sequence . forM names $ \n ->
        discoverRunnable searchPaths (ModuleName n) >>= \case
          Right (RunnableJudgement def dir) -> do
            origin <- detectArtifactOrigin root dir
            pure (Right (ArtifactJudgement origin, def))
          Right _ -> pure (Left ("'" <> n <> "' is referenced as a judgement but is another kind of artifact"))
          Left (ModuleNotFound _ _) -> case bundledJudgementSource (ModuleName n) of
            Just (path, text) ->
              evalJudgementFromText path text <&> \case
                Right def -> Right (BundledJudgement, def)
                Left _ -> Left ("the bundled judgement '" <> n <> "' does not decode")
            Nothing -> pure (Left ("The referenced judgement '" <> n <> "' was not found; install it with seihou install SOURCE --module " <> n))
          Left _ -> pure (Left ("The referenced judgement '" <> n <> "' could not be loaded; run seihou validate-judgement " <> n))
  where
    holds :: Map VarName VarValue -> JudgementRef -> Either Text Bool
    holds vars r = case r ^. #when of
      Nothing -> Right True
      Just t -> either (\e -> Left ("judgement reference '" <> r ^. #name <> "' has an invalid when: " <> e)) (Right . evalExpr vars) (parseExpr t)

-- | Plan the adoption of referenced judgements before anything is written,
-- collecting consent once for all of them.
planReferencedJudgements :: RunOpts -> JudgementOwner -> [(JudgementSource, JudgementDefinition)] -> IO (Either Text [AdoptionPlan])
planReferencedJudgements opts owner refs = do
  root <- getCurrentDirectory
  gatherAdoptionInputs >>= \case
    Left err -> pure (Left err)
    Right inputs -> do
      interactive <- hIsTerminalDevice stdin
      let configured = inputs ^. #configuredPolicy
          planAll consent = sequence <$> mapM (\(src, def) -> planAdoption root inputs consent owner src def) refs
      if opts ^. #dryRun || configured == Just ApprovedRemote
        then planAll (Just (fromMaybe ApprovedRemote configured))
        else
          if not interactive
            then planAll configured
            else
              planAll (Just ApprovedRemote) >>= \case
                Left err -> pure (Left err)
                Right previews -> do
                  mapM_ (TIO.putStr . renderAdoptionPlan) previews
                  TIO.putStr ("Activate these judgements and permit sending staged changes to their review route? [y/N] ")
                  hFlush stdout
                  answer <- T.toLower . T.strip <$> TIO.getLine
                  pure (if answer `elem` ["y", "yes"] then Right previews else Left "Nothing was applied: the referenced judgements were not permitted.")
