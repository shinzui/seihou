module Seihou.CLI.SchemaVersion
  ( schemaUrl,
    schemaHash,
    schemaImportLine,
  )
where

import Data.Text (Text)

-- | Raw URL for the seihou-schema package.dhall at a pinned commit
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/6df1496a7ce06a693d8b63bd4cf2c5d4a136670c/package.dhall"

-- | SHA256 integrity hash for the schema import
schemaHash :: Text
schemaHash = "sha256:4946704e8c2dd295179003832428b82273fb0a0cff8eae9282b64ae7e18b89f4"

-- | Complete Dhall import line for use in generated modules
schemaImportLine :: Text
schemaImportLine =
  "let S =\n      "
    <> schemaUrl
    <> "\n        "
    <> schemaHash
