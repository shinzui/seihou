module Seihou.Engine.DhallJSON
  ( dhallExprToJSON,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Void (Void)
import Dhall.Core qualified as Dhall
import Dhall.Map qualified as DhallMap
import Dhall.Src (Src)

-- | Convert a normalized Dhall expression to an aeson Value.
-- Supports records, text, naturals, integers, doubles, bools, lists, and optionals.
-- Returns Left with an error message for unsupported expression types.
dhallExprToJSON :: Dhall.Expr Src Void -> Either Text Aeson.Value
dhallExprToJSON = go
  where
    go (Dhall.RecordLit fields) = do
      pairs <- mapM convertField (DhallMap.toList fields)
      pure (Aeson.object pairs)
      where
        convertField (k, rf) = (Key.fromText k,) <$> go (Dhall.recordFieldValue rf)
    go (Dhall.TextLit (Dhall.Chunks [] t)) =
      pure (Aeson.String t)
    go (Dhall.NaturalLit n) =
      pure (Aeson.toJSON n)
    go (Dhall.IntegerLit n) =
      pure (Aeson.toJSON n)
    go (Dhall.DoubleLit (Dhall.DhallDouble d)) =
      pure (Aeson.toJSON d)
    go (Dhall.BoolLit b) =
      pure (Aeson.Bool b)
    go (Dhall.ListLit _ xs) = do
      items <- mapM go (toList xs)
      pure (Aeson.toJSON items)
    go (Dhall.Some e) =
      go e
    go (Dhall.App Dhall.None _) =
      pure Aeson.Null
    go (Dhall.Note _ e) =
      go e
    go expr =
      Left ("Cannot convert Dhall expression to JSON: " <> Dhall.pretty expr)
