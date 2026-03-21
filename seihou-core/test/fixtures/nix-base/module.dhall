{ name = "nix-base"
, version = None Text
, description = Some "Base Nix module"
, vars =
  [ { name = "nix.system"
    , type = "text"
    , default = Some "x86_64-linux"
    , description = Some "Target Nix system"
    , required = False
    , validation = None Text
    }
  ]
, exports = [ { var = "nix.system", alias = None Text } ]
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "template"
    , src = "shell.nix.tpl"
    , dest = "shell.nix"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
, removable = False
}
