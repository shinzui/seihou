-- | Seihou Module Schema
--
-- VarType is represented as a Text string in Dhall because Dhall does not
-- support recursive types. The Haskell decoder parses these strings into
-- the VarType ADT.
--
-- Valid type strings: "text", "bool", "int", "list text", "list bool",
-- "list int", "choice"

let VarDecl =
      { name : Text
      , type : Text
      , default : Optional Text
      , description : Optional Text
      , required : Bool
      , validation : Optional Text
      }

let VarExport = { var : Text, alias : Optional Text }

let Prompt =
      { var : Text
      , text : Text
      , when : Optional Text
      , choices : Optional (List Text)
      }

let Step =
      { strategy : Text
      , src : Text
      , dest : Text
      , when : Optional Text
      }

let Module =
      { name : Text
      , description : Optional Text
      , vars : List VarDecl
      , exports : List VarExport
      , prompts : List Prompt
      , steps : List Step
      , dependencies : List Text
      }

in  { VarDecl, VarExport, Prompt, Step, Module }
