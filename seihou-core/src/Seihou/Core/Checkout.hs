module Seihou.Core.Checkout
  ( CheckoutError (..),
    checkoutError,
    validateCheckoutPaths,
    validateCheckoutRecords,
    mergeCheckoutRecord,
    dropCheckoutOwners,
    checkoutClaims,
    checkoutSource,
    replaceCheckoutApplications,
    CheckoutIntent (..),
    CheckoutPolicy (..),
    CheckoutObservation (..),
    CheckoutAction (..),
    CheckoutEntry (..),
    CheckoutPlan (..),
    planCheckoutOutputs,
    checkoutApplicable,
    expectedTarget,
    pathsOverlap,
  )
where

import Control.Monad (foldM, forM_, unless, when)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, maybeToList)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Composition.Instance (ModuleInstance (..), qualifiedName)
import Seihou.Core.Path (validateCanonicalProjectPath)
import Seihou.Core.Types
import Seihou.Effect.Filesystem (PathEntry (..))
import Seihou.Prelude
import System.FilePath.Posix qualified as P

-- | Stable machine code and an actionable human explanation.
data CheckoutError = CheckoutError {code :: !Text, message :: !Text}
  deriving stock (Eq, Show, Generic)

checkoutError :: Text -> Text -> CheckoutError
checkoutError = CheckoutError

checkoutSource :: CheckoutOutputSpec -> FilePath
checkoutSource (DirectorySymlink source) = source

pathsOverlap :: FilePath -> FilePath -> Bool
pathsOverlap a b = a == b || (a <> "/") `isPrefixOf` b || (b <> "/") `isPrefixOf` a
  where
    isPrefixOf x y = T.pack x `T.isPrefixOf` T.pack y

validateCheckoutPaths :: FilePath -> FilePath -> Either CheckoutError ()
validateCheckoutPaths source dest = do
  forM_ [source, dest] $ \path -> first (checkoutError "checkout_path_invalid") (validateCanonicalProjectPath (T.pack path))
  when (pathsOverlap source dest) $ Left (checkoutError "checkout_path_overlap" "source and destination must not overlap")

