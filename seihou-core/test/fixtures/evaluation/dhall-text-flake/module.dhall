-- Prototype A: rewrite the split-flake module using the existing
-- DhallText strategy so one source produces both variants.
-- See docs/plans/8-evaluate-dhall-as-templating-language.md
{ name = "dhall-text-flake"
, version = Some "0.1.0"
, description = Some "DhallText rewrite of the split flake fixture"
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Project name"
    , required = True
    , validation = Some "[a-z][a-z0-9-]*"
    }
  , { name = "project.description"
    , type = "text"
    , default = None Text
    , description = Some "One-line project description"
    , required = True
    , validation = None Text
    }
  , { name = "ghc.version"
    , type = "text"
    , default = Some "ghc912"
    , description = Some "GHC version"
    , required = True
    , validation = None Text
    }
  , { name = "nix.process-compose"
    , type = "bool"
    , default = None Text
    , description = Some "Include process-compose"
    , required = True
    , validation = None Text
    }
  , { name = "nix.postgresql"
    , type = "bool"
    , default = None Text
    , description = Some "Include postgresql"
    , required = True
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts =
  [] : List
         { var : Text
         , text : Text
         , when : Optional Text
         , choices : Optional (List Text)
         }
, steps =
  [ { strategy = "dhall-text"
    , src = "flake.nix.dhall"
    , dest = "flake.nix"
    , when = None Text
    , patch = None Text
    }
  ]
, commands =
  [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies =
    [] : List { module : Text, vars : List { name : Text, value : Text } }
, removal =
    None
      { steps :
          List { action : Text, dest : Text, src : Optional Text }
      , commands :
          List { run : Text, workDir : Optional Text, when : Optional Text }
      }
}
