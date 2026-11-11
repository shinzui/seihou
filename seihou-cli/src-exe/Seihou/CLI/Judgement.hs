-- | Dispatcher for @seihou judgement eval@ and @seihou judgement configure@.
module Seihou.CLI.Judgement (handleJudgement) where

import Control.Monad (unless, when)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (providerToText)
import Seihou.CLI.Commands (JudgementCommand (..), JudgementConfigureOpts (..), JudgementEvalOpts (..))
import Seihou.CLI.Judgement.Check (loadActiveJudgements)
import Seihou.CLI.Judgement.Config (resolveJudgementRoute)
import Seihou.CLI.Judgement.Configure
import Seihou.CLI.Judgement.Evaluate
import Seihou.CLI.Judgement.Runtime (isRemoteRoute, productionRunner, shikumiBackend)
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.CLI.Judgement.Validate
import Seihou.Core.Judgement (DataPolicy (..), defaultPolicy)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Exit (exitFailure)

handleJudgement :: JudgementCommand -> IO ()
handleJudgement = \case
  JudgementEval opts -> handleEval opts
  JudgementConfigure opts -> handleConfigure opts

abort :: Text -> IO a
abort msg = TIO.putStrLn (T.stripEnd msg) >> exitFailure

handleEval :: JudgementEvalOpts -> IO ()
handleEval opts = do
  dir <- resolveJudgementTarget (Just (opts ^. #name)) >>= either abort pure
  v <- validateJudgementDir dir
  unless (null (v ^. #errors)) $ TIO.putStr (renderValidation v) >> exitFailure
  def <- maybe (abort "The judgement did not decode.") pure (v ^. #definition)
  ex <- maybe (abort ("Judgement '" <> def ^. #name <> "' has no examples.json; add labelled examples first.")) pure (v ^. #examples)
  sc <- findScanner
  if opts ^. #offline
    then do
      counts <- evaluateOffline sc def ex >>= either abort pure
      TIO.putStr . T.unlines $
        [ "Offline evaluation of '" <> def ^. #name <> "': the corpus is valid (" <> T.pack (show (length (ex ^. #examples))) <> " examples, " <> T.pack (show (length (def ^. #checks))) <> " checks)."
        ]
          <> ["  " <> i <> ": " <> T.pack (show n) <> " deterministic finding(s)" | (i, n) <- counts, n > 0]
          <> ["No model request was made. This validates the corpus, the scanner and the policy, not the model's accuracy, and is not a gate approval."]
    else do
      route <- resolveJudgementRoute >>= either abort pure >>= maybe (abort "No review route is configured; set judgement.provider and judgement.model, or run seihou judgement configure NAME --provider PROVIDER --model MODEL.") pure
      root <- getCurrentDirectory
      active <- either (const []) id <$> loadActiveJudgements root
      let policy = case [j | j <- active, j ^. #definition . #name == def ^. #name, j ^. #definition == def] of
            (j : _) -> j ^. #policy
            [] -> defaultPolicy ApprovedRemote False def
          label = providerToText (route ^. #provider) <> " " <> route ^. #model
      TIO.putStrLn ("Sending " <> T.pack (show (length (ex ^. #examples))) <> " synthetic example(s) to " <> label <> ", one request per check per example.")
      (runner, observed) <- productionRunner (def ^. #limits) route
      report <- evaluateExamples (Just (shikumiBackend runner Nothing observed)) (isRemoteRoute route) sc label def policy ex
      TIO.putStr (renderEvalReport report)
      let failedRuntime = or [t ^. #errors > 0 | c <- toList (def ^. #checks), let t = tally [(x ^. #example, x ^. #decision) | x <- report ^. #cases] (c ^. #name)]
      when failedRuntime $ TIO.putStrLn "Some cases ended in errors; see the cases above."

handleConfigure :: JudgementConfigureOpts -> IO ()
handleConfigure opts = do
  root <- getCurrentDirectory
  let req =
        ConfigureRequest
          (opts ^. #name)
          (opts ^. #provider)
          (opts ^. #model)
          (opts ^. #dataPolicy)
          (opts ^. #gateProvider)
          (opts ^. #gateModel)
          (opts ^. #noGate)
          (opts ^. #check)
          (CheckOverride (opts ^. #enforcement) (opts ^. #blockAt) (opts ^. #passAt) (opts ^. #gateBlockAt) (opts ^. #gatePassAt))
          (opts ^. #global)
          (opts ^. #dryRun)
  plan <- planConfigure root req >>= either abort pure
  TIO.putStrLn ("Judgement '" <> opts ^. #name <> "':")
  TIO.putStr (renderConfigurePlan plan)
  if opts ^. #dryRun
    then TIO.putStrLn "Dry run: nothing was written."
    else applyConfigure root plan >>= either abort (const (TIO.putStrLn "Saved."))
