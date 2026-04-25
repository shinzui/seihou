module Seihou.Core.SchemaUpgrade
  ( UpgradeIssue (..),
    UpgradeResult (..),
    detectIssues,
    upgradeModuleText,
    issueMessage,
  )
where

import Data.Char (isSpace)
import Data.Text qualified as T
import Seihou.Prelude

-- | Describes a single schema issue found in a module.dhall file.
data UpgradeIssue
  = -- | The module record is missing the @version@ field.
    MissingVersion
  | -- | A step record (at the given 0-based index) is missing the @patch@ field.
    MissingStepPatch Int
  | -- | The module record is missing the @commands@ field.
    MissingCommands
  | -- | A dependency is a bare text string rather than a record.
    BareStringDep Text
  | -- | The empty dependency list uses @List Text@ rather than the record type.
    BareStringDepTypeAnnotation
  | -- | The module is missing the @let S = \<url\>@ schema import.
    MissingSchemaImport
  | -- | The module record is missing the @migrations@ field.
    MissingMigrations
  deriving stock (Eq, Show)

-- | Result of attempting to upgrade a module.dhall text.
data UpgradeResult
  = -- | The module already conforms to the current schema.
    AlreadyCurrent
  | -- | The module was upgraded; contains the new text and issues that were fixed.
    Upgraded Text [UpgradeIssue]
  deriving stock (Eq, Show)

-- | Human-readable description of an upgrade issue.
issueMessage :: UpgradeIssue -> Text
issueMessage MissingVersion = "missing field: version"
issueMessage (MissingStepPatch n) = "missing field: patch (in step " <> T.pack (show (n + 1)) <> ")"
issueMessage MissingCommands = "missing field: commands"
issueMessage (BareStringDep name) = "bare string dependency: " <> name
issueMessage BareStringDepTypeAnnotation = "dependency list uses List Text type annotation"
issueMessage MissingSchemaImport = "missing schema import (let S = ...)"
issueMessage MissingMigrations = "missing field: migrations"

-- | Detect all schema issues in a module.dhall text without modifying it.
-- The schema URL is used to check whether the schema import is present.
detectIssues :: Text -> Text -> [UpgradeIssue]
detectIssues schemaUrl content =
  let ls = T.lines content
   in detectMissingVersion ls
        <> detectMissingStepPatch ls
        <> detectMissingCommands ls
        <> detectBareStringDeps ls
        <> detectDepTypeAnnotation ls
        <> detectMissingSchemaImport schemaUrl ls
        <> detectMissingMigrations ls

-- | Upgrade a module.dhall text to the current canonical schema.
-- Returns 'AlreadyCurrent' if no changes are needed.
-- The schema URL and hash are used to inject the schema import if missing.
upgradeModuleText :: Text -> Text -> Text -> UpgradeResult
upgradeModuleText schemaUrl schemaHash content =
  let issues = detectIssues schemaUrl content
   in if null issues
        then AlreadyCurrent
        else
          let upgraded =
                content
                  & applyIf (MissingVersion `elem` issues) insertVersion
                  & applyIf (any isMissingPatch issues) (insertPatchFields issues)
                  & applyIf (MissingCommands `elem` issues) insertCommands
                  & applyIf (any isBareStringDepIssue issues) convertBareStringDeps
                  & applyIf (BareStringDepTypeAnnotation `elem` issues) convertDepTypeAnnotation
                  & applyIf (MissingSchemaImport `elem` issues) (injectSchemaImport schemaUrl schemaHash)
                  & applyIf (MissingMigrations `elem` issues) insertMigrations
           in Upgraded upgraded issues
  where
    applyIf True f x = f x
    applyIf False _ x = x

    isMissingPatch (MissingStepPatch _) = True
    isMissingPatch _ = False

    isBareStringDepIssue (BareStringDep _) = True
    isBareStringDepIssue _ = False

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

detectMissingVersion :: [Text] -> [UpgradeIssue]
detectMissingVersion ls
  | any (matchesField "version") ls = []
  | otherwise = [MissingVersion]

detectMissingCommands :: [Text] -> [UpgradeIssue]
detectMissingCommands ls
  | any (matchesField "commands") ls = []
  | otherwise = [MissingCommands]

detectMissingStepPatch :: [Text] -> [UpgradeIssue]
detectMissingStepPatch ls =
  let blocks = extractStepBlocks ls
   in [ MissingStepPatch i
      | (i, block) <- zip [0 ..] blocks,
        not (any (matchesField "patch") block)
      ]

