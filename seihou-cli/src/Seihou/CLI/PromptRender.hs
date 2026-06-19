{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.PromptRender
  ( renderPromptSystemPrompt,
    renderPromptBody,
    formatPromptGuidance,
  )
where

import Data.FileEmbed (embedFile)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatReferenceFiles,
    formatSeihouProjectState,
    substitute,
  )
import Seihou.Core.Expr (evalExpr)
import Seihou.Core.Types

promptRunTemplate :: T.Text
promptRunTemplate = TE.decodeUtf8 $(embedFile "data/prompt-run-prompt.md")

renderPromptSystemPrompt ::
  AgentContext ->
  AgentPrompt ->
  Map VarName ResolvedVar ->
  T.Text ->
  Maybe T.Text ->
  T.Text
renderPromptSystemPrompt ctx prompt resolved renderedPrompt userPrompt =
  substitute
    [ ("cwd", ctx.cwd),
      ("seihou_project_state", formatSeihouProjectState ctx),
      ("manifest_state", formatManifestState ctx),
      ("module_dhall_state", formatModuleDhallState ctx),
      ("local_modules", formatLocalModules ctx),
      ("available_modules", formatAvailableModules ctx),
      ("prompt_name", prompt.name.unModuleName),
      ("prompt_version", fromMaybe "(unspecified)" prompt.version),
      ("prompt_description", fromMaybe "(no description)" prompt.description),
      ("reference_files", formatReferenceFiles prompt.files),
      ("prompt_guidance", formatPromptGuidance resolved prompt.guidance),
      ("prompt_body", renderedPrompt),
      ("user_prompt", fromMaybe "(no one-off user instruction)" userPrompt)
    ]
    promptRunTemplate

renderPromptBody :: Map VarName ResolvedVar -> T.Text -> T.Text
renderPromptBody resolved tpl =
  substitute
    [(vn.unVarName, varValueToText rv.value) | (vn, rv) <- Map.toList resolved]
    tpl

formatPromptGuidance :: Map VarName ResolvedVar -> [PromptGuidance] -> T.Text
formatPromptGuidance resolved guidance =
  case filter selected guidance of
    [] -> "(no prompt guidance)"
    selectedGuidance -> T.intercalate "\n\n" (map render selectedGuidance)
  where
    bindings = Map.map (.value) resolved

    selected g =
      case g.condition of
        Nothing -> True
        Just cond -> evalExpr bindings cond

    render g =
      T.unlines
        [ "### " <> g.title,
          "",
          g.body
        ]

varValueToText :: VarValue -> T.Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)
