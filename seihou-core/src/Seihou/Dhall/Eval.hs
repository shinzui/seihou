module Seihou.Dhall.Eval
  ( evalDhallExpr,
    evalModuleFromFile,
    evalRecipeFromFile,
    evalBlueprintFromFile,
    evalRegistryFromFile,
    moduleDecoder,
    recipeDecoder,
    blueprintDecoder,
    blueprintFileDecoder,
    registryDecoder,
    registryEntryDecoder,
    varTypeDecoder,
    varDeclDecoder,
    varExportDecoder,
    promptDecoder,
    stepDecoder,
    commandDecoder,
    strategyDecoder,
    patchOpDecoder,
    dependencyDecoder,
    removalDecoder,
    removalStepDecoder,
    removalActionDecoder,
    migrationDecoder,
    migrationOpDecoder,
  )
where

import Control.Exception (SomeException, evaluate, throwIO, try)
import Data.Either.Validation (Validation (..))
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Void (Void)
import Dhall (defaultInputSettings, input, inputExprWithSettings, inputFile, list, record, rootDirectory, sourceName, strictText)
import Dhall.Core (Chunks (..), makeRecordField)
import Dhall.Core qualified as Dhall (Expr (..))
import Dhall.Map qualified as DhallMap
import Dhall.Marshal.Decode (Decoder (..), Extractor, bool, constructor, field, maybe, string, union)
import Dhall.Src (Src)
import Seihou.Core.Expr (parseExpr)
import Seihou.Core.Migration (Migration (..), MigrationOp (..))
import Seihou.Core.Registry (Registry (..), RegistryEntry (..))
import Seihou.Core.Types
import Seihou.Prelude
import System.FilePath (takeDirectory)
import Prelude hiding (maybe)

-- | Spike: evaluate a Dhall expression containing a record with @name@ and @version@
-- fields. Returns them as a 'Map'.
evalDhallExpr :: Text -> IO (Map Text Text)
evalDhallExpr expr = do
  (name, version) <- input simpleRecordDecoder expr
  pure (Map.fromList [("name", name), ("version", version)])

simpleRecordDecoder :: Decoder (Text, Text)
simpleRecordDecoder =
  record
    ( (,)
        <$> field "name" strictText
        <*> field "version" strictText
    )

-- | Evaluate a @module.dhall@ file and decode it into a 'Module' value.
-- Returns 'Left' with a 'ModuleLoadError' if evaluation or decoding fails.
--
-- Uses 'inputExprWithSettings' to parse, resolve imports, and normalize the
-- Dhall expression, then extracts with 'moduleDecoder' directly. This
-- bypasses Dhall's type-annotation check, allowing the @dependencies@ field
-- to be either @List Text@ (bare strings) or
-- @List { module : Text, vars : ... }@ (parameterized form) — the custom
-- 'dependencyDecoder' handles both at the AST level.
--
-- Note: Dhall 'Decoder' only supports 'Functor', so decoder helpers like
-- 'parseVarType' use 'error' for invalid input. These 'error' calls produce
-- lazy thunks inside the decoded 'Module'. We force evaluation of all
-- potentially-failing fields inside the 'try' block so that exceptions
-- are caught here rather than propagating as uncaught crashes later.
evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)
evalModuleFromFile path = do
  result <- try $ do
    text <- TIO.readFile path
    let settings =
          set rootDirectory (takeDirectory path) $
            set sourceName path defaultInputSettings
    expr <- inputExprWithSettings settings text
    case extract moduleDecoder expr of
      Success m -> do
        -- Force lazy decoder thunks that may contain 'error' calls
        mapM_ (\v -> evaluate v.type_) m.vars
        mapM_ (\s -> evaluate s.strategy >> evaluate s.condition >> mapM_ evaluate s.patch) m.steps
        mapM_ (\c -> mapM_ evaluate c.condition) m.commands
        mapM_ (\p -> evaluate p.condition) m.prompts
        pure m
      Failure e -> throwIO e
  case result of
    Left (e :: SomeException) ->
      let name = guessModuleName path
       in pure $ Left (DhallEvalError name (T.pack (show e)))
    Right m -> pure (Right m)

