-- | Smoke test that seihou can call the okf-core authoring API.
--
-- This module exists only to make the okf-core build wiring (EP-56) observable:
-- if it compiles and 'okfSmoke' evaluates, seihou code can use okf-core. It is
-- replaced by the real documentation renderer in EP-58
-- (@docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md@).
module Seihou.CLI.Docs.Smoke
  ( okfSmoke,
  )
where

import Data.Text (Text)
import Okf.Document (OKFDocument (..), emptyFrontmatter, serializeDocument)

-- | A serialized empty-frontmatter OKF document, proving okf-core is reachable.
okfSmoke :: Text
okfSmoke = serializeDocument (OKFDocument emptyFrontmatter "# smoke\n")
