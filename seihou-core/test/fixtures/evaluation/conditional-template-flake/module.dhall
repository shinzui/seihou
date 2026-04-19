-- Single-template companion to split-flake: one flake.nix.tpl with
-- inline {{#if Eq nix.postgresql true}} blocks replaces the two
-- mutually-exclusive templates in split-flake/. Used by the in-tree
-- test that exercises the Template strategy's body-level conditional
-- rendering through compilePlan.
-- See docs/plans/9-inline-conditionals-in-template-strategy.md
{ name = "conditional-template-flake"
, version = Some "0.1.0"
, description = Some "Conditional-template fixture: one template gated by inline {{#if}} blocks"
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
