{ name = "structured-merge-a"
, version = None Text
, description = Some "Creates a base config.json"
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "structured"
    , src = "config.dhall"
    , dest = "config.json"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
}
