module Seihou.CLI.SchemaVersion
  ( schemaUrl,
    schemaHash,
    schemaImportLine,
  )
where

import Data.Text (Text)

-- | Raw URL for the seihou-schema package.dhall at a pinned commit
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/d3c78cd81d9697ebff3128732ec673a17e65c73f/package.dhall"

-- | SHA256 integrity hash for the schema import
schemaHash :: Text
schemaHash = "sha256:49297b712cb7fd4b38f3d7c7eb41f34685638e306058913e5129a79157e298aa"

-- | Complete Dhall import line for use in generated modules
schemaImportLine :: Text
schemaImportLine =
  "let S =\n      "
    <> schemaUrl
    <> "\n        "
    <> schemaHash
