{-# LANGUAGE TemplateHaskell #-}

-- | @seihou run NAME@ when NAME is a judgement: preview, collect consent and
-- adopt. The bundled catalogue is embedded here because it needs
-- "Data.FileEmbed"; everything else lives in "Seihou.CLI.Judgement.Adopt".
module Seihou.CLI.RunJudgement
  ( bundledJudgementSource,
    runJudgementAdoption,
  )
where

import Control.Monad (unless, when)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (RunOpts (..))
import Seihou.CLI.Judgement.Adopt
import Seihou.Core.Judgement (DataPolicy (..), JudgementDefinition)
import Seihou.Core.Types (JudgementSource, ModuleName (..))
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
      plan <- planAdoption root inputs (Just (fromMaybe ApprovedRemote configured)) source def >>= either abort pure
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
              preview <- planAdoption root inputs (Just ApprovedRemote) source def >>= either abort pure
              TIO.putStr (renderAdoptionPlan preview)
              TIO.putStr ("Activate it and permit sending staged changes to " <> preview ^. #routeLabel <> "? [y/N] ")
              hFlush stdout
              answer <- T.toLower . T.strip <$> TIO.getLine
              if answer `elem` ["y", "yes"] then pure (Just ApprovedRemote) else abort "Nothing was activated."
          | otherwise -> pure Nothing
      plan <- planAdoption root inputs consent source def >>= either abort pure
      when (configured == Just ApprovedRemote || not interactive) $ TIO.putStr (renderAdoptionPlan plan)
      applyAdoption plan >>= either abort pure
      TIO.putStrLn ("Judgement '" <> plan ^. #active . #definition . #name <> "' is active. seihou check runs it on every commit.")
      exitSuccess
  where
    abort msg = TIO.putStrLn (T.stripEnd msg) >> exitFailure
