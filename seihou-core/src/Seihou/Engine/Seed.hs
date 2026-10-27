module Seihou.Engine.Seed
  ( SeedError (..),
    SeedDecision (..),
    PlannedSeed (..),
    classifySeed,
    seedOperationClaims,
    planSeeds,
    validateSeedRun,
    executeSeeds,
    renderSeedPlan,
  )
where

import Control.Monad (foldM, forM)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Checkout (pathsOverlap)
import Seihou.Core.Path (pathsHaveConflictingSpelling, validateCanonicalProjectPath)
import Seihou.Core.Seed
import Seihou.Core.Types
import Seihou.Effect.Filesystem
import Seihou.Prelude
import System.FilePath.Posix qualified as P

data SeedError = SeedError {code :: !Text, message :: !Text}
  deriving stock (Eq, Show, Generic)

data SeedDecision = SeedWrite | SeedKeepExisting | SeedRespectDeletion | SeedAlreadySettled | SeedReleaseManaged
  deriving stock (Eq, Show, Generic)

data PlannedSeed = PlannedSeed
  { dest :: !FilePath,
    content :: !Text,
    strategy :: !Strategy,
    supplier :: !ModuleName,
    owners :: !(Set ModuleName),
    observed :: !PathEntry,
    decision :: !SeedDecision
  }
  deriving stock (Eq, Show, Generic)

classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> PathEntry -> Either SeedError SeedDecision
classifySeed _ (Just _) _ = Right SeedReleaseManaged
classifySeed (Just _) Nothing EntryMissing = Right SeedRespectDeletion
classifySeed (Just _) Nothing _ = Right SeedAlreadySettled
classifySeed Nothing Nothing EntryMissing = Right SeedWrite
classifySeed Nothing Nothing EntryFile = Right SeedKeepExisting
classifySeed Nothing Nothing _ = Left (SeedError "seed_destination_occupied" "new seed destination is a symlink or directory; move it aside and retry")

seedOperationClaims :: [Operation] -> Map FilePath (Set ModuleName)
seedOperationClaims operations = Map.fromListWith Set.union [(dest, Set.singleton moduleName) | SeedFileOp {dest, moduleName} <- operations]

