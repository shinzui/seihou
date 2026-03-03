{ name = "nix-flake"
, description = Some "Nix flake module"
, vars =
  [ { name = "nix.description"
    , type = "text"
    , default = Some "A Nix project"
    , description = Some "Flake description"
    , required = False
    , validation = None Text
    }
  , { name = "nix.system"
    , type = "text"
    , default = None Text
    , description = Some "Target Nix system (inherited from nix-base)"
    , required = True
    , validation = None Text
    }
  ]
, exports = [ { var = "nix.system", alias = None Text } ]
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "template"
    , src = "flake.nix.tpl"
    , dest = "flake.nix"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [ "nix-base" ]
}
