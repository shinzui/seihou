module Seihou.Core.Version
  ( Version (..),
    parseVersion,
    renderVersion,
  )
where

import Data.Text qualified as T
import GHC.Generics (Generic)
import Numeric.Natural (Natural)
import Seihou.Prelude

-- | A parsed version consisting of numeric segments (e.g. @[1, 2, 3]@ for "1.2.3").
newtype Version = Version {segments :: [Natural]}
  deriving stock (Show, Generic)

instance Eq Version where
  Version a == Version b =
    let maxLen = max (length a) (length b)
     in pad maxLen a == pad maxLen b

instance Ord Version where
  compare (Version a) (Version b) =
    let maxLen = max (length a) (length b)
     in compare (pad maxLen a) (pad maxLen b)

-- | Pad a list of naturals with trailing zeros to the given length.
pad :: Int -> [Natural] -> [Natural]
pad n xs = xs ++ replicate (n - length xs) 0

-- | Parse a dotted version string like @"1.2.3"@ into a 'Version'.
-- Returns 'Nothing' for empty strings or strings with non-numeric segments.
parseVersion :: Text -> Maybe Version
parseVersion t
  | T.null t = Nothing
  | otherwise =
      let parts = T.splitOn "." t
       in case traverse readNatural parts of
            Just ns@(_ : _) -> Just (Version ns)
            _ -> Nothing

-- | Try to read a 'Natural' from a 'Text' value.
readNatural :: Text -> Maybe Natural
readNatural t = case reads (T.unpack t) of
  [(n, "")] | (n :: Integer) >= 0 -> Just (fromIntegral n)
  _ -> Nothing

-- | Render a 'Version' back to dotted notation.
renderVersion :: Version -> Text
renderVersion (Version ns) = T.intercalate "." (map (T.pack . show) ns)
