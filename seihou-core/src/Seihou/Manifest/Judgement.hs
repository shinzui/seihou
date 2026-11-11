-- | The manifest encoding of judgement definitions and judgement policy.
--
-- The encoding is Seihou's own and is versioned by the manifest schema
-- (introduced in schema 15). No provider, Shikumi or transport type appears
-- in it: thresholds are plain numbers, enumerations are stable kebab-case
-- strings, and every key is always written so a diff is reviewable.
--
-- 'definitionDigest' hashes the canonical encoding of a definition, so the
-- digest identifies exactly the reviewed definition independently of the
-- Dhall source it was decoded from.
module Seihou.Manifest.Judgement
  ( definitionToJSON,
    parseDefinition,
    policyToJSON,
    parsePolicy,
    definitionDigest,
  )
where

import Control.Monad (forM_, unless)
import Data.Aeson (Value, object, withObject, (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Parser)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.Core.Judgement
import Seihou.Core.Types (SHA256)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude hiding ((.=))

-- | SHA-256 of the canonical encoding. Aeson writes object keys in sorted
-- order, so the bytes do not depend on construction order.
definitionDigest :: JudgementDefinition -> SHA256
definitionDigest = hashContent . TE.decodeUtf8 . LBS.toStrict . Aeson.encode . definitionToJSON

enumText :: (Bounded a, Enum a) => (a -> Text) -> Text -> Text -> Parser a
enumText render what t = case [x | x <- [minBound .. maxBound], render x == t] of
  [x] -> pure x
  _ -> fail ("unknown " <> T.unpack what <> " '" <> T.unpack t <> "'")

thresholdsToJSON :: Thresholds -> Value
thresholdsToJSON t = object ["blockAt" .= (t ^. #blockAt), "passAt" .= (t ^. #passAt)]

parseThresholds :: Value -> Parser Thresholds
parseThresholds = withObject "Thresholds" $ \o -> Thresholds <$> o .: "blockAt" <*> o .: "passAt"

definitionToJSON :: JudgementDefinition -> Value
definitionToJSON d =
  object
    [ "name" .= (d ^. #name),
      "version" .= (d ^. #version),
      "description" .= (d ^. #description),
      "instructions" .= (d ^. #instructions),
      "evidence"
        .= object
          [ "scopes" .= map renderScopeKind (d ^. #evidence . #scopes),
            "include" .= (d ^. #evidence . #include),
            "exclude" .= (d ^. #evidence . #exclude)
          ],
      "limits"
        .= object
          [ "maxFileBytes" .= (d ^. #limits . #maxFileBytes),
            "maxChunkBytes" .= (d ^. #limits . #maxChunkBytes),
            "maxChunks" .= (d ^. #limits . #maxChunks),
            "maxAttempts" .= (d ^. #limits . #maxAttempts),
            "timeoutSeconds" .= (d ^. #limits . #timeoutSeconds),
            "maxFindings" .= (d ^. #limits . #maxFindings)
          ],
      "deterministicChecks" .= map renderDeterministicCheck (d ^. #deterministicChecks),
      "checks" .= map checkToJSON (toList (d ^. #checks))
    ]
  where
    checkToJSON c =
      object
        [ "name" .= (c ^. #name),
          "question" .= (c ^. #question),
          "concernWhen" .= renderAnswer (c ^. #concernWhen),
          "yesMeans" .= (c ^. #yesMeans),
          "noMeans" .= (c ^. #noMeans),
          "categories"
            .= [ object ["name" .= (cat ^. #name), "severity" .= renderSeverity (cat ^. #severity), "description" .= (cat ^. #description)]
               | cat <- c ^. #categories
               ],
          "enforcement" .= renderEnforcement (c ^. #enforcement),
          "blockingSeverity" .= renderSeverity (c ^. #blockingSeverity),
          "review" .= thresholdsToJSON (c ^. #review),
          "gate" .= thresholdsToJSON (c ^. #gate),
          "useGate" .= (c ^. #useGate)
        ]

-- | Decode and structurally validate a definition snapshot.
parseDefinition :: Value -> Parser JudgementDefinition
parseDefinition = withObject "JudgementDefinition" $ \o -> do
  evidence <- o .: "evidence" >>= withObject "EvidenceDeclaration" (\e -> EvidenceDeclaration <$> (mapM (enumText renderScopeKind "evidence scope") =<< e .: "scopes") <*> e .: "include" <*> e .: "exclude")
  limits <-
    o .: "limits"
      >>= withObject
        "CoverageLimits"
        ( \l ->
            CoverageLimits
              <$> l .: "maxFileBytes"
              <*> l .: "maxChunkBytes"
              <*> l .: "maxChunks"
              <*> l .: "maxAttempts"
              <*> l .: "timeoutSeconds"
              <*> l .: "maxFindings"
        )
  rawChecks <- o .: "checks"
  checks <- maybe (fail "a judgement needs at least one check") pure . NE.nonEmpty =<< mapM parseCheck rawChecks
  d <-
    JudgementDefinition
      <$> o .: "name"
      <*> o .: "version"
      <*> o .: "description"
      <*> o .: "instructions"
      <*> pure evidence
      <*> pure limits
      <*> (mapM (enumText renderDeterministicCheck "deterministic check") =<< o .: "deterministicChecks")
      <*> pure checks
  either (fail . T.unpack . (^. #message)) (const (pure d)) (validateDefinition d)
  where
    parseCheck = withObject "JudgementCheck" $ \c ->
      JudgementCheck
        <$> c .: "name"
        <*> c .: "question"
        <*> (enumText renderAnswer "answer" =<< c .: "concernWhen")
        <*> c .: "yesMeans"
        <*> c .: "noMeans"
        <*> (mapM parseCategory =<< c .: "categories")
        <*> (enumText renderEnforcement "enforcement" =<< c .: "enforcement")
        <*> (enumText renderSeverity "severity" =<< c .: "blockingSeverity")
        <*> (parseThresholds =<< c .: "review")
        <*> (parseThresholds =<< c .: "gate")
        <*> c .: "useGate"
    parseCategory = withObject "FindingCategory" $ \cat ->
      FindingCategory <$> cat .: "name" <*> (enumText renderSeverity "severity" =<< cat .: "severity") <*> cat .: "description"

policyToJSON :: JudgementPolicy -> Value
policyToJSON p =
  object
    [ "dataPolicy" .= renderDataPolicy (p ^. #dataPolicy),
      "gatePermitted" .= (p ^. #gatePermitted),
      "checks" .= Map.map checkPolicyToJSON (p ^. #checks)
    ]
  where
    checkPolicyToJSON c =
      object
        [ "enforcement" .= renderEnforcement (c ^. #enforcement),
          "blockingSeverity" .= renderSeverity (c ^. #blockingSeverity),
          "review" .= thresholdsToJSON (c ^. #review),
          "gate" .= thresholdsToJSON (c ^. #gate),
          "useGate" .= (c ^. #useGate)
        ]

-- | Decode a policy and check it against the definition it governs: every
-- check has exactly one policy entry and every threshold pair is valid.
parsePolicy :: JudgementDefinition -> Value -> Parser JudgementPolicy
parsePolicy def = withObject "JudgementPolicy" $ \o -> do
  raw <- o .: "checks" :: Parser (Map Text Value)
  checks <- Map.traverseWithKey (const parseCheckPolicy) raw
  let declared = map (^. #name) (toList (def ^. #checks))
  unless (Map.keys checks == sortedUnique declared) $
    fail ("judgement '" <> T.unpack (def ^. #name) <> "' policy must name exactly its checks: " <> T.unpack (T.intercalate ", " declared))
  forM_ (Map.toList checks) $ \(name, c) -> do
    either (fail . T.unpack . (^. #message)) pure (validateThresholds ("check '" <> name <> "' review") (c ^. #review))
    either (fail . T.unpack . (^. #message)) pure (validateThresholds ("check '" <> name <> "' gate") (c ^. #gate))
  JudgementPolicy
    <$> (enumText renderDataPolicy "data policy" =<< o .: "dataPolicy")
    <*> o .: "gatePermitted"
    <*> pure checks
  where
    sortedUnique = Map.keys . Map.fromList . map (,())
    parseCheckPolicy = withObject "CheckPolicy" $ \c ->
      CheckPolicy
        <$> (enumText renderEnforcement "enforcement" =<< c .: "enforcement")
        <*> (enumText renderSeverity "severity" =<< c .: "blockingSeverity")
        <*> (parseThresholds =<< c .: "review")
        <*> (parseThresholds =<< c .: "gate")
        <*> c .: "useGate"
