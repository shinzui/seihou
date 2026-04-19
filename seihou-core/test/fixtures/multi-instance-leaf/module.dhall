{ name = "multi-instance-leaf"
, version = Some "1.0.0"
, description = Some "Leaf module that pulls in the helper bound to skill.name = \"leaf\""
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies =
  [ { module = "multi-instance-helper"
    , vars = [ { name = "skill.name", value = "leaf" } ]
    }
  ]
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
