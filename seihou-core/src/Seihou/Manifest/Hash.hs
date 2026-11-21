module Seihou.Manifest.Hash
  ( hashContent,
    hashBytes,
    baselineRefForContent,
    baselineRefFromText,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isHexDigit)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.Core.Types (BaselineRef (..), SHA256 (..))
import Seihou.Prelude

-- | Compute the SHA256 hash of text content, returning a hex-encoded digest.
-- The text is UTF-8 encoded before hashing.
hashContent :: Text -> SHA256
hashContent = hashBytes . TE.encodeUtf8

hashBytes :: BS.ByteString -> SHA256
hashBytes = SHA256 . TE.decodeUtf8 . Base16.encode . SHA256.hash

-- | Hash generated content into its content-addressed baseline reference.
baselineRefForContent :: Text -> BaselineRef
baselineRefForContent = BaselineRef . hashContent

-- | Validate and normalize a serialized SHA-256 baseline reference. SHA-256
-- references are exactly 64 hexadecimal digits; normalization keeps on-disk
-- filenames canonical even when an older hand-written manifest used uppercase.
baselineRefFromText :: Text -> Maybe BaselineRef
baselineRefFromText value
  | T.length value == 64 && T.all isHexDigit value =
      Just (BaselineRef (SHA256 (T.toLower value)))
  | otherwise = Nothing
