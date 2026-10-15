-- | The raw-byte boundary shared by manifest readers and explicit upgrades.
-- Check multiplicity before Aeson turns object members into a map.
module Seihou.Manifest.JSON (decodeManifestValue) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Decoding.ByteString.Lazy (lbsToTokens)
import Data.Aeson.Decoding.Tokens
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.Set qualified as Set

-- | Reject duplicate keys, including escaped-equivalent spellings, at any depth.
decodeManifestValue :: LBS.ByteString -> Either String Aeson.Value
decodeManifestValue bytes = check (lbsToTokens bytes) >> Aeson.eitherDecode bytes
  where
    check :: Tokens k String -> Either String k
    check (TkLit _ rest) = Right rest
    check (TkText _ rest) = Right rest
    check (TkNumber _ rest) = Right rest
    check (TkErr err) = Left err
    check (TkArrayOpen array) = checkArray array
    check (TkRecordOpen record) = checkRecord Set.empty record
    checkArray (TkItem value) = check value >>= checkArray
    checkArray (TkArrayEnd rest) = Right rest
    checkArray (TkArrayErr err) = Left err
    checkRecord seen (TkPair key value)
      | Set.member key seen = Left ("duplicate manifest JSON key: " <> show (Key.toText key))
      | otherwise = check value >>= checkRecord (Set.insert key seen)
    checkRecord _ (TkRecordEnd rest) = Right rest
    checkRecord _ (TkRecordErr err) = Left err