detectBareStringDeps :: [Text] -> [UpgradeIssue]
detectBareStringDeps ls =
  let depsValue = extractDepsValue ls
   in map BareStringDep (extractBareStrings depsValue)

detectDepTypeAnnotation :: [Text] -> [UpgradeIssue]
detectDepTypeAnnotation ls
  | any (\l -> "List Text" `T.isInfixOf` l && matchesField "dependencies" l) ls =
      [BareStringDepTypeAnnotation]
  | otherwise = []

detectMissingSchemaImport :: Text -> [Text] -> [UpgradeIssue]
detectMissingSchemaImport schemaUrl ls
  | any (\l -> "let S =" `T.isInfixOf` l || "let Schema =" `T.isInfixOf` l) ls,
    any (T.isInfixOf "seihou-schema") ls =
      []
  | -- Also accept if the schema URL itself appears (e.g. different binding name)
    any (T.isInfixOf schemaUrl) ls =
      []
  | otherwise = [MissingSchemaImport]

detectMissingMigrations :: [Text] -> [UpgradeIssue]
detectMissingMigrations ls
  | any (matchesField "migrations") ls = []
  | otherwise = [MissingMigrations]

-- ---------------------------------------------------------------------------
-- Rewriting
-- ---------------------------------------------------------------------------

