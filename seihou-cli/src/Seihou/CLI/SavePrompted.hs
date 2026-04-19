module Seihou.CLI.SavePrompted
  ( collectPromptedValues,
    offerSavePrompted,
  )
where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Composition.Instance (ModuleInstance)
import Seihou.Core.Types
import Seihou.Effect.ConfigWriter (ConfigWriter, writeConfigValue)
import Seihou.Effect.Console (Console, confirm, putText)
import Seihou.Prelude

-- | Collect variables resolved via interactive prompts that are not already
-- in local config with the same value. Returns triples of (variable name,
-- prompted text value, Just existingValue if overwriting).
collectPromptedValues ::
  Map ModuleInstance (Map VarName ResolvedVar) ->
  Map VarName Text ->
  [(VarName, Text, Maybe Text)]
collectPromptedValues resolved localConfig =
  let allPrompted =
        Map.toAscList $
          Map.unions
            [ Map.mapMaybe promptedOnly vs
            | vs <- Map.elems resolved
            ]
      promptedOnly rv =
        case rv.source of
          FromPrompt -> Just (varValueToText rv.value)
          _ -> Nothing
   in [ (vn, val, existing)
      | (vn, val) <- allPrompted,
        let existing = Map.lookup vn localConfig,
        existing /= Just val
      ]

-- | Offer to save prompted values to local config.
-- Nothing = ask interactively, Just True = auto-save, Just False = skip.
offerSavePrompted ::
  (Console :> es, ConfigWriter :> es) =>
  Maybe Bool ->
  Bool ->
  [(VarName, Text, Maybe Text)] ->
  Eff es ()
offerSavePrompted (Just False) _ _ = pure ()
offerSavePrompted _ _ [] = pure ()
offerSavePrompted mode interactive entries = do
  let shouldSave = case mode of
        Just True -> pure True
        _ | not interactive -> pure False
        _ -> do
          putText ""
          putText "Save prompted values to .seihou/config.dhall?"
          putText ""
          mapM_
            ( \(VarName n, val, mExisting) -> do
                let overwriteNote = case mExisting of
                      Just old -> "  (overwrites current: \"" <> old <> "\")"
                      Nothing -> ""
                putText ("  " <> n <> " = \"" <> val <> "\"" <> overwriteNote)
            )
            entries
          putText ""
          confirm "Save? [Y/n]"
  doSave <- shouldSave
  when doSave $ do
    mapM_
      ( \(VarName n, val, _) ->
          writeConfigValue ScopeLocal n val
      )
      entries
    putText $ "Saved " <> T.pack (show (length entries)) <> " value(s) to .seihou/config.dhall"
    putText "Use 'seihou config list' to view or 'seihou config unset <key>' to remove."

-- | Convert a VarValue to its text representation.
varValueToText :: VarValue -> Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)
