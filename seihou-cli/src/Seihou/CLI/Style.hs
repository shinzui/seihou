module Seihou.CLI.Style
  ( useColor,
    green,
    yellow,
    red,
    magenta,
    dim,
    bold,
    cyan,
    renderPreviewColor,
    renderReportColor,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types (Module (..), ModuleName (..))
import Seihou.Engine.Preview
import Seihou.Engine.Validate
import System.Console.ANSI
  ( Color (..),
    ColorIntensity (..),
    ConsoleIntensity (..),
    ConsoleLayer (..),
    SGR (..),
    hSupportsANSIColor,
    setSGRCode,
  )
import System.IO (stdout)

-- | Check whether stdout supports ANSI color output.
useColor :: IO Bool
useColor = hSupportsANSIColor stdout

-- | Wrap text in ANSI color codes.
withSGR :: [SGR] -> Text -> Text
withSGR codes t =
  T.pack (setSGRCode codes) <> t <> T.pack (setSGRCode [Reset])

green :: Text -> Text
green = withSGR [SetColor Foreground Dull Green]

yellow :: Text -> Text
yellow = withSGR [SetColor Foreground Dull Yellow]

red :: Text -> Text
red = withSGR [SetColor Foreground Vivid Red]

magenta :: Text -> Text
magenta = withSGR [SetColor Foreground Dull Magenta]

dim :: Text -> Text
dim = withSGR [SetConsoleIntensity FaintIntensity]

bold :: Text -> Text
bold = withSGR [SetConsoleIntensity BoldIntensity]

cyan :: Text -> Text
cyan = withSGR [SetColor Foreground Dull Cyan]

-- | Render preview lines with optional ANSI color.
-- When the first argument is False, falls back to plain text.
renderPreviewColor :: Bool -> [PreviewLine] -> Text
renderPreviewColor False lines' = renderPreviewPlain lines'
renderPreviewColor True lines' =
  T.unlines (map renderColorLine lines' ++ [summaryLine lines'])

renderColorLine :: PreviewLine -> Text
renderColorLine (FilePreview status verb path annotation) =
  let (prefix, colorFn) = statusStyle status
      pathText = T.pack path
   in "  " <> prefix <> " " <> verb <> "  " <> colorFn pathText <> "  " <> dim annotation
renderColorLine (DirPreview path) =
  "  " <> "  " <> " " <> cyan "mkdir" <> "  " <> cyan (T.pack path)
renderColorLine (CommandPreview cmd) =
  "  " <> "  " <> " " <> dim "run" <> "    " <> dim cmd
renderColorLine (OrphanPreview path modName') =
  "  " <> magenta "-" <> " " <> magenta (T.pack path) <> "  " <> dim ("(orphaned from " <> unModuleName modName' <> ")")

statusStyle :: FileStatus -> (Text, Text -> Text)
statusStyle FsNew = (green "+", green)
statusStyle FsModified = (yellow "~", yellow)
statusStyle FsUnchanged = (dim "=", dim)
statusStyle FsConflict = (bold (red "!"), bold . red)
statusStyle FsOrphaned = (magenta "-", magenta)
statusStyle FsUnknown = (" ", id)

summaryLine :: [PreviewLine] -> Text
summaryLine lines' =
  let nNew = count isNew lines'
      nMod = count isMod lines'
      nUnch = count isUnch lines'
      nConf = count isConf lines'
      nOrph = count isOrph lines'
   in "\n"
        <> green (T.pack (show nNew) <> " new")
        <> ", "
        <> yellow (T.pack (show nMod) <> " modified")
        <> ", "
        <> T.pack (show nUnch)
        <> " unchanged"
        <> ", "
        <> (if nConf > 0 then bold (red (T.pack (show nConf) <> " conflicts")) else T.pack (show nConf) <> " conflicts")
        <> ", "
        <> (if nOrph > 0 then magenta (T.pack (show nOrph) <> " orphaned") else T.pack (show nOrph) <> " orphaned")
  where
    count f = length . filter f
    isNew (FilePreview FsNew _ _ _) = True
    isNew _ = False
    isMod (FilePreview FsModified _ _ _) = True
    isMod _ = False
    isUnch (FilePreview FsUnchanged _ _ _) = True
    isUnch _ = False
    isConf (FilePreview FsConflict _ _ _) = True
    isConf _ = False
    isOrph (OrphanPreview {}) = True
    isOrph _ = False

-- | Render a validation report with optional ANSI color.
-- When the first argument is False, falls back to plain text.
renderReportColor :: Bool -> ValidateReport -> Text
renderReportColor False report = renderReportPlain report
renderReportColor True report =
  T.unlines $
    [ "Validating module at " <> T.pack (reportPath report) <> "...",
      ""
    ]
      ++ dhallLine'
      ++ summaryLines'
      ++ checkLines'
      ++ [""]
      ++ [resultLine']
  where
    m = reportModule report

    dhallLine' =
      if reportDhallOk report
        then ["  " <> green "\x2713" <> " module.dhall evaluates successfully"]
        else ["  " <> bold (red "\x2717") <> " module.dhall failed to evaluate"]

    summaryLines' =
      if reportDhallOk report
        then
          [ "  " <> green "\x2713" <> " Module name: " <> cyan (unModuleName (moduleName m)),
            "  " <> green "\x2713" <> " " <> T.pack (show (length (moduleVars m))) <> " variables declared",
            "  " <> green "\x2713" <> " " <> T.pack (show (length (modulePrompts m))) <> " prompts defined",
            "  " <> green "\x2713" <> " " <> T.pack (show (length (moduleSteps m))) <> " steps defined"
          ]
        else []

    checkLines' = concatMap renderCheckColor (reportChecks report)

    renderCheckColor c
      | null (diagDetails c) =
          ["  " <> green "\x2713" <> " " <> diagLabel c]
      | diagSeverity c == DiagWarning =
          ("  " <> yellow "\x26A0" <> " " <> yellow (diagLabel c))
            : map (\d -> "      " <> dim d) (diagDetails c)
      | otherwise =
          ("  " <> bold (red "\x2717") <> " " <> red (diagLabel c))
            : map (\d -> "      " <> dim d) (diagDetails c)

    errorCount =
      length
        [ ()
        | c <- reportChecks report,
          diagSeverity c == DiagError,
          not (null (diagDetails c))
        ]

    dhallFailed = not (reportDhallOk report)
    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine'
      | totalErrors > 0 =
          bold (red (T.pack (show totalErrors) <> " error(s) found.")) <> " Module is invalid."
      | otherwise =
          green ("Module '" <> unModuleName (moduleName m) <> "' is valid.")
