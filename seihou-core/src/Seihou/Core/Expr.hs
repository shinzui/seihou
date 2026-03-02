module Seihou.Core.Expr
  ( parseExpr,
    evalExpr,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types

-- | Parse an expression string into an 'Expr' AST.
--
-- Grammar:
--
-- >  expr     = or_expr
-- >  or_expr  = and_expr ("||" and_expr)*
-- >  and_expr = not_expr ("&&" not_expr)*
-- >  not_expr = "!" atom | atom
-- >  atom     = "IsSet" varname
-- >           | "Eq" varname value
-- >           | "(" expr ")"
-- >           | "true" | "false"
-- >  varname  = [a-zA-Z][a-zA-Z0-9._-]*
-- >  value    = quoted_string | bare_word
parseExpr :: Text -> Either Text Expr
parseExpr input =
  let trimmed = T.strip input
   in if T.null trimmed
        then Left "empty expression"
        else case runParser parseOrExpr trimmed of
          Left err -> Left err
          Right (expr, rest)
            | T.null (T.strip rest) -> Right expr
            | otherwise -> Left ("unexpected trailing input: " <> rest)

-- | Evaluate an expression against a map of variable bindings.
evalExpr :: Map VarName VarValue -> Expr -> Bool
evalExpr vars = go
  where
    go (ExprEq name val) = Map.lookup name vars == Just val
    go (ExprAnd l r) = go l && go r
    go (ExprOr l r) = go l || go r
    go (ExprNot e) = not (go e)
    go (ExprIsSet name) = Map.member name vars
    go (ExprLit b) = b

-- Parser internals: a parser consumes text and returns the result plus unconsumed input.
type Parser a = Text -> Either Text (a, Text)

runParser :: Parser a -> Text -> Either Text (a, Text)
runParser = id

parseOrExpr :: Parser Expr
parseOrExpr input = do
  (left, rest) <- parseAndExpr input
  parseOrRest left rest

parseOrRest :: Expr -> Parser Expr
parseOrRest left input =
  let stripped = T.strip input
   in if "||" `T.isPrefixOf` stripped
        then do
          let rest = T.strip (T.drop 2 stripped)
          (right, rest') <- parseAndExpr rest
          parseOrRest (ExprOr left right) rest'
        else Right (left, input)

parseAndExpr :: Parser Expr
parseAndExpr input = do
  (left, rest) <- parseNotExpr input
  parseAndRest left rest

parseAndRest :: Expr -> Parser Expr
parseAndRest left input =
  let stripped = T.strip input
   in if "&&" `T.isPrefixOf` stripped
        then do
          let rest = T.strip (T.drop 2 stripped)
          (right, rest') <- parseNotExpr rest
          parseAndRest (ExprAnd left right) rest'
        else Right (left, input)

parseNotExpr :: Parser Expr
parseNotExpr input =
  let stripped = T.strip input
   in if "!" `T.isPrefixOf` stripped
        then do
          let rest = T.drop 1 stripped
          (e, rest') <- parseNotExpr rest
          Right (ExprNot e, rest')
        else parseAtom stripped

parseAtom :: Parser Expr
parseAtom input =
  let stripped = T.strip input
   in case () of
        _
          | T.null stripped -> Left "unexpected end of input"
          | "true" `T.isPrefixOf` stripped && isAtomEnd (T.drop 4 stripped) ->
              Right (ExprLit True, T.drop 4 stripped)
          | "false" `T.isPrefixOf` stripped && isAtomEnd (T.drop 5 stripped) ->
              Right (ExprLit False, T.drop 5 stripped)
          | "IsSet" `T.isPrefixOf` stripped && isWhitespace (T.drop 5 stripped) -> do
              let rest = T.strip (T.drop 5 stripped)
              (name, rest') <- parseVarName rest
              Right (ExprIsSet (VarName name), rest')
          | "Eq" `T.isPrefixOf` stripped && isWhitespace (T.drop 2 stripped) -> do
              let rest = T.strip (T.drop 2 stripped)
              (name, rest') <- parseVarName rest
              let rest'' = T.strip rest'
              (value, rest''') <- parseValue rest''
              Right (ExprEq (VarName name) value, rest''')
          | T.head stripped == '(' -> do
              let rest = T.strip (T.drop 1 stripped)
              (e, rest') <- parseOrExpr rest
              let rest'' = T.strip rest'
              if not (T.null rest'') && T.head rest'' == ')'
                then Right (e, T.drop 1 rest'')
                else Left "expected closing parenthesis"
          | otherwise -> Left ("unexpected token: " <> T.take 20 stripped)

-- | Check if the character after a keyword is a valid separator (not a varname char).
isAtomEnd :: Text -> Bool
isAtomEnd t = T.null t || not (isVarNameChar (T.head t))

isWhitespace :: Text -> Bool
isWhitespace t = not (T.null t) && T.head t == ' '

parseVarName :: Parser Text
parseVarName input
  | T.null input = Left "expected variable name"
  | not (isVarNameStart (T.head input)) = Left ("expected variable name, got: " <> T.take 10 input)
  | otherwise =
      let (name, rest) = T.span isVarNameChar input
       in Right (name, rest)

isVarNameStart :: Char -> Bool
isVarNameStart c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

isVarNameChar :: Char -> Bool
isVarNameChar c =
  (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c == '.'
    || c == '_'
    || c == '-'

parseValue :: Parser VarValue
parseValue input
  | T.null input = Left "expected value"
  | T.head input == '"' = parseQuotedString (T.drop 1 input)
  | otherwise = parseBareWord input

parseQuotedString :: Parser VarValue
parseQuotedString input =
  case T.breakOn "\"" input of
    (content, rest)
      | T.null rest -> Left "unterminated quoted string"
      | otherwise -> Right (VText content, T.drop 1 rest)

parseBareWord :: Parser VarValue
parseBareWord input =
  let (word, rest) = T.break (\c -> c == ' ' || c == ')' || c == '&' || c == '|') input
   in if T.null word
        then Left "expected value"
        else Right (VText word, rest)
