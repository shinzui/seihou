{ name = "haskell-pinned"
, version = Some "1.0.0"
, description = Some "Haskell with pinned nix system"
, modules =
  [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
  , { module = "nix-flake", vars = [ { name = "nix.system", value = "aarch64-darwin" } ] }
  ]
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
}
