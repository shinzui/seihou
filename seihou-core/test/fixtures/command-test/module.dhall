{ name = "command-test"
, version = None Text
, description = Some "Test module with commands"
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the project"
    , required = True
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps =
  [ { strategy = "template"
    , src = "README.md.tpl"
    , dest = "README.md"
    , when = None Text
    , patch = None Text
    }
  ]
, commands =
  [ { run = "echo {{project.name}}"
    , workDir = None Text
    , when = None Text
    }
  , { run = "echo conditional"
    , workDir = None Text
    , when = Some "IsSet project.name"
    }
  ]
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
}
