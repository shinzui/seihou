module Seihou.OKF.Extension
  ( okfSmoke,
    runExtensionMain,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Okf.Document (OKFDocument (..), emptyFrontmatter, serializeDocument)
import Options.Applicative
import Options.Applicative.Help.Pretty (pretty, vsep)
import System.Exit (exitFailure)

data Command
  = Docs
  deriving stock (Eq, Show)

okfSmoke :: Text
okfSmoke = serializeDocument (OKFDocument emptyFrontmatter "# smoke\n")

runExtensionMain :: IO ()
runExtensionMain = do
  command <- customExecParser (prefs showHelpOnEmpty) opts
  case command of
    Docs -> do
      TIO.putStrLn "seihou-okf-extension docs is not implemented yet; see EP-57/EP-58/EP-59."
      exitFailure

opts :: ParserInfo Command
opts =
  info
    (commandParser <**> helper)
    ( fullDesc
        <> progDesc "Generate OKF documentation bundles for Seihou registries"
        <> header "seihou-okf-extension - OKF documentation extension for Seihou"
    )

commandParser :: Parser Command
commandParser =
  hsubparser
    (command "docs" docsInfo)

docsInfo :: ParserInfo Command
docsInfo =
  info
    (pure Docs <**> helper)
    ( fullDesc
        <> progDesc "Generate OKF docs for a Seihou registry (not implemented yet)"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("This command is a placeholder in EP-60." :: String),
                  pretty ("EP-57, EP-58, and EP-59 add registry loading, OKF rendering, and file output." :: String),
                  pretty ("Smoke value length: " <> show (T.length okfSmoke) :: String)
                ]
          )
    )