-- | Lifecycle transitions belong to update; force is never consent. This pure
-- preflight runs before migrations, writes, or publishing new applied metadata.
validateSeedRun :: Manifest -> [Operation] -> Either [SeedError] ()
validateSeedRun manifest operations = case errors of [] -> Right (); _ -> Left errors
  where
    errors =
      [transition path | SeedFileOp {dest = path} <- operations, Map.member path (manifest ^. #files)]
        <> [transition path | op <- operations, Just path <- [managedDestination op], seed <- Map.keys (manifest ^. #seeds), pathsOverlap path seed]
    transition path = SeedError "seed_lifecycle_transition" ("output '" <> T.pack path <> "' changes lifecycle; run seihou update for its recorded application to review the transition")

managedDestination :: Operation -> Maybe FilePath
managedDestination WriteFileOp {dest} = Just dest
managedDestination CopyFileOp {dest} = Just dest
managedDestination PatchFileOp {dest} = Just dest
managedDestination CheckoutOutputOp {dest} = Just dest
managedDestination _ = Nothing

planSeeds :: (Filesystem :> es) => FilePath -> Manifest -> Map FilePath (Set ModuleName) -> [Operation] -> Eff es (Either [SeedError] [PlannedSeed])
planSeeds root manifest claims operations = do
  results <- forM [op | op@SeedFileOp {} <- operations] $ \case
    SeedFileOp {dest, content, strategy, moduleName} -> do
      let overlaps =
            [other | other <- Map.keys (manifest ^. #files), other /= dest, (pathsOverlap dest other || pathsHaveConflictingSpelling dest other)]
              <> [other | other <- Map.keys (manifest ^. #checkoutOutputs), (pathsOverlap dest other || pathsHaveConflictingSpelling dest other)]
              <> [other | other <- Map.keys (manifest ^. #seeds), other /= dest, (pathsOverlap dest other || pathsHaveConflictingSpelling dest other)]
      case first (SeedError "seed_path_invalid") (validateCanonicalProjectPath (T.pack dest)) of
        Left err -> pure (Left err)
        Right () | not (null overlaps) -> pure (Left (SeedError "seed_path_overlap" ("seed '" <> T.pack dest <> "' overlaps retained output '" <> T.pack (head overlaps) <> "'")))
        Right () -> do
          parents <- checkParents root dest False
          case parents of
            Left err -> pure (Left err)
            Right () -> do
              observed <- inspectPath (root </> dest)
              alias <- checkSpelling root dest observed
              pure $ do
                alias
                decision <- first (atPath dest) (classifySeed (Map.lookup dest (manifest ^. #seeds)) (Map.lookup dest (manifest ^. #files)) observed)
                Right (PlannedSeed dest content strategy moduleName (Map.findWithDefault (Set.singleton moduleName) dest claims) observed decision)
    _ -> error "non-seed operation in seed partition"
  pure $ case [err | Left err <- results] of [] -> Right [planned | Right planned <- results]; errors -> Left errors

ancestors :: FilePath -> [FilePath]
ancestors path = reverse (go (P.takeDirectory path))
  where
    go "." = []; go "" = []; go p = p : go (P.takeDirectory p)

atPath :: FilePath -> SeedError -> SeedError
atPath path err = err & #message %~ (("seed '" <> T.pack path <> "': ") <>)

checkSpelling :: (Filesystem :> es) => FilePath -> FilePath -> PathEntry -> Eff es (Either SeedError ())
checkSpelling _ _ EntryMissing = pure (Right ())
checkSpelling root path _ = do
  names <- listDirectory (root </> P.takeDirectory path)
  pure $ if P.takeFileName path `elem` names then Right () else Left (SeedError "seed_native_alias" ("seed path '" <> T.pack path <> "' resolves through a different native spelling"))

-- | Never traverse an unsafe ancestor. Missing parents are created only for an
-- actual exclusive creation attempt, so respecting deletion creates no directories.
checkParents :: (Filesystem :> es) => FilePath -> FilePath -> Bool -> Eff es (Either SeedError ())
checkParents root dest create = go (ancestors dest)
  where
    go [] = pure (Right ())
    go (parent : rest) =
      inspectPath (root </> parent) >>= \case
        EntryDirectory -> do
          spelling <- checkSpelling root parent EntryDirectory
          case spelling of Left err -> pure (Left err); Right () -> go rest
        EntryMissing | create -> createDirectoryIfMissing False (root </> parent) >> go rest
        EntryMissing -> pure (Right ())
        _ -> pure (Left (SeedError "seed_parent_unsafe" ("seed ancestor '" <> T.pack parent <> "' must be a real directory; move the object aside")))

-- | Return the application's complete actual candidate claims; the caller uses
-- replaceSelectedSeedClaims after attaching final application records. No receipt
-- is returned for a failed creation. A partial run may leave a complete new file.
executeSeeds :: (Filesystem :> es) => FilePath -> ApplicationId -> UTCTime -> [PlannedSeed] -> Manifest -> Eff es (Either SeedError (Map FilePath SeedRecord))
executeSeeds root app now plans manifest = foldM apply (Right Map.empty) plans
  where
    apply (Left err) _ = pure (Left err)
    apply (Right records) planned = do
      let path = planned ^. #dest
          decision = planned ^. #decision
      outcome <- case decision of
        SeedWrite -> do
          safe <- checkParents root path True
          case safe of
            Left err -> pure (Left err)
            Right () ->
              createFileExclusive (root </> path) (planned ^. #content) >>= \case
                ExclusiveCreated -> pure (Right SeedCreated)
                ExclusiveFailure reason -> pure (Left (SeedError "seed_creation_failed" ("cannot create seed '" <> T.pack path <> "': " <> reason)))
                ExclusiveOccupied ->
                  inspectPath (root </> path) >>= \case
                    EntryFile -> pure (Right SeedFoundExisting)
                    _ -> pure (Left (SeedError "seed_destination_changed" ("seed '" <> T.pack path <> "' became occupied; move it aside and retry")))
        SeedReleaseManaged -> pure (Left (SeedError "seed_lifecycle_transition" "managed release requires seihou update"))
        SeedKeepExisting -> pure (Right SeedFoundExisting)
        _ -> pure (Right (maybe SeedFoundExisting (^. #outcome) (Map.lookup path (manifest ^. #seeds))))
      pure $ do
        actual <- outcome
        let prior = Map.lookup path (manifest ^. #seeds)
            record = SeedRecord (maybe (planned ^. #supplier) (^. #moduleName) prior) (KnownSeedOwners (Map.singleton app (planned ^. #owners))) actual (maybe now (^. #settledAt) prior)
        Right (Map.insert path record records)

renderSeedPlan :: Bool -> [PlannedSeed] -> Text
renderSeedPlan showContent plans = T.concat (map render plans)
  where
    render planned =
      "  "
        <> action (planned ^. #decision)
        <> " "
        <> T.pack (planned ^. #dest)
        <> " (seed; owned by the project)\n"
        <> if showContent && planned ^. #decision == SeedWrite then T.unlines (map ("    + " <>) (T.lines (planned ^. #content))) else ""
    action SeedWrite = "create once"
    action SeedKeepExisting = "keep existing"
    action SeedRespectDeletion = "keep deleted"
    action SeedAlreadySettled = "keep settled"
    action SeedReleaseManaged = "release to project"
