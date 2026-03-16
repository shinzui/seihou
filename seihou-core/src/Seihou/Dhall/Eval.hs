module Seihou.Dhall.Eval
  ( evalDhallExpr,
    evalModuleFromFile,
    evalRegistryFromFile,
    moduleDecoder,
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
  )
where

import Control.Exception (SomeException, evaluate, throwIO, try)
import Data.Either.Validation (Validation (..))
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Void (Void)
import Dhall (defaultInputSettings, input, inputExprWithSettings, inputFile, list, record, rootDirectory, sourceName, strictText)
import Dhall.Core (Chunks (..))
import Dhall.Core qualified as Dhall (Expr (..))
import Dhall.Marshal.Decode (Decoder (..), Extractor, bool, field, maybe, string)
import Dhall.Src (Src)
import Seihou.Core.Expr (parseExpr)
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

-- | Decoder for the top-level Module type from Dhall.
moduleDecoder :: Decoder Module
moduleDecoder =
  record
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
    )

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
      -- Caught by 'try' in 'evalModuleFromFile'
      other -> error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section")

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
    parsePatchOp other = error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section")

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
registryEntryDecoder :: Decoder RegistryEntry
registryEntryDecoder =
  record
    ( RegistryEntry
        <$> field "name" moduleNameDecoder
        <*> field "version" (maybe strictText)
        <*> field "path" string
        <*> field "description" (maybe strictText)
        <*> field "tags" (list strictText)
    )

-- | Decoder for a registry metadata file from Dhall.
registryDecoder :: Decoder Registry
registryDecoder =
  record
    ( Registry
        <$> field "repoName" strictText
        <*> field "repoDescription" (maybe strictText)
        <*> field "modules" (list registryEntryDecoder)
    )

-- | Evaluate a @seihou-registry.dhall@ file and decode it into a 'Registry'.
-- Returns 'Left' with a 'RegistryEvalError' if evaluation or decoding fails.
evalRegistryFromFile :: FilePath -> IO (Either ModuleLoadError Registry)
evalRegistryFromFile path = do
  result <- try $ inputFile registryDecoder path
  case result of
    Left (e :: SomeException) ->
      pure $ Left (RegistryEvalError (T.pack path) (T.pack (show e)))
    Right r -> pure (Right r)