-- | Validate the entire candidate, including application-local instance ownership.
validateCheckoutRecords :: Manifest -> [FilePath] -> Either CheckoutError ()
validateCheckoutRecords manifest pending = do
  let outputs = manifest ^. #checkoutOutputs
      bytePaths = Map.keys (manifest ^. #files) <> Map.keys (manifest ^. #seeds) <> pending
  forM_ (Map.toAscList outputs) $ \(dest, record) -> do
    validateCheckoutPaths (checkoutSource (record ^. #spec)) dest
    when (Map.null (record ^. #owners)) $ bad dest "has no owners"
    forM_ (Map.toAscList (record ^. #owners)) $ \(appId, names) -> do
      when (Set.null names) $ bad dest "has an empty instance owner set"
      case filter ((== appId) . (^. #applicationId)) (manifest ^. #applications) of
        [app] -> unless (names `Set.isSubsetOf` Set.fromList [qualifiedName (ModuleInstance (state ^. #name) (state ^. #parentVars)) | state <- app ^. #instances]) $ bad dest "names an instance outside its owning application"
        _ -> bad dest "names an unknown or duplicate application owner"
    forM_ bytePaths $ \path -> when (pathsOverlap dest path) $ bad dest ("overlaps managed or seed output '" <> T.pack path <> "'; resolve the lifecycle transition manually")
    forM_ (Map.keys outputs) $ \other -> do
      when (dest /= other && pathsOverlap dest other) $ bad dest ("overlaps checkout destination '" <> T.pack other <> "'")
      when (pathsOverlap (checkoutSource (record ^. #spec)) other) $ bad dest ("source overlaps checkout destination '" <> T.pack other <> "'")
  where
    bad dest reason = Left (checkoutError "checkout_declaration_invalid" ("checkout output '" <> T.pack dest <> "' " <> reason))

mergeCheckoutRecord :: FilePath -> CheckoutOutputRecord -> Map FilePath CheckoutOutputRecord -> Either CheckoutError (Map FilePath CheckoutOutputRecord)
mergeCheckoutRecord dest record records = case Map.lookup dest records of
  Nothing -> Right (Map.insert dest record records)
  Just old | old ^. #spec == record ^. #spec -> Right (Map.insert dest (old & #owners %~ Map.unionWith Set.union (record ^. #owners)) records)
  Just _ -> Left (checkoutError "checkout_owner_conflict" ("checkout owners disagree on '" <> T.pack dest <> "'"))

-- | Replace the selected claims; preserve all unselected application/instance owners.
dropCheckoutOwners :: Map ApplicationId (Set ModuleName) -> Map FilePath CheckoutOutputRecord -> Map FilePath CheckoutOutputRecord
dropCheckoutOwners selected = Map.mapMaybe $ \record ->
  let retained = Map.mapMaybeWithKey (\app names -> let rest = names `Set.difference` Map.findWithDefault Set.empty app selected in if Set.null rest then Nothing else Just rest) (record ^. #owners)
   in if Map.null retained then Nothing else Just (record & #owners .~ retained)

checkoutClaims :: ApplicationId -> [Operation] -> Either CheckoutError (Map FilePath CheckoutOutputRecord)
checkoutClaims app = foldM add Map.empty
  where
    add records CheckoutOutputOp {dest, spec, moduleName} = mergeCheckoutRecord dest (CheckoutOutputRecord spec (Map.singleton app (Set.singleton moduleName))) records
    add records _ = Right records

data CheckoutIntent = Rebuild | Reconcile deriving stock (Eq, Show, Generic)

data CheckoutPolicy = SyncIgnoredOnly | ApplyDeclaration deriving stock (Eq, Show, Generic)

data CheckoutObservation = CheckoutObservation
  { entry :: !PathEntry,
    sourceDirectory :: !Bool,
    problems :: ![CheckoutError],
    gitAvailable :: !Bool,
    ignored :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data CheckoutAction = CreateLink | ReplaceLink | RetireLink | UnchangedLink | AlreadyAbsent | PreserveModified | RefusedLink
  deriving stock (Eq, Ord, Show, Generic)

data CheckoutEntry = CheckoutEntry
  { dest :: !FilePath,
    previous :: !(Maybe CheckoutOutputSpec),
    candidate :: !(Maybe CheckoutOutputSpec),
    observation :: !CheckoutObservation,
    action :: !CheckoutAction,
    errors :: ![CheckoutError],
    warnings :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

newtype CheckoutPlan = CheckoutPlan {entries :: [CheckoutEntry]}
  deriving stock (Eq, Show, Generic)

checkoutApplicable :: CheckoutPlan -> Bool
checkoutApplicable = all (null . (^. #errors)) . (^. #entries)

expectedTarget :: FilePath -> CheckoutOutputSpec -> FilePath
expectedTarget dest (DirectorySymlink source) =
  let parent = P.takeDirectory dest
      depth = if parent == "." then 0 else length (P.splitDirectories parent)
   in P.joinPath (replicate depth ".." <> [source])

planCheckoutOutputs :: CheckoutIntent -> CheckoutPolicy -> Map FilePath CheckoutOutputRecord -> Map FilePath CheckoutOutputRecord -> Map FilePath CheckoutObservation -> CheckoutPlan
planCheckoutOutputs intent policy prior candidate observations = CheckoutPlan (map plan (Set.toAscList (Map.keysSet prior <> Map.keysSet candidate)))
  where
    plan dest =
      let old = (^. #spec) <$> Map.lookup dest prior
          new = (^. #spec) <$> Map.lookup dest candidate
          obs = Map.findWithDefault (CheckoutObservation EntryMissing False [checkoutError "checkout_observation_missing" "output was not observed"] False False) dest observations
          unchanged = intent == Reconcile && old == new
          active = isJust new
          syntax = [err | spec <- maybeToList new <> maybeToList old, Left err <- [validateCheckoutPaths (checkoutSource spec) dest]]
          policyErrors =
            [checkoutError "checkout_git_required" "sync requires a Git working tree" | policy == SyncIgnoredOnly, not (obs ^. #gitAvailable)]
              <> [checkoutError "checkout_not_ignored" "destination must be ignored; add it to .gitignore before running seihou sync" | policy == SyncIgnoredOnly, active, not (obs ^. #ignored)]
          preconditions =
            if unchanged
              then []
              else
                obs ^. #problems
                  <> policyErrors
                  <> [checkoutError "checkout_source_missing" "source must be an existing real project directory; restore it before retrying" | active, not (obs ^. #sourceDirectory)]
          contract = [checkoutError "checkout_rebuild_contract" "rebuild requires identical prior and candidate declarations" | intent == Rebuild, prior /= candidate]
          (proposed, collisions) = classify dest old new (obs ^. #entry) unchanged
          errs = contract <> syntax <> preconditions <> collisions
          warnings =
            ["preserved a modified checkout entry; released its declaration" | proposed == PreserveModified]
              <> ["Git evidence unavailable; applying a declaration before git-init" | not unchanged, policy == ApplyDeclaration, not (obs ^. #gitAvailable)]
              <> ["checkout destination is not ignored; clones require ignore rules for seihou sync" | not unchanged, policy == ApplyDeclaration, obs ^. #gitAvailable, active, not (obs ^. #ignored)]
       in CheckoutEntry dest old new obs (if null errs then proposed else RefusedLink) errs warnings
    classify _ _ _ _ True = (UnchangedLink, [])
    classify dest old Nothing entry _ = case entry of
      EntryMissing -> (AlreadyAbsent, [])
      EntrySymlink target | Just spec <- old, target == expectedTarget dest spec -> (RetireLink, [])
      _ -> (PreserveModified, [])
    classify dest old (Just spec) entry _ = case entry of
      EntryMissing -> (CreateLink, [])
      EntrySymlink target
        | target == expectedTarget dest spec -> (UnchangedLink, [])
        | intent == Rebuild || maybe False ((== target) . expectedTarget dest) old -> (ReplaceLink, [])
        | otherwise -> (RefusedLink, [checkoutError "checkout_link_modified" "link target changed locally; move it aside or restore its recorded target"])
      _ -> (RefusedLink, [checkoutError "checkout_destination_occupied" "destination is a real file or directory; move it aside manually"])

-- | Re-evaluation replaces a selected application's complete declaration set,
-- including dependencies that disappeared or whose conditions became false.
replaceCheckoutApplications :: Manifest -> [(AppliedComposition, [Operation])] -> Either CheckoutError Manifest
replaceCheckoutApplications prior applications = do
  let selected = Set.fromList [app ^. #applicationId | (app, _) <- applications]
      departing = Map.unionsWith Set.union [Map.restrictKeys (record ^. #owners) selected | record <- Map.elems (prior ^. #checkoutOutputs)]
      retained = dropCheckoutOwners departing (prior ^. #checkoutOutputs)
      updateApps apps (app, _) = app : filter ((/= app ^. #applicationId) . (^. #applicationId)) apps
  outputs <- foldM add retained applications
  let candidate = prior & #checkoutOutputs .~ outputs & #applications .~ foldl updateApps (prior ^. #applications) applications
      pending =
        [ dest
        | (_, ops) <- applications,
          op <- ops,
          dest <- case op of
            WriteFileOp {dest} -> [dest]
            CopyFileOp {dest} -> [dest]
            PatchFileOp {dest} -> [dest]
            _ -> []
        ]
  validateCheckoutRecords candidate pending
  forM_ pending $ \path -> forM_ (Map.keys (prior ^. #checkoutOutputs)) $ \old ->
    when (pathsOverlap path old) $ Left (checkoutError "checkout_lifecycle_transition" ("output '" <> T.pack path <> "' overlaps a previous checkout declaration; remove that declaration and resolve the transition manually"))
  pure candidate
  where
    add records (app, ops) = do
      claims <- checkoutClaims (app ^. #applicationId) ops
      foldM (\acc (dest, record) -> mergeCheckoutRecord dest record acc) records (Map.toAscList claims)