-- | Evaluate a @recipe.dhall@ file and decode it into a 'Recipe' value.
-- Returns 'Left' with a 'ModuleLoadError' if evaluation or decoding fails.
--
-- Follows the same pattern as 'evalModuleFromFile': uses
-- 'inputExprWithSettings' to parse and normalize, then extracts with
-- 'recipeDecoder'. The recipe's @modules@ field reuses 'dependencyDecoder'.
evalRecipeFromFile :: FilePath -> IO (Either ModuleLoadError Recipe)
evalRecipeFromFile path = do
  result <- try $ do
    text <- TIO.readFile path
    let settings =
          set rootDirectory (takeDirectory path) $
            set sourceName path defaultInputSettings
    expr <- inputExprWithSettings settings text
    case extract recipeDecoder expr of
      Success r -> do
        -- Force lazy decoder thunks that may contain 'error' calls
        mapM_ (\v -> evaluate v.type_) r.vars
        mapM_ (\p -> evaluate p.condition) r.prompts
        pure r
      Failure e -> throwIO e
  case result of
    Left (e :: SomeException) ->
      let name = guessModuleName path
       in pure $ Left (DhallEvalError name (T.pack (show e)))
    Right r -> pure (Right r)

-- | Guess a module name from its file path by taking the parent directory name.
guessModuleName :: FilePath -> ModuleName
guessModuleName path =
  let parts = T.splitOn "/" (T.pack path)
   in case parts of
        [] -> ModuleName "<unknown>"
        [_] -> ModuleName "<unknown>"
        _ ->
          let parentDir = parts !! (length parts - 2)
           in ModuleName parentDir

