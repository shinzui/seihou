{ name = "haskell-with-nix"
, version = Some "1.0.0"
, description = Some "Haskell project with Nix integration"
, modules =
  [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
  , { module = "nix-flake", vars = [] : List { name : Text, value : Text } }
  ]
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
}
