{ name = "structured-merge-b"
, description = Some "Adds keys to the same config.json via Structured strategy"
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "structured"
    , src = "config-extra.dhall"
    , dest = "config.json"
    , when = None Text
    , patch = None Text
    }
  ]
, dependencies = ["structured-merge-a"]
}
