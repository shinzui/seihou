module Seihou.Dhall.Eval
  ( evalDhallExpr,
    evalModuleFromFile,
    moduleDecoder,
    varTypeDecoder,
    varDeclDecoder,
    varExportDecoder,
    promptDecoder,
    stepDecoder,
    strategyDecoder,
  )
where

import Control.Exception (SomeException, try)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Dhall (Decoder, input, inputFile, list, record, strictText)
import Dhall.Marshal.Decode (bool, field, maybe, string)
import Seihou.Core.Expr (parseExpr)
import Seihou.Core.Types
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
evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)
evalModuleFromFile path = do
  result <- try (inputFile moduleDecoder path)
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
        <*> field "description" (maybe strictText)
        <*> field "vars" (list varDeclDecoder)
        <*> field "exports" (list varExportDecoder)
        <*> field "prompts" (list promptDecoder)
        <*> field "steps" (list stepDecoder)
        <*> field "dependencies" (list moduleNameDecoder)
    )

moduleNameDecoder :: Decoder ModuleName
moduleNameDecoder = ModuleName <$> strictText

-- | Decoder for VarType from a Dhall Text string.
-- Dhall does not support recursive types, so VarType is represented as a
-- string: @"text"@, @"bool"@, @"int"@, @"list text"@, @"list bool"@,
-- @"list int"@, @"choice"@.
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
            error ("Unknown VarType: " <> T.unpack other)

-- | Decoder for Strategy from a Dhall Text string.
strategyDecoder :: Decoder Strategy
strategyDecoder = parseStrategy <$> strictText
  where
    parseStrategy :: Text -> Strategy
    parseStrategy t = case t of
      "copy" -> Copy
      "template" -> Template
      "dhall-text" -> DhallText
      "structured" -> Structured
      other -> error ("Unknown strategy: " <> T.unpack other)

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
        { promptVar = v,
          promptText = t,
          promptWhen = parseWhen whenText,
          promptChoices = choices
        }

-- | Decoder for Step from a Dhall record.
-- The @when@ field is parsed via 'parseExpr' into an 'Expr' AST.
stepDecoder :: Decoder Step
stepDecoder =
  record
    ( mkStep
        <$> field "strategy" strategyDecoder
        <*> field "src" string
        <*> field "dest" strictText
        <*> field "when" (maybe strictText)
    )
  where
    mkStep strat src dest whenText =
      Step
        { stepStrategy = strat,
          stepSrc = src,
          stepDest = dest,
          stepWhen = parseWhen whenText
        }

-- | Parse an optional @when@ expression text into an 'Expr'.
-- Returns 'Nothing' for 'Nothing' input, 'Just expr' on success, or calls
-- 'error' on a malformed expression (indicating a bug in the module definition).
parseWhen :: Maybe Text -> Maybe Expr
parseWhen Nothing = Nothing
parseWhen (Just t) = case parseExpr t of
  Right expr -> Just expr
  Left err -> error ("Invalid when expression: " <> T.unpack err <> " in: " <> T.unpack t)
