module Seihou.Composition.Recipe
  ( expandRecipe,
    ExpandedRecipe (..),
    ResolvedRecipeNode (..),
    ResolvedRecipeMember (..),
    RecipeLiteral (..),
    mergeRecipeChain,
    recipeLiteralSources,
  )
where

import Control.Lens ((&), (.~), (^.))
import Control.Monad (foldM, unless, when)
import Data.Generics.Labels ()
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.ArtifactIdentity (sameArtifactIdentity)
import Seihou.Core.Recipe (validateRecipe, validateRecipeVersion)
import Seihou.Core.Types

-- | Context belongs to the declaring recipe, even after member deduplication.
data ResolvedRecipeMember = ResolvedRecipeMember
  { dependency :: !Dependency,
    declaringRecipe :: !RecipeName,
    declaringOrigin :: !ArtifactOrigin,
    declaringDirectory :: !FilePath,
    memberOrigin :: !ArtifactOrigin
  }
  deriving stock (Eq, Show, Generic)

data ResolvedRecipeNode = ResolvedRecipeNode
  { definition :: !Recipe,
    origin :: !ArtifactOrigin,
    directory :: !FilePath,
    members :: ![ResolvedRecipeMember]
  }
  deriving stock (Eq, Show, Generic)

data RecipeLiteral = RecipeLiteral
  { value :: !Text,
    recipe :: !RecipeName,
    origin :: !ArtifactOrigin,
    member :: !ModuleName
  }
  deriving stock (Eq, Show, Generic)

data ExpandedRecipe = ExpandedRecipe
  { primary :: !ModuleName,
    members :: ![ResolvedRecipeMember],
    literals :: !(Map VarName RecipeLiteral),
    declarations :: ![VarDecl],
    prompts :: ![Prompt],
    chain :: ![ResolvedRecipeNode]
  }
  deriving stock (Eq, Show, Generic)