-- | Insert @, version = None Text@ after the @{ name = ...@ line.
insertVersion :: Text -> Text
insertVersion = mapLines $ \line ->
  if matchesFieldStart "name" line
    then [line, ", version = None Text"]
    else [line]

-- | Insert @, patch = None Text@ into step records that are missing it.
insertPatchFields :: [UpgradeIssue] -> Text -> Text
insertPatchFields issues content =
  let missingIndices = [i | MissingStepPatch i <- issues]
      ls = T.lines content
   in T.unlines (go ls 0 missingIndices False)
  where
    go [] _ _ _ = []
    go (l : rest) idx missing inStep
      | not inStep && containsStepStart l =
          l : go rest idx missing True
      | inStep && isBlockEnd l =
          if idx `elem` missing
            then "    , patch = None Text" : l : go rest (idx + 1) missing False
            else l : go rest (idx + 1) missing False
      | otherwise = l : go rest idx missing inStep

    isBlockEnd line =
      let s = T.stripEnd line
          stripped = T.stripStart line
       in "}" `T.isSuffixOf` s
            && not (containsStepStart stripped)

-- | Insert @, commands = ...@ before @, dependencies =@.
insertCommands :: Text -> Text
insertCommands = mapLines $ \line ->
  if matchesField "dependencies" line
    then [", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }", line]
    else [line]

-- | Convert bare string dependencies to record form.
convertBareStringDeps :: Text -> Text
convertBareStringDeps content =
  let ls = T.lines content
      (before, rest) = break (matchesField "dependencies") ls
   in case rest of
        [] -> content
        _ ->
          let (depsLines, after) = spanDepsRegion rest
              converted = convertDepsLines depsLines
           in T.unlines (before <> converted <> after)

-- | Inject a schema import line and wrap the existing record in @S.Module::@.
-- Prepends @let S = \<url\> \<hash\>@ and replaces the opening @{@ with @in  S.Module::{@.
injectSchemaImport :: Text -> Text -> Text -> Text
injectSchemaImport url hash content =
  let header =
        T.unlines
          [ "let S =",
            "      " <> url,
            "        " <> hash,
            ""
          ]
      ls = T.lines content
      -- Find the first line that starts with '{' (the module record)
      (before, recordLines) = break (T.isPrefixOf "{" . T.stripStart) ls
   in case recordLines of
        [] -> header <> content
        (firstLine : rest) ->
          let -- Replace the leading '{' with 'in  S.Module::{'
              stripped = T.stripStart firstLine
              replaced = "in  S.Module::" <> stripped
           in header <> T.unlines (before <> (replaced : rest))

-- | Convert @[] : List Text@ to the record type annotation.
convertDepTypeAnnotation :: Text -> Text
convertDepTypeAnnotation =
  T.replace
    "[] : List Text"
    "[] : List { module : Text, vars : List { name : Text, value : Text } }"

-- | Insert @, migrations = [] : List S.Migration.Type@ before the closing
-- brace of the module record. Inserts after the @removal = ...@ line if
-- present (it always is on a current schema), otherwise before the closing
-- brace as a fallback.
insertMigrations :: Text -> Text
insertMigrations content =
  let ls = T.lines content
      -- For modules using the schema package, S.Migration.Type is the right
      -- type. For legacy modules without the schema import we still emit the
      -- same line — it will be a forward reference fixed up by adding the
      -- schema import (MissingSchemaImport handler runs separately).
      migrationsLine = "    , migrations = [] : List S.Migration.Type"
      legacyMigrationsLine = ", migrations = [] : List { from : Text, to : Text, ops : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } > }"
      hasSchemaImport =
        any (\l -> "let S =" `T.isInfixOf` l || "let Schema =" `T.isInfixOf` l) ls
      lineToInsert = if hasSchemaImport then migrationsLine else legacyMigrationsLine
   in T.unlines (insertBeforeClose lineToInsert ls)
  where
    -- Insert the new line just before the line that closes the module
    -- record. The closing line is the last line that is exactly @}@ or
    -- @  }@ (the schema-completion-syntax close). We look for the last
    -- such line so we insert into the outermost record, not nested ones.
    insertBeforeClose newLine xs =
      case findLastClosing xs of
        Just idx ->
          take idx xs ++ [newLine] ++ drop idx xs
        Nothing -> xs ++ [newLine]

    findLastClosing :: [Text] -> Maybe Int
    findLastClosing xs =
      let indexed = zip [0 ..] xs
          closes = [i | (i, l) <- indexed, isClosingBrace l]
       in case closes of
            [] -> Nothing
            _ -> Just (last closes)

    isClosingBrace :: Text -> Bool
    isClosingBrace l =
      let s = T.strip l
       in s == "}" || s == "} : T"

-- ---------------------------------------------------------------------------
-- Text utilities
-- ---------------------------------------------------------------------------

-- | Check if a line contains a field assignment like @, fieldName =@ or
-- @{ fieldName =@.
matchesField :: Text -> Text -> Bool
matchesField fieldName line =
  let s = T.stripStart line
   in (", " <> fieldName <> " =") `T.isPrefixOf` s
        || (", " <> fieldName <> "=") `T.isPrefixOf` s
        || ("{ " <> fieldName <> " =") `T.isPrefixOf` s

-- | Like 'matchesField' but only for the first field in a record (using @{@).
matchesFieldStart :: Text -> Text -> Bool
matchesFieldStart fieldName line =
  let s = T.stripStart line
   in ("{ " <> fieldName <> " =") `T.isPrefixOf` s

-- | Apply a per-line transformation and reassemble.
mapLines :: (Text -> [Text]) -> Text -> Text
mapLines f = T.unlines . concatMap f . T.lines

-- | Check if a line contains @{ strategy =@ (possibly preceded by @[@ or @,@).
containsStepStart :: Text -> Bool
containsStepStart line = "{ strategy =" `T.isInfixOf` line || "{ strategy=" `T.isInfixOf` line

-- | Extract step blocks from lines. A step block starts with a line containing
-- @{ strategy =@ and ends at the next line ending with @}@.
extractStepBlocks :: [Text] -> [[Text]]
extractStepBlocks [] = []
extractStepBlocks (l : rest)
  | containsStepStart l =
      let (block, remaining) = spanBlock (l : rest)
       in block : extractStepBlocks remaining
  | otherwise = extractStepBlocks rest
  where
    spanBlock [] = ([], [])
    spanBlock (x : xs)
      | "}" `T.isSuffixOf` T.stripEnd x = ([x], xs)
      | otherwise =
          let (block, remaining) = spanBlock xs
           in (x : block, remaining)

-- | Extract the raw value portion of the dependencies field.
-- For @, dependencies = [ "foo", "bar" ]@ this returns @[ "foo", "bar" ]@.
-- For multi-line deps, concatenates all lines.
extractDepsValue :: [Text] -> Text
extractDepsValue ls =
  let region = extractDepsRegion ls
   in case region of
        [] -> ""
        (firstLine : rest) ->
          -- Strip the field name prefix from the first line
          let val = case T.breakOn "=" firstLine of
                (_, after)
                  | T.null after -> firstLine
                  | otherwise -> T.drop 1 after -- drop the '='
           in T.unlines (val : rest)

-- | Extract the lines in the dependencies region.
extractDepsRegion :: [Text] -> [Text]
extractDepsRegion ls =
  let (_, rest) = break (matchesField "dependencies") ls
   in case rest of
        [] -> []
        _ -> fst (spanDepsRegion rest)

-- | Split the deps region from the rest of the lines.
spanDepsRegion :: [Text] -> ([Text], [Text])
spanDepsRegion [] = ([], [])
spanDepsRegion (l : rest)
  -- Single-line: , dependencies = [ "foo" ] or , dependencies = [] : List Text
  | matchesField "dependencies" l
      && ("]" `T.isSuffixOf` T.stripEnd l || "List Text" `T.isSuffixOf` T.stripEnd l) =
      ([l], rest)
  | matchesField "dependencies" l = collectUntilClose [l] rest
  | otherwise = ([], l : rest)
  where
    collectUntilClose acc [] = (reverse acc, [])
    collectUntilClose acc (x : xs)
      | "]" `T.isSuffixOf` T.stripEnd x = (reverse (x : acc), xs)
      | otherwise = collectUntilClose (x : acc) xs

-- | Extract bare string names from a deps value text.
-- Handles both single-line @[ "foo", "bar" ]@ and multi-line formats.
-- A bare string dep is a quoted string that is NOT preceded by @module =@
-- (which would make it a record field value rather than a bare dep).
extractBareStrings :: Text -> [Text]
extractBareStrings t =
  let pieces = T.splitOn "\"" t
   in extractOddElements pieces
  where
    extractOddElements (context : name : rest)
      -- Skip if the name contains '=' which would mean it's part of a record field value
      | "=" `T.isInfixOf` name = extractOddElements rest
      -- Skip if it looks like a type annotation (contains ':')
      | ":" `T.isInfixOf` name = extractOddElements rest
      | T.null name = extractOddElements rest
      -- Skip if preceded by 'module =' — this is a record-form dependency value
      | "module =" `T.isInfixOf` context = extractOddElements rest
      | "module=" `T.isInfixOf` context = extractOddElements rest
      | otherwise = name : extractOddElements rest
    extractOddElements _ = []

-- | Convert dependency lines, handling both single-line and multi-line formats.
convertDepsLines :: [Text] -> [Text]
convertDepsLines [] = []
convertDepsLines [singleLine]
  -- Single-line deps: , dependencies = [ "foo", "bar" ]
  | matchesField "dependencies" singleLine =
      let indent = T.takeWhile isSpace singleLine
          bareNames = extractBareStrings singleLine
       in case bareNames of
            [] -> [singleLine] -- no bare strings to convert, leave as-is
            _ ->
              let entries =
                    [ "  { module = \"" <> name <> "\", vars = [] : List { name : Text, value : Text } }"
                    | name <- bareNames
                    ]
                  formatted = case entries of
                    [] -> [indent <> ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }"]
                    [e] -> [indent <> ", dependencies = [ " <> T.stripStart e <> " ]"]
                    (first : mid) ->
                      let lastEntry = last mid
                          midEntries = init mid
                       in [indent <> ", dependencies ="]
                            <> [indent <> "  [ " <> T.stripStart first]
                            <> [indent <> "  , " <> T.stripStart e | e <- midEntries]
                            <> [indent <> "  , " <> T.stripStart lastEntry]
                            <> [indent <> "  ]"]
               in formatted
convertDepsLines ls =
  -- Multi-line: convert each line that contains a bare string
  map convertMultiLineDepEntry ls
  where
    convertMultiLineDepEntry line
      | hasBareString line =
          let indent = T.takeWhile isSpace line
              s = T.stripStart line
              prefix
                | "[ " `T.isPrefixOf` s = indent <> "[ "
                | "[" `T.isPrefixOf` s = indent <> "[ "
                | ", " `T.isPrefixOf` s = indent <> ", "
                | otherwise = indent <> "  "
              name = extractSingleBareString line
              trailingClose = if "]" `T.isSuffixOf` T.stripEnd line then " ]" else ""
           in prefix <> "{ module = \"" <> name <> "\", vars = [] : List { name : Text, value : Text } }" <> trailingClose
      | otherwise = line

    hasBareString line =
      let s = T.strip line
          cleaned = T.dropWhile (\c -> c == '[' || c == ',' || c == ' ') s
       in case T.uncons (T.stripStart cleaned) of
            Just ('"', _) -> not ("{" `T.isInfixOf` s)
            _ -> False

    extractSingleBareString line =
      let s = T.strip line
          cleaned = T.filter (\c -> c /= '[' && c /= ']' && c /= ',') s
          trimmed = T.strip cleaned
       in case T.stripPrefix "\"" trimmed >>= T.stripSuffix "\"" of
            Just name -> name
            Nothing -> trimmed
