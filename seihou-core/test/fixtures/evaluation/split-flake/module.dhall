-- Minimized stand-in for the real nix-haskell-flake module, used to
-- reproduce the "two near-duplicate templates gated by mutually
-- exclusive when conditions" pain point in-tree.
-- See docs/plans/8-evaluate-dhall-as-templating-language.md
{ name = "split-flake"
, version = Some "0.1.0"
, description = Some "Split-flake fixture: two near-duplicate templates for one output"
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
  [ { strategy = "template"
    , src = "flake.nix.tpl"
    , dest = "flake.nix"
    , when = Some "Eq nix.postgresql false"
    , patch = None Text
    }
  , { strategy = "template"
    , src = "flake-with-postgres.nix.tpl"
    , dest = "flake.nix"
    , when = Some "Eq nix.postgresql true"
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
