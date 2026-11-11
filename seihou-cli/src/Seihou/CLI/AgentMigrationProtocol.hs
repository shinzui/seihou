-- | Validation of a local agent CLI's raw output, before Seihou accepts the run.
--
-- Two contracts live here. 'validateMigrationOutput' is the strict migration
-- contract (ADR 0019): unknown fields are compatible, but corrupt or incomplete
-- evidence is not. 'validateBatchRunOutput' is the narrower contract for an
-- ordinary batch blueprint run (ADR 0026): it keeps the old acceptance rules and
-- adds only a failure on reported tool refusals.
module Seihou.CLI.AgentMigrationProtocol
  ( validateMigrationOutput,
    validateBatchRunOutput,
    batchRunRefusals,
    renderPermissionDenials,
  )
where

import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecodeStrict')
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS
import Data.List (nub)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
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
        Just (Array values) -> Left ("Claude reported permission denials: " <> renderPermissionDenials (V.toList values) <> ". " <> detail event)
        _ -> Left ("Claude reported permission denials: unspecified tool. " <> detail event)
      when (field "is_error" event == Just (Bool True) || field "type" event == Just (String "error")) (Left "Claude reported an error.")
    decodeValue raw = case eitherDecodeStrict' raw of
      Left _ -> Left "Malformed migration provider JSON."
      Right value -> Right value
    decode raw = case eitherDecodeStrict' raw of
      Left _ -> Left "Malformed migration provider JSON."
      Right value@(Object _) -> Right value
      Right _ -> Left "Migration provider event must be a JSON object."
    textField key value = case field key value of
      Just (String body) -> Right body
      _ -> Left "Migration provider omitted a required text field."
    require condition err = unless condition (Left err)

-- | Validate the stdout of a batch @claude -p --output-format json@ run of an
-- ordinary blueprint. The output is one result object, or (in recent Claude
-- Code versions) a non-empty array of events whose last element is the result.
--
-- The run fails when any event reports a refused tool call, when the result
-- has @is_error: true@, when the output is not JSON, and when the result text
-- is blank. Everything else the older provider accepted is still accepted: a
-- missing @permission_denials@, @type@ or @subtype@ is not an error.
validateBatchRunOutput :: ByteString -> Either Text Text
validateBatchRunOutput bytes = do
  events <- decodeClaudeEvents bytes
  maybe (Right ()) Left (refusalsIn events)
  let result = NE.last events
  when (field "is_error" result == Just (Bool True)) $
    Left ("Claude reported an error: " <> resultDetail result)
  case field "result" result of
    Just (String body) -> nonblank body
    _ -> Left "Provider returned no assistant text."
  where
    resultDetail value = case field "result" value of
      Just (String body) | not (T.null (T.strip body)) -> T.take 2000 body
      _ -> "Claude gave no detail. Check the Claude CLI authentication and configuration, then retry."

-- | The refusal error for a batch run's stdout, when it parses and reports at
-- least one refused tool call. A run that exited non-zero is checked with this
-- first, so the user sees the refusals instead of a bare exit status.
batchRunRefusals :: ByteString -> Maybe Text
batchRunRefusals bytes = either (const Nothing) refusalsIn (decodeClaudeEvents bytes)

refusalsIn :: NonEmpty Value -> Maybe Text
refusalsIn events = case concatMap denialsOf (NE.toList events) of
  [] -> Nothing
  denials ->
    let n = length denials
        noun = if n == 1 then "tool call" else "tool calls"
     in Just $
          "Claude refused "
            <> T.pack (show n)
            <> " "
            <> noun
            <> " during this unattended run: "
            <> renderPermissionDenials denials
            <> ". An unattended run cannot approve tools. Declare the commands the blueprint needs in its allowedTools, or run it interactively, then retry."
  where
    denialsOf event = case field "permission_denials" event of
      Just (Array values) -> V.toList values
      -- A non-array value is still a report of refusal; count it once.
      Just Null -> []
      Just other -> [other]
      Nothing -> []

decodeClaudeEvents :: ByteString -> Either Text (NonEmpty Value)
decodeClaudeEvents bytes = case eitherDecodeStrict' bytes of
  Left _ -> Left "Claude returned output that is not JSON. Check the Claude CLI version and configuration, then retry."
  Right value@(Object _) -> Right (value :| [])
  Right (Array events)
    | all isObject events, Just nonEmpty <- NE.nonEmpty (V.toList events) -> Right nonEmpty
  Right _ -> Left "Claude returned no result object. Check the Claude CLI version and configuration, then retry."
  where
    isObject (Object _) = True
    isObject _ = False

-- | Render reported permission denials as the user would name them:
-- @Bash (nix build .#docs)@, @Write (/repo/.git/x)@, or the bare tool name.
-- Identical entries are listed once, in first-seen order, and the list stops
-- after ten entries with @and N more@.
renderPermissionDenials :: [Value] -> Text
renderPermissionDenials values =
  case nub (map renderOne values) of
    [] -> "unspecified tool"
    rendered ->
      let (shown, rest) = splitAt 10 rendered
       in T.intercalate ", " shown
            <> if null rest then "" else ", and " <> T.pack (show (length rest)) <> " more"
  where
    renderOne value =
      let name = case field "tool_name" value of
            Just (String tool) | not (T.null (T.strip tool)) -> tool
            _ -> "unspecified tool"
       in name <> inputDetail value
    inputDetail value = case firstText ["command", "file_path"] (field "tool_input" value) of
      Just target -> " (" <> T.take 240 target <> ")"
      Nothing -> ""
    firstText keys input = case [t | key <- keys, Just (String t) <- [input >>= field key], not (T.null (T.strip t))] of
      (t : _) -> Just t
      [] -> Nothing

field :: Key -> Value -> Maybe Value
field key (Object object) = KM.lookup key object
field _ _ = Nothing

nonblank :: Text -> Either Text Text
nonblank body = if T.null (T.strip body) then Left "Provider returned no assistant text." else Right body
