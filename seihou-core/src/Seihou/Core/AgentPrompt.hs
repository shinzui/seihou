module Seihou.Core.AgentPrompt
  ( validateAgentPrompt,
    checkAgentPromptNameFormat,
    checkAgentPromptVersionPresent,
    checkAgentPromptBodyNonEmpty,
    checkAgentPromptUniqueVars,
    checkAgentPromptPromptRefs,
    checkAgentPromptCommandVars,
    checkAgentPromptFiles,
    checkAgentPromptTags,
    checkAgentPromptAllowedTools,
  )
where

import Data.Set qualified as Set
import Data.Text qualified as T
import Numeric.Natural (Natural)
import Seihou.Core.Module (isValidModuleName)
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Validate a decoded 'AgentPrompt' against the prompt authoring rules.
-- The 'FilePath' is the prompt's base directory (containing @prompt.dhall@).
validateAgentPrompt :: FilePath -> AgentPrompt -> IO (Either ModuleLoadError AgentPrompt)
validateAgentPrompt baseDir p = do
  fileErrs <- checkAgentPromptFiles baseDir p
  let pureErrs =
        checkAgentPromptNameFormat p
          <> checkAgentPromptVersionPresent p
          <> checkAgentPromptBodyNonEmpty p
          <> checkAgentPromptUniqueVars p
          <> checkAgentPromptPromptRefs p
          <> checkAgentPromptCommandVars p
          <> checkAgentPromptTags p
          <> checkAgentPromptAllowedTools p
      allErrs = pureErrs <> fileErrs
  pure $
    if null allErrs
      then Right p
      else Left (ValidationError p.name allErrs)

checkAgentPromptNameFormat :: AgentPrompt -> [Text]
checkAgentPromptNameFormat p =
  let n = p.name.unModuleName
   in if T.null n || not (isValidModuleName n)
        then ["prompt name must match [a-z][a-z0-9-]*, got: " <> n]
        else []

checkAgentPromptVersionPresent :: AgentPrompt -> [Text]
checkAgentPromptVersionPresent p = case p.version of
  Nothing -> []
  Just v
    | T.null (T.strip v) -> ["prompt version, if specified, must not be empty"]
    | otherwise -> []

checkAgentPromptBodyNonEmpty :: AgentPrompt -> [Text]
checkAgentPromptBodyNonEmpty p
  | T.null (T.strip p.prompt) = ["prompt body must not be empty"]
  | otherwise = []

checkAgentPromptUniqueVars :: AgentPrompt -> [Text]
checkAgentPromptUniqueVars p =
  let names = map (\d -> d.name.unVarName) p.vars
   in map (\n -> "duplicate variable name: " <> n) (findDupes Set.empty Set.empty names)

checkAgentPromptPromptRefs :: AgentPrompt -> [Text]
checkAgentPromptPromptRefs p =
  let varNames = Set.fromList (map (.name) p.vars)
   in concatMap
        ( \prompt ->
            if Set.member prompt.var varNames
              then []
              else ["prompt references undeclared variable: " <> prompt.var.unVarName]
        )
        p.prompts

checkAgentPromptCommandVars :: AgentPrompt -> [Text]
checkAgentPromptCommandVars p =
  duplicateCommandVars <> concatMap checkCommandVar p.commandVars
  where
    commandNames = map (\cv -> cv.name.unVarName) p.commandVars

    duplicateCommandVars =
      map
        (\n -> "duplicate command variable name: " <> n)
        (findDupes Set.empty Set.empty commandNames)

    checkCommandVar cv =
      checkName cv <> checkRun cv <> checkWorkDir cv.workDir <> checkMaxBytes cv.maxBytes

    checkName cv
      | T.null (T.strip cv.name.unVarName) = ["command variable name must not be empty"]
      | otherwise = []

    checkRun cv
      | T.null (T.strip cv.run) = ["command variable '" <> cv.name.unVarName <> "' run must not be empty"]
      | otherwise = []

    checkWorkDir Nothing = []
    checkWorkDir (Just wd) =
      case validateProjectRelativePath wd of
        Left err -> ["command variable workDir " <> err]
        Right _ -> []

    checkMaxBytes Nothing = []
    checkMaxBytes (Just n)
      | n == 0 = ["command variable maxBytes must be greater than zero"]
      | n > maxReasonableBytes = ["command variable maxBytes must be <= 1048576"]
      | otherwise = []

    maxReasonableBytes :: Natural
    maxReasonableBytes = 1048576

checkAgentPromptFiles :: FilePath -> AgentPrompt -> IO [Text]
checkAgentPromptFiles baseDir p =
  concat
    <$> mapM
      ( \pf -> do
          let path = baseDir </> "files" </> pf.src
          exists <- doesFileExist path
          pure $
            if exists
              then []
              else ["prompt file not found: " <> T.pack pf.src]
      )
      p.files

checkAgentPromptTags :: AgentPrompt -> [Text]
checkAgentPromptTags p =
  [ "tag must not be empty"
  | t <- p.tags,
    T.null (T.strip t)
  ]

checkAgentPromptAllowedTools :: AgentPrompt -> [Text]
checkAgentPromptAllowedTools p = case p.allowedTools of
  Nothing -> []
  Just xs ->
    [ "allowedTools entry must not be empty"
    | t <- xs,
      T.null (T.strip t)
    ]

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs
