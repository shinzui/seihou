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
    formatPlanViewColor,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Types (DiffResult (..), Module (..), ModuleName (..), VarName (..), VarValue (..))
import Seihou.Engine.Preview
import Seihou.Engine.Validate
import Seihou.Prelude
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
  if null lines'
    then "No operations to perform.\n"
    else T.unlines (map (renderColorLine maxPathLen) fileLines ++ map renderNonFileColor nonFileLines)
  where
    fileLines = [l | l@(FilePreview {}) <- lines']
    nonFileLines = [l | l <- lines', not (isFilePreview' l)]
    -- PreviewLine is a sum type and `path` lives only in FilePreview, so this
    -- is a pattern match rather than a #path read: generic-lens can only build
    -- a lens for a field that every constructor has.
    maxPathLen = maximum (0 : [T.length (T.pack p) | FilePreview {path = p} <- lines'])

renderColorLine :: Int -> PreviewLine -> Text
renderColorLine maxPath (FilePreview status path annotation mMod) =
  let (tag, colorFn) = statusStyleColor status
      pathText = T.pack path
      pathPad = T.replicate (maxPath - T.length pathText) " "
      modSuffix = case mMod of
        Just mn -> ", " <> (mn ^. #unModuleName)
        Nothing -> ""
   in "    " <> tag <> "  " <> colorFn pathText <> pathPad <> "  " <> dim ("(" <> annotation <> modSuffix <> ")")
renderColorLine _ other = renderNonFileColor other

renderNonFileColor :: PreviewLine -> Text
renderNonFileColor (DirPreview path) =
  "    " <> cyan "mkdir" <> "  " <> cyan (T.pack path)
renderNonFileColor (CommandPreview cmd mOwner) =
  "    " <> dim "run" <> "    " <> dim cmd <> ownerSuffix mOwner
  where
    ownerSuffix = maybe "" (\owner -> "  " <> dim ("(" <> owner ^. #unModuleName <> ")"))
renderNonFileColor (OrphanPreview path modName') =
  "    " <> magenta "[orphaned]" <> "  " <> magenta (T.pack path) <> "  " <> dim ("(orphaned from " <> modName' ^. #unModuleName <> ")")
renderNonFileColor _ = ""

isFilePreview' :: PreviewLine -> Bool
isFilePreview' (FilePreview {}) = True
isFilePreview' _ = False

statusStyleColor :: FileStatus -> (Text, Text -> Text)
statusStyleColor FsNew = (green "[new]", green)
statusStyleColor FsModified = (yellow "[modified]", yellow)
statusStyleColor FsUnchanged = (dim "[unchanged]", dim)
statusStyleColor FsConflict = (bold (red "[conflict]"), bold . red)
statusStyleColor FsOrphaned = (magenta "[orphaned]", magenta)
statusStyleColor FsUnknown = ("[unknown]", id)

-- | Format a complete plan view with optional ANSI color.
formatPlanViewColor :: Bool -> [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text
formatPlanViewColor False modNames vars preview diff = formatPlanView modNames vars preview diff
formatPlanViewColor True modNames vars preview diff =
  T.unlines $
    [header, ""]
      ++ varsSection
      ++ ["  Operations:"]
      ++ map ("  " <>) (T.lines (renderPreviewColor True preview))
      ++ [""]
      ++ [summaryText']
  where
    header =
      bold
        ( "Generation Plan ("
            <> T.intercalate " + " (map (cyan . (^. #unModuleName)) modNames)
            <> "):"
        )

    varsSection =
      if Map.null vars
        then []
        else
          "  Variables:"
            : map formatVar' (Map.toAscList vars)
            ++ [""]

    maxVarLen = maximum (0 : map (\(VarName n, _) -> T.length n) (Map.toAscList vars))

    formatVar' (VarName name, val) =
      let namePad = T.replicate (maxVarLen - T.length name) " "
       in "    " <> name <> namePad <> " = " <> showVarValueColor val

    showVarValueColor (VText t) = cyan ("\"" <> t <> "\"")
    showVarValueColor (VBool True) = cyan "true"
    showVarValueColor (VBool False) = cyan "false"
    showVarValueColor (VInt n) = cyan (T.pack (show n))
    showVarValueColor (VList vs) = "[" <> T.intercalate ", " (map showVarValueColor vs) <> "]"

    nFiles = countNew preview + countMod preview
    nConflicts = countConf preview

    summaryText'
      | nConflicts > 0 =
          "  "
            <> T.pack (show nFiles)
            <> " files to write, "
            <> bold (red (T.pack (show nConflicts) <> " conflicts"))
      | otherwise =
          "  "
            <> T.pack (show nFiles)
            <> " files to write, "
            <> T.pack (show nConflicts)
            <> " conflicts"

    countNew = length . filter (\l -> case l of FilePreview FsNew _ _ _ -> True; _ -> False)
    countMod = length . filter (\l -> case l of FilePreview FsModified _ _ _ -> True; _ -> False)
    countConf = length . filter (\l -> case l of FilePreview FsConflict _ _ _ -> True; _ -> False)

-- | Render a validation report with optional ANSI color.
-- When the first argument is False, falls back to plain text.
renderReportColor :: Bool -> ValidateReport -> Text
renderReportColor False report = renderReportPlain report
renderReportColor True report =
  T.unlines $
    [ "Validating module at " <> T.pack (report ^. #path) <> "...",
      ""
    ]
      ++ dhallLine'
      ++ summaryLines'
      ++ checkLines'
      ++ [""]
      ++ [resultLine']
  where
    m = (report ^. #module_)

    dhallLine' =
      if report ^. #dhallOk
        then ["  " <> green "\x2713" <> " module.dhall evaluates successfully"]
        else
          ["  " <> bold (red "\x2717") <> " module.dhall failed to evaluate"]
            ++ case report ^. #dhallError of
              Just errText -> ["      " <> dim errText]
              Nothing -> []

    summaryLines' =
      if report ^. #dhallOk
        then
          [ "  " <> green "\x2713" <> " Module name: " <> cyan (m ^. #name . #unModuleName),
            "  " <> green "\x2713" <> " " <> T.pack (show (length (m ^. #vars))) <> " variables declared",
            "  " <> green "\x2713" <> " " <> T.pack (show (length (m ^. #prompts))) <> " prompts defined",
            "  " <> green "\x2713" <> " " <> T.pack (show (length (m ^. #steps))) <> " steps defined"
          ]
        else []

    checkLines' = concatMap renderCheckColor (report ^. #checks)

    renderCheckColor c
      | null (c ^. #details) =
          ["  " <> green "\x2713" <> " " <> c ^. #label]
      | c ^. #severity == DiagWarning =
          ("  " <> yellow "\x26A0" <> " " <> yellow (c ^. #label))
            : map (\d -> "      " <> dim d) (c ^. #details)
      | otherwise =
          ("  " <> bold (red "\x2717") <> " " <> red (c ^. #label))
            : map (\d -> "      " <> dim d) (c ^. #details)

    errorCount =
      length
        [ ()
        | c <- report ^. #checks,
          c ^. #severity == DiagError,
          not (null (c ^. #details))
        ]

    dhallFailed = not (report ^. #dhallOk)
    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine'
      | totalErrors > 0 =
          bold (red (T.pack (show totalErrors) <> " error(s) found.")) <> " Module is invalid."
      | otherwise =
          green ("Module '" <> m ^. #name . #unModuleName <> "' is valid.")
