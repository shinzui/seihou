module Seihou.Core.Install
  ( parseModuleName,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

-- | Parse a module name from a git URL by extracting the last path segment
-- and stripping a trailing .git extension.
parseModuleName :: Text -> String
parseModuleName url =
  let stripped = T.stripSuffix ".git" url
      base = maybe url id stripped
      segments = T.splitOn "/" base
      lastSeg = if null segments then base else last segments
   in T.unpack lastSeg
