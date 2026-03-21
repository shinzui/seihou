-- | Seihou Module Schema
--
-- VarType is represented as a Text string in Dhall because Dhall does not
-- support recursive types. The Haskell decoder parses these strings into
-- the VarType ADT.
--
-- Valid type strings: "text", "bool", "int", "list text", "list bool",
-- "list int", "choice"
--
-- Required fields (no default): name
-- Usage: let S = ./package.dhall in S.Module::{ name = "my-module", steps = [ ... ] }

let VarDecl = ./VarDecl.dhall

let VarExport = ./VarExport.dhall

let Prompt = ./Prompt.dhall

let Step = ./Step.dhall

let Command = ./Command.dhall

let Dependency = ./Dependency.dhall

in  { Type =
        { name : Text
        , version : Optional Text
        , description : Optional Text
        , vars : List VarDecl.Type
        , exports : List VarExport.Type
        , prompts : List Prompt.Type
        , steps : List Step.Type
        , commands : List Command.Type
        , dependencies : List Dependency.Type
        }
    , default =
        { version = None Text
        , description = None Text
        , vars = [] : List VarDecl.Type
        , exports = [] : List VarExport.Type
        , prompts = [] : List Prompt.Type
        , steps = [] : List Step.Type
        , commands = [] : List Command.Type
        , dependencies = [] : List Dependency.Type
        }
    }
