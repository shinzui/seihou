{ name = "param-dep-parent"
, version = None Text
, description = Some "Parent module that supplies skill.name to its child"
, vars =
  [ { name = "skill.name"
    , type = "text"
    , default = Some "my-skill"
    , description = Some "Name of the skill"
    , required = True
    , validation = None Text
    }
  ]
, exports =
  [ { var = "skill.name", alias = None Text }
  ]
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies =
  [ { module = "param-dep-child"
    , vars = [ { name = "skill.name", value = "my-skill" } ]
    }
  ]
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
