module Seihou.OKF.Extension
  ( okfSmoke,
    runExtensionMain,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Okf.Document (OKFDocument (..), emptyFrontmatter, serializeDocument)
import Options.Applicative
import Options.Applicative.Help.Pretty (pretty, vsep)
import Seihou.OKF.Extension.Docs (DocsOpts (..), handleDocs)

data Command
  = Docs DocsOpts
  deriving stock (Eq, Show)

okfSmoke :: Text
okfSmoke = serializeDocument (OKFDocument emptyFrontmatter "# smoke\n")

runExtensionMain :: IO ()
runExtensionMain = do
  parsedCommand <- customExecParser (prefs showHelpOnEmpty) opts
  case parsedCommand of
    Docs docsOpts ->
      handleDocs docsOpts

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
    (Docs <$> docsParser <**> helper)
    ( fullDesc
        <> progDesc "Generate OKF docs for a Seihou registry"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reads seihou-registry.dhall, loads each listed artifact, validates the OKF bundle," :: String),
                  pretty ("and writes one Markdown concept document per registry entry." :: String),
                  pretty ("Smoke value length: " <> show (T.length okfSmoke) :: String)
                ]
          )
    )

docsParser :: Parser DocsOpts
docsParser =
  DocsOpts
    <$> strOption
      ( long "dir"
          <> metavar "PATH"
          <> value "."
          <> showDefault
          <> help "Registry directory containing seihou-registry.dhall"
      )
    <*> strOption
      ( long "out"
          <> metavar "PATH"
          <> value "okf-docs"
          <> showDefault
          <> help "Output directory for the generated OKF bundle"
      )
    <*> switch (long "force" <> help "Overwrite a non-empty output directory")
    <*> optional
      ( strOption
          ( long "generated-at"
              <> metavar "DATE"
              <> help
                "ISO-8601 date or timestamp recorded as the generation time; \
                \omitted by default so regeneration is byte-stable"
          )
      )
    <*> switch
      ( long "permissive"
          <> help
            "Validate with OKF permissive conformance instead of the default \
            \strict authoring rules"
      )
