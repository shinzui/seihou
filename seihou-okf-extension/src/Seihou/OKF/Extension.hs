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
import Seihou.OKF.Extension.Version (extensionVersion)

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
    (commandParser <**> helper <**> infoOption ("seihou-okf-extension " <> T.unpack extensionVersion) (long "version" <> help "Show extension version"))
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
    (Docs <$> docsParser)
    ( fullDesc
        <> progDesc "Generate OKF docs for a Seihou registry"
        <> footerDoc
          ( Just $
              vsep
                [ pretty ("Reads seihou-registry.dhall, loads each listed artifact, validates the OKF bundle," :: String),
                  pretty ("and writes one concept per module, recipe, blueprint, prompt and judgement, plus the registry overview." :: String),
                  pretty ("From a fresh checkout: seihou-okf-extension docs. Regenerate: add --force." :: String),
                  pretty ("No dependency installation or command execution is needed. Invalid input preserves existing output." :: String)
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
    <*> optional
      ( strOption
          ( long "profile"
              <> metavar "PATH"
              <> help
                "Check the bundle against this house profile descriptor instead \
                \of the built-in one"
          )
      )
    <*> switch
      ( long "no-profile"
          <> help "Skip house-profile enforcement entirely"
      )
