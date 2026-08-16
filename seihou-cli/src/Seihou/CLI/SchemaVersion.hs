module Seihou.CLI.SchemaVersion
  ( schemaUrl,
    schemaHash,
    schemaImportLine,
  )
where

import Data.Text (Text)

-- | Raw URL for the seihou-schema package.dhall at a pinned commit
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/49ff1e5b353b171b1b52946f478623ee4423ea93/package.dhall"

-- | SHA256 integrity hash for the schema import
schemaHash :: Text
schemaHash = "sha256:cadacb688dd31ec39feb7f2fe599973a1ad58ef8fcc8ed1100bf3da22a1222cb"

-- | Complete Dhall import line for use in generated modules
schemaImportLine :: Text
schemaImportLine =
  "let S =\n      "
    <> schemaUrl
    <> "\n        "
    <> schemaHash
