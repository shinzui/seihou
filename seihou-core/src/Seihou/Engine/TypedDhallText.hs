-- | Experimental "Prototype B" renderer for the Dhall-as-templating
-- evaluation in @docs/plans/8-evaluate-dhall-as-templating-language.md@.
--
-- Unlike the production 'Seihou.Engine.Plan.compileDhallTextStep',
-- this renderer does __not__ perform Seihou @{{var}}@ placeholder
-- substitution against the raw Dhall source. Instead it treats the
-- source as a typed Dhall function @\(vars : RecordType) -> Text@
-- and applies it to a record literal built from the resolved
-- variable map.
--
-- This module is reachable only from tests — it is intentionally not
-- wired into 'Seihou.Engine.Plan.compileStep' or the 'Strategy' enum.
module Seihou.Engine.TypedDhallText
  ( renderTypedDhallText,
    fieldNameFor,
  )
where

import Control.Exception (SomeException, try)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Dhall qualified
import Seihou.Core.Types
import Seihou.Prelude

-- | Render a Dhall source file that exports a
-- @\\(vars : RecordType) -> Text@ function by applying it to a typed
-- record built from the resolved variable map.
--
-- The caller is responsible for building @Map VarName VarValue@ from
-- variable resolution. The returned 'Text' is the evaluated output of
-- the function.
renderTypedDhallText ::
  -- | Path to the @.dhall@ source file.
  FilePath ->
  -- | Resolved variables to pass to the function.
  Map VarName VarValue ->
  IO (Either Text Text)
renderTypedDhallText srcPath vars = do
  sourceResult <- try (TIO.readFile srcPath)
  case sourceResult of
    Left (e :: SomeException) ->
      pure (Left ("failed to read source: " <> T.pack (show e)))
    Right source -> do
      let record = buildRecordLiteral vars
          -- @(\(vars : ...) -> ...) { field1 = ..., ... }@
          applied = "(" <> source <> ") " <> record
      evalResult <- try (Dhall.input Dhall.strictText applied)
      case evalResult of
        Left (e :: SomeException) ->
          pure (Left ("Dhall evaluation failed: " <> T.pack (show e)))
        Right txt -> pure (Right txt)

-- | Build a Dhall record literal expression (as 'Text') from a variable map.
--
-- Field names are derived from variable names by replacing @.@ with @_@
-- via 'fieldNameFor'. Values are emitted with their natural Dhall syntax:
--
--  * 'VText' -> quoted Dhall @Text@ literal with characters escaped.
--  * 'VBool' -> @True@ or @False@.
--  * 'VInt'  -> Dhall @Integer@ literal (with sign prefix).
--  * 'VList' -> Dhall @List@ with element type inferred from the first
--    element. Empty lists fall back to @List Text@.
buildRecordLiteral :: Map VarName VarValue -> Text
buildRecordLiteral vars
  | Map.null vars = "{=}"
  | otherwise =
      "{ "
        <> T.intercalate
          ", "
          [fieldNameFor name <> " = " <> renderVarValue v | (name, v) <- Map.toList vars]
        <> " }"

-- | Deterministic mapping from 'VarName' to a valid Dhall identifier.
-- Replaces @.@ and @-@ with @_@ to produce a bare identifier usable
-- without backtick quoting.
fieldNameFor :: VarName -> Text
fieldNameFor (VarName n) = T.map fixChar n
  where
    fixChar '.' = '_'
    fixChar '-' = '_'
    fixChar c = c

-- | Render a single 'VarValue' as Dhall source.
renderVarValue :: VarValue -> Text
renderVarValue = \case
  VText t -> renderText t
  VBool True -> "True"
  VBool False -> "False"
  VInt n
    | n >= 0 -> "+" <> T.pack (show n)
    | otherwise -> T.pack (show n)
  VList [] -> "[] : List Text"
  VList vs@(v : _) ->
    "[ " <> T.intercalate ", " (map renderVarValue vs) <> " ] : List " <> dhallTypeOf v

-- | Render a text value as a Dhall double-quoted string literal, escaping
-- @\\@, @"@, and the Dhall interpolation trigger @${@.
renderText :: Text -> Text
renderText t =
  "\""
    <> T.concatMap escapeChar t
    <> "\""
  where
    escapeChar '\\' = "\\\\"
    escapeChar '"' = "\\\""
    escapeChar '\n' = "\\n"
    escapeChar '\t' = "\\t"
    escapeChar '\r' = "\\r"
    escapeChar '$' = "\\$" -- Dhall escape for literal '$' so "${" never forms.
    escapeChar c = T.singleton c

-- | Dhall type name for a single 'VarValue', used when emitting a typed
-- empty list or annotating a non-empty list. Nested lists are not
-- supported by this prototype.
dhallTypeOf :: VarValue -> Text
dhallTypeOf (VText _) = "Text"
dhallTypeOf (VBool _) = "Bool"
dhallTypeOf (VInt _) = "Integer"
dhallTypeOf (VList _) = "Text" -- nested-list fallback; flagged in the evaluation doc.
