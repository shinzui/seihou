module Seihou.Manifest.Hash
  ( hashContent,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Seihou.Core.Types (SHA256 (..))

-- | Compute the SHA256 hash of text content, returning a hex-encoded digest.
-- The text is UTF-8 encoded before hashing.
hashContent :: Text -> SHA256
hashContent t =
  let bytes = TE.encodeUtf8 t
      digest = SHA256.hash bytes
      hex = Base16.encode digest
   in SHA256 (TE.decodeUtf8 hex)