-- | Compatibility API for flat recipes. Never silently discard an extension.
expandRecipe :: Recipe -> Either [Text] (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt], [Dependency])
expandRecipe recipe = do
  validated <- validateRecipe recipe
  when (isJust (validated ^. #extends)) $
    Left ["Recipe extends a base; use origin-aware recipe-chain expansion"]
  case validated ^. #modules of
    [] -> Left ["recipe must list at least one module"]
    first : rest ->
      Right
        ( first ^. #module_,
          map (^. #module_) rest,
          Map.unions (map (^. #vars) (validated ^. #modules)),
          validated ^. #vars,
          validated ^. #prompts,
          validated ^. #modules
        )

-- | Merge an already resolved oldest-first chain. IO lookup and source proof
-- happen before this function; no member's binding becomes a graph edge.
mergeRecipeChain :: [ResolvedRecipeNode] -> Either [Text] ExpandedRecipe
mergeRecipeChain [] = Left ["Recipe chain is empty"]
mergeRecipeChain nodes@(oldest : _) = do
  mapM_ (validateRecipe . (^. #definition)) nodes
  when (isJust (oldest ^. #definition . #extends)) (Left ["Unresolved oldest recipe base"])
  checkLinks nodes
  (mergedMembers, bindings, decls, questions) <- foldM layer ([], Map.empty, [], []) nodes
  case mergedMembers of
    [] -> Left ["Expanded recipe must list at least one module"]
    first : _ -> do
      -- Reuse descriptor checks on the complete declaration/prompt scope.
      let lastRecipe = foldl (\_ n -> n ^. #definition) (oldest ^. #definition) nodes
          final =
            lastRecipe
              & #extends .~ Nothing
              & #moduleOverrides .~ []
              & #promptOverrides .~ []
              & #modules .~ map (^. #dependency) mergedMembers
              & #vars .~ decls
              & #prompts .~ questions
      _ <- validateRecipe final
      pure (ExpandedRecipe (first ^. #dependency . #module_) mergedMembers bindings decls questions nodes)
  where
    extended = length nodes > 1
    checkLinks (parent : child : rest) = do
      case child ^. #definition . #extends of
        Just ref | ref ^. #recipe == parent ^. #definition . #name -> validateRecipeVersion ref (parent ^. #definition)
        _ -> Left ["Recipe chain does not match its declared base"]
      checkLinks (child : rest)
    checkLinks [_] = Right ()
    checkLinks [] = Right ()

    layer (inherited, bindings, decls, questions) node = do
      let descriptor = node ^. #definition
          label = descriptor ^. #name . #unRecipeName
          failHere :: Text -> Either [Text] a
          failHere msg = Left ["Recipe '" <> label <> "': " <> msg]
      unless (map (^. #dependency) (node ^. #members) == descriptor ^. #modules) $
        failHere "resolved member context does not match descriptor"
      unless (not extended || unique (map (^. #var) questions)) $
        failHere "inherited prompts have ambiguous duplicate targets"
      changed <- foldM (overrideMember failHere) inherited (descriptor ^. #moduleOverrides)
      combined <- foldM (addMember failHere) changed (node ^. #members)
      let entries =
            [(dep ^. #module_, dep ^. #vars) | dep <- descriptor ^. #modules]
              <> [(o ^. #module_, o ^. #vars) | o <- descriptor ^. #moduleOverrides]
      delta <- foldM (addLiterals failHere node) Map.empty entries
      mergedDecls <- foldM (addDeclaration failHere) decls (descriptor ^. #vars)
      replaced <- foldM (overridePrompt failHere) questions (descriptor ^. #promptOverrides)
      mergedPrompts <-
        if extended
          then foldM (addPrompt failHere) replaced (descriptor ^. #prompts)
          else Right (descriptor ^. #prompts)
      pure (combined, Map.union delta bindings, mergedDecls, mergedPrompts)

    overrideMember failHere inherited override =
      case filter (\m -> m ^. #dependency . #module_ == override ^. #module_) inherited of
        [_] ->
          Right
            [ if m ^. #dependency . #module_ == override ^. #module_
                then m & #dependency . #vars .~ Map.union (override ^. #vars) (m ^. #dependency . #vars)
                else m
            | m <- inherited
            ]
        _ -> failHere "moduleOverrides must name exactly one inherited member"

    addMember failHere acc member = case filter (\m -> m ^. #dependency . #module_ == member ^. #dependency . #module_) acc of
      [] -> Right (acc <> [member])
      [old]
        | not (sameArtifactIdentity (old ^. #memberOrigin) (member ^. #memberOrigin)) -> failHere ("member '" <> member ^. #dependency . #module_ . #unModuleName <> "' requires different origins: " <> originLabel (old ^. #memberOrigin) <> " versus " <> originLabel (member ^. #memberOrigin))
        | old ^. #dependency . #vars /= member ^. #dependency . #vars -> failHere ("repeated member '" <> member ^. #dependency . #module_ . #unModuleName <> "' bindings conflict; use moduleOverrides")
        | otherwise -> Right acc
      _ -> failHere "ambiguous member identity"

    addLiterals failHere node acc (member, values) = foldM add acc (Map.toList values)
      where
        add current (name, value) = case Map.lookup name current of
          Just old | extended && old ^. #value /= value -> failHere ("unequal literal '" <> name ^. #unVarName <> "' in members '" <> old ^. #member . #unModuleName <> "' and '" <> member ^. #unModuleName <> "' (modules/moduleOverrides)")
          Just _ -> Right current
          Nothing -> Right (Map.insert name (RecipeLiteral value (node ^. #definition . #name) (node ^. #origin) member) current)

    addDeclaration failHere acc child = case filter (\d -> d ^. #name == child ^. #name) acc of
      [] -> Right (acc <> [child])
      [parent]
        | parent ^. #type_ /= child ^. #type_ || parent ^. #required /= child ^. #required || parent ^. #validation /= child ^. #validation ->
            failHere ("inherited variable '" <> child ^. #name . #unVarName <> "' type, requiredness or validation conflicts")
        | otherwise ->
            Right
              [ if d ^. #name == child ^. #name
                  then
                    child
                      & #default_ .~ nearest (child ^. #default_) (parent ^. #default_)
                      & #description .~ nearest (child ^. #description) (parent ^. #description)
                  else d
              | d <- acc
              ]
      _ -> failHere "ambiguous variable declaration"

    overridePrompt failHere acc child = case filter (\p -> p ^. #var == child ^. #var) acc of
      [_] -> Right [if p ^. #var == child ^. #var then child else p | p <- acc]
      _ -> failHere "promptOverrides must name exactly one inherited prompt"
    addPrompt failHere acc child = case filter (\p -> p ^. #var == child ^. #var) acc of
      [] -> Right (acc <> [child])
      [old] | old == child -> Right acc
      _ -> failHere "repeated prompt differs; use promptOverrides"
    nearest (Just x) _ = Just x
    nearest Nothing old = old
    unique [] = True
    unique (x : xs) = x `notElem` xs && unique xs

-- | Preserve source attribution when resolving declared and undeclared literals.
recipeLiteralSources :: ExpandedRecipe -> Map VarName (Text, VarSource)
recipeLiteralSources expanded = Map.map (\literal -> (literal ^. #value, FromRecipeBindingAt (literal ^. #recipe) (literal ^. #origin))) (expanded ^. #literals)

originLabel :: ArtifactOrigin -> Text
originLabel (RemoteOrigin url name _) = url <> "#" <> name
originLabel (ProjectOrigin path) = T.pack path
originLabel (LocalOrigin name) = name <> " (unverified local origin)"
