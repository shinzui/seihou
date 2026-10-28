-- | Strict validation before a migration may create a receipt. Unknown fields
-- are compatible; corrupt or incomplete evidence is not.
module Seihou.CLI.AgentMigrationProtocol (validateMigrationOutput) where

import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecodeStrict')
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector qualified as V

validateMigrationOutput :: Bool -> ByteString -> Either Text Text
validateMigrationOutput claude bytes = case validate of
  Left err -> Left (err <> " Inspect partial edits, check provider permissions/protocol support, then retry the same migration.")
  Right body -> Right body
  where
    validate
      | claude = do
          raw <- decodeValue bytes
          value <- case raw of
            Object _ -> Right raw
            Array events | not (V.null events) -> do
              mapM_ checkClaudeEvent (V.toList events)
              Right (V.last events)
            _ -> Left "Claude result is missing."
          require (field "type" value == Just (String "result")) "Claude result is missing."
          require (field "subtype" value == Just (String "success")) ("Claude did not report success. " <> detail value)
          require (field "is_error" value == Just (Bool False)) ("Claude reported an error or omitted is_error. " <> detail value)
          case field "permission_denials" value of
            Just (Array denials) | V.null denials -> pure ()
            _ -> Left ("Claude reported permission denials or omitted permission evidence. " <> detail value)
          textField "result" value >>= nonblank
      | otherwise = do
          events <- traverse decode (filter (not . BS.null) (BS.lines bytes))
          mapM_ checkEvent events
          require (any (\event -> field "type" event == Just (String "turn.completed")) events) "Codex has no successful terminal turn result."
          let messages = [body | event <- events, field "type" event == Just (String "item.completed"), Just item <- [field "item" event], field "type" item == Just (String "agent_message"), Just (String body) <- [field "text" item]]
          nonblank (T.intercalate "\n" messages)
    detail value = case field "result" value of
      Just (String body) -> T.take 2000 body
      _ -> "Check the Claude CLI authentication and configuration."
    checkEvent event = do
      kind <- textField "type" event
      when (kind `elem` ["error", "turn.failed", "permission_denied"]) (Left "Codex reported an error, failed turn, or permission denial.")
      case field "permission_denials" event of
        Nothing -> pure ()
        Just (Array values) | V.null values -> pure ()
        _ -> Left "Codex reported permission denials."
      when (kind `elem` ["item.completed", "item.started", "item.updated"]) $ do
        item <- maybe (Left "Codex item event omitted item.") Right (field "item" event)
        itemKind <- textField "type" item
        when (itemKind == "error" || field "status" item `elem` [Just (String "declined"), Just (String "failed")]) (Left "Codex reported an item error or permission denial.")
        when (kind == "item.completed" && itemKind == "agent_message") $ do
          _ <- textField "text" item
          pure ()
    checkClaudeEvent event = do
      kind <- textField "type" event
      when (kind == "result" && field "subtype" event /= Just (String "success")) (Left "Claude reported a failed result.")
      case field "permission_denials" event of
        Nothing -> pure ()
        Just (Array values) | V.null values -> pure ()
        _ -> Left ("Claude reported permission denials: " <> deniedTools event <> ". " <> detail event)
      when (field "is_error" event == Just (Bool True) || field "type" event == Just (String "error")) (Left "Claude reported an error.")
    deniedTools event = case field "permission_denials" event of
      Just (Array values) -> T.intercalate ", " [name | value <- V.toList values, Just (String name) <- [field "tool_name" value]]
      _ -> "unspecified tool"
    decodeValue raw = case eitherDecodeStrict' raw of
      Left _ -> Left "Malformed migration provider JSON."
      Right value -> Right value
    decode raw = case eitherDecodeStrict' raw of
      Left _ -> Left "Malformed migration provider JSON."
      Right value@(Object _) -> Right value
      Right _ -> Left "Migration provider event must be a JSON object."
    field key (Object object) = KM.lookup key object
    field _ _ = Nothing
    textField key value = case field key value of
      Just (String body) -> Right body
      _ -> Left "Migration provider omitted a required text field."
    require condition err = unless condition (Left err)
    nonblank body = if T.null (T.strip body) then Left "Provider returned no assistant text." else Right body
