-- | Publish a receipt against the document the provider left on disk. Keep
-- unrelated JSON members, including producer fields unknown to this binary.
module Seihou.CLI.AppliedBlueprint
  ( recordAppliedBlueprint,
    updateReceiptDocument,
    preflightPolicyReceipt,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (void)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Types
import Seihou.Manifest.JSON (decodeManifestValue)
import Seihou.Manifest.Types (blueprintToJSON, emptyManifest, minimumManifestVersion)
import Seihou.Manifest.Upgrade (renderManifestUpgradeError, upgradeDocumentLosslessly)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, renameFile)
import System.FilePath (takeDirectory)
import System.IO (hClose)
import System.IO.Error (isDoesNotExistError)
import System.IO.Temp (withTempFile)

-- Reading a v5 manifest still requires reviewed origin conversion. Validate
-- before transforming so forged evidence cannot be legalized by an upgrade.
readReceiptDocument :: Bool -> FilePath -> IO (Either Text (Maybe (Manifest, Aeson.Object)))
readReceiptDocument upgrade path = do
  bytes <- try @IOException (BS.readFile path)
  pure $ case bytes of
    Left err | isDoesNotExistError err -> Right Nothing
    Left err -> Left (T.pack (displayException err))
    Right raw -> do
      original <- first T.pack (decodeManifestValue (LBS.fromStrict raw))
      previous <- typed original
      (manifest, prepared) <-
        if upgrade && previous ^. #version < minimumManifestVersion CallerToolPolicyEvidence
          then do
            (_, doc) <- first renderManifestUpgradeError (upgradeDocumentLosslessly (minimumManifestVersion CallerToolPolicyEvidence) original)
            (,doc) <$> typed doc
          else Right (previous, original)
      case prepared of
        Aeson.Object fields -> Right (Just (manifest, fields))
        _ -> Left "Manifest must be a JSON object."
  where
    typed doc = case Aeson.fromJSON doc of
      Aeson.Success manifest -> Right manifest
      Aeson.Error err -> Left (T.pack err)

preflightPolicyReceipt :: FilePath -> IO (Either Text ())
preflightPolicyReceipt path = void <$> readReceiptDocument True path

recordAppliedBlueprint :: FilePath -> AppliedBlueprint -> IO (Either Text ())
recordAppliedBlueprint path receipt =
  updateReceiptDocument path (receipt ^. #appliedAt) (isJust (receipt ^. #callerToolPolicy)) $ \manifest fields ->
    KM.insert "blueprint" (blueprintToJSON (manifest ^. #version) receipt) fields

updateReceiptDocument :: FilePath -> UTCTime -> Bool -> (Manifest -> Aeson.Object -> Aeson.Object) -> IO (Either Text ())
updateReceiptDocument path now upgrade update = do
  attempt <- try @IOException $ do
    current <- readReceiptDocument upgrade path
    case current of
      Left err -> pure (Left err)
      Right existing -> do
        let fresh = emptyManifest now
            initial = case Aeson.toJSON fresh of Aeson.Object o -> o; _ -> mempty
            (manifest, fields) = maybe (fresh, initial) id existing
            dir = takeDirectory path
        createDirectoryIfMissing True dir
        withTempFile dir "manifest.json.tmp" $ \temporary handle -> do
          LBS.hPut handle (Aeson.encode (Aeson.Object (update manifest fields)))
          hClose handle
          renameFile temporary path
        pure (Right ())
  pure (either (Left . T.pack . displayException) id attempt)
