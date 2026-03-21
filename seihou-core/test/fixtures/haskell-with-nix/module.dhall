{ name = "haskell-with-nix"
, version = None Text
, description = Some "Haskell project with Nix integration"
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "template"
    , src = "Makefile.tpl"
    , dest = "Makefile"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies =
  [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
  , { module = "nix-flake", vars = [] : List { name : Text, value : Text } }
  ]
, removable = False
}
