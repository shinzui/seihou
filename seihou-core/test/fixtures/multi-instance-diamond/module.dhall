{ name = "multi-instance-diamond"
, version = Some "1.0.0"
, description = Some "Diamond root: depends on the leaf (which binds skill.name=\"leaf\") and also directly on the helper (skill.name=\"diamond\"), so the helper is invoked twice"
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies =
  [ { module = "multi-instance-leaf"
    , vars = [] : List { name : Text, value : Text }
    }
  , { module = "multi-instance-helper"
    , vars = [ { name = "skill.name", value = "diamond" } ]
    }
  ]
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