-- | Wrap a decoder to inject default values for missing record fields.
-- For each @(key, defaultExpr)@, if the key is absent from a 'RecordLit',
-- it is added with the given Dhall expression before extraction.
-- This allows decoders to handle schema evolution gracefully.
withDefaults :: [(Text, Dhall.Expr Src Void)] -> Decoder a -> Decoder a
withDefaults defaults (Decoder ext exp_) = Decoder ext' exp_
  where
    ext' expr@(Dhall.RecordLit fields) =
      let fields' = foldl' addDefault fields defaults
       in ext (Dhall.RecordLit fields')
    ext' expr = ext expr

    addDefault fs (k, v) =
      case DhallMap.lookup k fs of
        Just _ -> fs
        Nothing -> DhallMap.insert k (makeRecordField v) fs

-- | A Dhall expression representing @None Text@.
-- Used as a placeholder default for missing @Optional@-typed fields.
noneText :: Dhall.Expr Src Void
noneText = Dhall.App Dhall.None Dhall.Text

-- | Decoder for the top-level Module type from Dhall.
-- Uses 'withDefaults' to handle modules that predate the @removal@ and
-- @migrations@ fields.
moduleDecoder :: Decoder Module
moduleDecoder =
  withDefaults
    [ ("removal", noneText),
      ("migrations", emptyMigrationList)
    ]
    $ record
      ( Module
          <$> field "name" moduleNameDecoder
          <*> field "version" (maybe strictText)
          <*> field "description" (maybe strictText)
          <*> field "vars" (list varDeclDecoder)
          <*> field "exports" (list varExportDecoder)
          <*> field "prompts" (list promptDecoder)
          <*> field "steps" (list stepDecoder)
          <*> field "commands" (list commandDecoder)
          <*> field "dependencies" (list dependencyDecoder)
          <*> field "removal" (maybe removalDecoder)
          <*> field "migrations" (list migrationDecoder)
      )

-- | A Dhall expression representing an empty list of Migration records.
-- The list element type annotation is unused by the list extractor (which
-- ignores the annotation and reads element values), so we use a placeholder
-- type to keep the synthesized expression compact.
emptyMigrationList :: Dhall.Expr Src Void
emptyMigrationList = Dhall.ListLit (Just Dhall.Text) mempty

-- | Decoder for a single 'Migration' record.
migrationDecoder :: Decoder Migration
migrationDecoder =
  record
    ( Migration
        <$> field "from" strictText
        <*> field "to" strictText
        <*> field "ops" (list migrationOpDecoder)
    )

-- | Decoder for a 'MigrationOp' from a Dhall union value.
-- The union variants must match @schema/MigrationOp.dhall@.
migrationOpDecoder :: Decoder MigrationOp
migrationOpDecoder =
  union
    ( (mkMoveFile <$> constructor "MoveFile" srcDestRecord)
        <> (mkMoveDir <$> constructor "MoveDir" srcDestRecord)
        <> (mkDeleteFile <$> constructor "DeleteFile" pathRecord)
        <> (mkDeleteDir <$> constructor "DeleteDir" pathRecord)
        <> (mkRunCommand <$> constructor "RunCommand" runCommandRecord)
    )
  where
    srcDestRecord :: Decoder (FilePath, FilePath)
    srcDestRecord =
      record ((,) <$> field "src" string <*> field "dest" string)

    pathRecord :: Decoder FilePath
    pathRecord = record (field "path" string)

    runCommandRecord :: Decoder (Text, Maybe FilePath)
    runCommandRecord =
      record ((,) <$> field "run" strictText <*> field "workDir" (maybe string))

    mkMoveFile (s, d) = MoveFile {src = s, dest = d}
    mkMoveDir (s, d) = MoveDir {src = s, dest = d}
    mkDeleteFile p = DeleteFile {path = p}
    mkDeleteDir p = DeleteDir {path = p}
    mkRunCommand (r, wd) = RunCommand {run = r, workDir = wd}

-- | Decoder for the top-level Recipe type from Dhall.
recipeDecoder :: Decoder Recipe
recipeDecoder =
  record
    ( Recipe
        <$> field "name" recipeNameDecoder
        <*> field "version" (maybe strictText)
        <*> field "description" (maybe strictText)
        <*> field "modules" (list dependencyDecoder)
        <*> field "vars" (list varDeclDecoder)
        <*> field "prompts" (list promptDecoder)
    )

recipeNameDecoder :: Decoder RecipeName
recipeNameDecoder = RecipeName <$> strictText

-- | Decoder for a 'BlueprintFile' record. The @src@ is a path relative
-- to the blueprint's @files/@ directory; the optional @description@ is
-- shown to the agent so it can pick the right reference.
blueprintFileDecoder :: Decoder BlueprintFile
blueprintFileDecoder =
  record
    ( BlueprintFile
        <$> field "src" string
        <*> field "description" (maybe strictText)
    )

-- | Decoder for the top-level Blueprint type from Dhall.
blueprintDecoder :: Decoder Blueprint
blueprintDecoder =
  record
    ( Blueprint
        <$> field "name" moduleNameDecoder
        <*> field "version" (maybe strictText)
        <*> field "description" (maybe strictText)
        <*> field "prompt" strictText
        <*> field "vars" (list varDeclDecoder)
        <*> field "prompts" (list promptDecoder)
        <*> field "baseModules" (list dependencyDecoder)
        <*> field "files" (list blueprintFileDecoder)
        <*> field "allowedTools" (maybe (list strictText))
        <*> field "tags" (list strictText)
    )

-- | Evaluate a @blueprint.dhall@ file and decode it into a 'Blueprint'.
-- Returns 'Left' with a 'ModuleLoadError' if evaluation or decoding fails.
--
-- Follows the same pattern as 'evalModuleFromFile' / 'evalRecipeFromFile':
-- uses 'inputExprWithSettings' to parse and normalize, then extracts with
-- 'blueprintDecoder' and forces lazy decoder thunks so 'error' calls in
-- the inner decoders are caught here rather than escaping later.
evalBlueprintFromFile :: FilePath -> IO (Either ModuleLoadError Blueprint)
evalBlueprintFromFile path = do
  result <- try $ do
    text <- TIO.readFile path
    let settings =
          set rootDirectory (takeDirectory path) $
            set sourceName path defaultInputSettings
    expr <- inputExprWithSettings settings text
    case extract blueprintDecoder expr of
      Success b -> do
        mapM_ (\v -> evaluate v.type_) b.vars
        mapM_ (\p -> evaluate p.condition) b.prompts
        pure b
      Failure e -> throwIO e
  case result of
    Left (e :: SomeException) ->
      let nm = guessModuleName path
       in pure $ Left (DhallEvalError nm (T.pack (show e)))
    Right b -> pure (Right b)

-- | Decoder for Removal from a Dhall record.
removalDecoder :: Decoder Removal
removalDecoder =
  record
    ( Removal
        <$> field "steps" (list removalStepDecoder)
        <*> field "commands" (list commandDecoder)
    )

-- | Decoder for RemovalStep from a Dhall record.
removalStepDecoder :: Decoder RemovalStep
removalStepDecoder =
  record
    ( RemovalStep
        <$> field "action" removalActionDecoder
        <*> field "dest" strictText
        <*> field "src" (maybe string)
    )

-- | Decoder for RemovalAction from a Dhall Text string.
--
-- See 'varTypeDecoder' note re: 'error' safety.
removalActionDecoder :: Decoder RemovalAction
removalActionDecoder = parseRemovalAction <$> strictText
  where
    parseRemovalAction :: Text -> RemovalAction
    parseRemovalAction t = case t of
      "remove-file" -> RemoveFileAction
      "remove-section" -> RemoveSectionAction
      "rewrite-file" -> RewriteFileAction
      -- Caught by 'try' in 'evalModuleFromFile'
      other -> error ("Unknown removal action \"" <> T.unpack other <> "\"; expected one of: remove-file, remove-section, rewrite-file")

moduleNameDecoder :: Decoder ModuleName
moduleNameDecoder = ModuleName <$> strictText

-- | Decoder for a dependency entry.
-- Accepts two Dhall forms for backward compatibility:
--
-- 1. A bare text string: @"base"@ decodes as @Dependency "base" mempty@.
-- 2. A record: @{ module = "base", vars = [ { name = "x", value = "y" } ] }@
--    decodes as @Dependency "base" (fromList [("x", "y")])@.
--
-- This is implemented as a custom decoder that pattern-matches on the Dhall
-- expression AST: 'TextLit' for bare strings, falling back to the record
-- decoder for the parameterized form.
dependencyDecoder :: Decoder Dependency
dependencyDecoder = Decoder extractDep expectedDep
  where
    extractDep :: Dhall.Expr Src Void -> Extractor Src Void Dependency
    extractDep (Dhall.TextLit (Chunks [] t)) =
      pure (simpleDep (ModuleName t))
    extractDep expr =
      extract paramDepDecoder expr

    expectedDep = expected strictText

    paramDepDecoder :: Decoder Dependency
    paramDepDecoder =
      record
        ( mkDep
            <$> field "module" moduleNameDecoder
            <*> field "vars" (list varBindingDecoder)
        )

    varBindingDecoder :: Decoder (VarName, Text)
    varBindingDecoder =
      record
        ( (,)
            <$> field "name" varNameDecoder
            <*> field "value" strictText
        )

    mkDep :: ModuleName -> [(VarName, Text)] -> Dependency
    mkDep name bindings = Dependency {depModule = name, depVars = Map.fromList bindings}

-- | Decoder for VarType from a Dhall Text string.
-- Dhall does not support recursive types, so VarType is represented as a
-- string: @"text"@, @"bool"@, @"int"@, @"list text"@, @"list bool"@,
-- @"list int"@, @"choice"@.
--
-- Note: 'Decoder' only has a 'Functor' instance (no 'Monad'/'MonadFail'), so
-- we cannot use @fail@ for error reporting. The 'error' call throws an
-- 'ErrorCall' exception that is caught by @try@ in 'evalModuleFromFile' and
-- wrapped as @Left (DhallEvalError ...)@.
varTypeDecoder :: Decoder VarType
varTypeDecoder = parseVarType <$> strictText
  where
    parseVarType :: Text -> VarType
    parseVarType t = case T.toLower t of
      "text" -> VTText
      "bool" -> VTBool
      "int" -> VTInt
      "choice" -> VTChoice []
      other
        | "list " `T.isPrefixOf` other ->
            VTList (parseVarType (T.drop 5 other))
        | otherwise ->
            -- Caught by 'try' in 'evalModuleFromFile'
            error ("Unknown var type \"" <> T.unpack other <> "\"; expected one of: text, bool, int, choice, list <type>")

-- | Decoder for Strategy from a Dhall Text string.
--
-- See 'varTypeDecoder' note re: 'error' safety.
strategyDecoder :: Decoder Strategy
strategyDecoder = parseStrategy <$> strictText
  where
    parseStrategy :: Text -> Strategy
    parseStrategy t = case t of
      "copy" -> Copy
      "template" -> Template
      "dhall-text" -> DhallText
      "structured" -> Structured
      -- Caught by 'try' in 'evalModuleFromFile'
      other -> error ("Unknown strategy \"" <> T.unpack other <> "\"; expected one of: copy, template, dhall-text, structured")

-- | Decoder for VarDecl from a Dhall record.
varDeclDecoder :: Decoder VarDecl
varDeclDecoder =
  record
    ( VarDecl
        <$> field "name" varNameDecoder
        <*> field "type" varTypeDecoder
        <*> field "default" (fmap (fmap VText) (maybe strictText))
        <*> field "description" (maybe strictText)
        <*> field "required" bool
        <*> field "validation" (fmap (fmap ValPattern) (maybe strictText))
    )

varNameDecoder :: Decoder VarName
varNameDecoder = VarName <$> strictText

-- | Decoder for VarExport from a Dhall record.
-- Note: the Dhall field is @alias@ rather than @as@ because @as@ is a
-- reserved keyword in Dhall.
varExportDecoder :: Decoder VarExport
varExportDecoder =
  record
    ( VarExport
        <$> field "var" varNameDecoder
        <*> field "alias" (fmap (fmap VarName) (maybe strictText))
    )

-- | Decoder for Prompt from a Dhall record.
-- The @when@ field is parsed via 'parseExpr' into an 'Expr' AST.
-- Parse failures are treated as fatal (via 'error') since they indicate a
-- malformed module definition.
promptDecoder :: Decoder Prompt
promptDecoder =
  record
    ( mkPrompt
        <$> field "var" varNameDecoder
        <*> field "text" strictText
        <*> field "when" (maybe strictText)
        <*> field "choices" (maybe (list strictText))
    )
  where
    mkPrompt v t whenText choices =
      Prompt
        { var = v,
          text = t,
          condition = parseWhen whenText,
          choices = choices
        }

-- | Decoder for PatchOp from a Dhall Text string.
--
-- See 'varTypeDecoder' note re: 'error' safety.
patchOpDecoder :: Decoder PatchOp
patchOpDecoder = parsePatchOp <$> strictText
  where
    parsePatchOp :: Text -> PatchOp
    parsePatchOp t = case t of
      "append-file" -> AppendFile
      "prepend-file" -> PrependFile
      "append-section" -> AppendSection
      "append-line-if-absent" -> AppendLineIfAbsent
      -- Caught by 'try' in 'evalModuleFromFile'
      other -> error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section, append-line-if-absent")

-- | Decoder for Step from a Dhall record.
-- The @when@ field is parsed via 'parseExpr' into an 'Expr' AST.
-- The @patch@ field is an optional patch operation string.
stepDecoder :: Decoder Step
stepDecoder =
  record
    ( mkStep
        <$> field "strategy" strategyDecoder
        <*> field "src" string
        <*> field "dest" strictText
        <*> field "when" (maybe strictText)
        <*> field "patch" (maybe strictText)
    )
  where
    mkStep strat src dest whenText patchText =
      Step
        { strategy = strat,
          src = src,
          dest = dest,
          condition = parseWhen whenText,
          patch = fmap parsePatchOp patchText
        }
    parsePatchOp "append-file" = AppendFile
    parsePatchOp "prepend-file" = PrependFile
    parsePatchOp "append-section" = AppendSection
    parsePatchOp "append-line-if-absent" = AppendLineIfAbsent
    parsePatchOp other = error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section, append-line-if-absent")

-- | Decoder for Command from a Dhall record.
-- The @when@ field is parsed via 'parseExpr' into an 'Expr' AST.
commandDecoder :: Decoder Command
commandDecoder =
  record
    ( mkCommand
        <$> field "run" strictText
        <*> field "workDir" (maybe strictText)
        <*> field "when" (maybe strictText)
    )
  where
    mkCommand run workDir whenText =
      Command
        { run = run,
          workDir = workDir,
          condition = parseWhen whenText
        }

-- | Parse an optional @when@ expression text into an 'Expr'.
-- Returns 'Nothing' for 'Nothing' input, 'Just expr' on success, or calls
-- 'error' on a malformed expression. The 'error' is caught by @try@ in
-- 'evalModuleFromFile' (see 'varTypeDecoder' note).
parseWhen :: Maybe Text -> Maybe Expr
parseWhen Nothing = Nothing
parseWhen (Just t) = case parseExpr t of
  Right expr -> Just expr
  -- Caught by 'try' in 'evalModuleFromFile'
  Left err -> error ("Invalid when expression \"" <> T.unpack t <> "\": " <> T.unpack err)

-- | Decoder for a single registry entry from a Dhall record.
-- Uses 'withDefaults' to handle registries that omit the @version@ field.
registryEntryDecoder :: Decoder RegistryEntry
registryEntryDecoder =
  withDefaults [("version", noneText)] $
    record
      ( RegistryEntry
          <$> field "name" moduleNameDecoder
          <*> field "version" (maybe strictText)
          <*> field "path" string
          <*> field "description" (maybe strictText)
          <*> field "tags" (list strictText)
      )

-- | Decoder for a registry metadata file from Dhall.
-- Uses 'withDefaults' to handle registries that omit the @recipes@ field
-- (backwards compatibility with existing seihou-registry.dhall files).
registryDecoder :: Decoder Registry
registryDecoder =
  withDefaults [("recipes", emptyRegistryEntryList)] $
    record
      ( Registry
          <$> field "repoName" strictText
          <*> field "repoDescription" (maybe strictText)
          <*> field "modules" (list registryEntryDecoder)
          <*> field "recipes" (list registryEntryDecoder)
      )

-- | A Dhall expression representing an empty list of registry entries.
-- Used as a default for the @recipes@ field in registries that predate recipe support.
emptyRegistryEntryList :: Dhall.Expr Src Void
emptyRegistryEntryList =
  Dhall.ListLit
    ( Just
        ( Dhall.Record
            ( DhallMap.fromList
                [ ("name", makeRecordField Dhall.Text),
                  ("version", makeRecordField (Dhall.App Dhall.Optional Dhall.Text)),
                  ("path", makeRecordField Dhall.Text),
                  ("description", makeRecordField (Dhall.App Dhall.Optional Dhall.Text)),
                  ("tags", makeRecordField (Dhall.App Dhall.List Dhall.Text))
                ]
            )
        )
    )
    mempty

-- | Evaluate a @seihou-registry.dhall@ file and decode it into a 'Registry'.
-- Returns 'Left' with a 'RegistryEvalError' if evaluation or decoding fails.
--
-- Uses 'inputExprWithSettings' to parse, resolve imports, and normalize the
-- Dhall expression, then extracts with 'registryDecoder' directly. This
-- bypasses Dhall's type-annotation check, allowing registry entries to omit
-- optional fields like @version@ — the custom 'registryEntryDecoder' handles
-- missing fields at the AST level.
evalRegistryFromFile :: FilePath -> IO (Either ModuleLoadError Registry)
evalRegistryFromFile path = do
  result <- try $ do
    text <- TIO.readFile path
    let settings =
          set rootDirectory (takeDirectory path) $
            set sourceName path defaultInputSettings
    expr <- inputExprWithSettings settings text
    case extract registryDecoder expr of
      Success r -> pure r
      Failure e -> throwIO e
  case result of
    Left (e :: SomeException) ->
      pure $ Left (RegistryEvalError (T.pack path) (T.pack (show e)))
    Right r -> pure (Right r)
