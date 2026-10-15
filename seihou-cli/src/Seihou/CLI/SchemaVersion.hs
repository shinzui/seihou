module Seihou.CLI.SchemaVersion
  ( schemaUrl,
    schemaHash,
    schemaImportLine,
  )
where

import Data.Text (Text)

-- | Raw URL for the seihou-schema package.dhall at a pinned commit
schemaUrl :: Text
schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/1d686cf9e3019cec061c1f4a4d83be53cb606e8b/package.dhall"

-- | SHA256 integrity hash for the schema import
schemaHash :: Text
schemaHash = "sha256:ef20d62c240dfe0e1126e05534d58c467188af4198307ad3c2a4a713bcd93505"

-- | Complete Dhall import line for use in generated modules
schemaImportLine :: Text
schemaImportLine =
  "let S =\n      "
    <> schemaUrl
    <> "\n        "
    <> schemaHash
