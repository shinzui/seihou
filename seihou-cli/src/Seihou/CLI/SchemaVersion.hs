module Seihou.CLI.SchemaVersion
  ( schemaUrl,
    schemaHash,
    schemaImportLine,
  )
where

import Data.Text (Text)

-- | Raw URL for the seihou-schema package.dhall at a pinned commit
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/9080a472d739456b429455c4da167ed8ee36b483/package.dhall"

-- | SHA256 integrity hash for the schema import
schemaHash :: Text
schemaHash = "sha256:251d9e01c4b2987d5d57e8b38d98e97bd0f6216f280ce3418e3e1759a8755532"

-- | Complete Dhall import line for use in generated modules
schemaImportLine :: Text
schemaImportLine =
  "let S =\n      "
    <> schemaUrl
    <> "\n        "
    <> schemaHash
