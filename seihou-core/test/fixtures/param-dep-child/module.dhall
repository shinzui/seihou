{ name = "param-dep-child"
, version = None Text
, description = Some "Child module that requires skill.name from its parent"
, vars =
  [ { name = "skill.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the skill"
    , required = True
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
, removable = False
}
