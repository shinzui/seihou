{ name = "structured-basic"
, version = None Text
, description = Some "Test fixture for Structured strategy"
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the project"
    , required = True
    , validation = None Text
    }
  , { name = "project.version"
    , type = "text"
    , default = Some "1.0.0"
    , description = Some "Project version"
    , required = False
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts =
    [] : List
           { var : Text
           , text : Text
           , when : Optional Text
           , choices : Optional (List Text)
           }
, steps =
  [ { strategy = "structured"
    , src = "data.json.gen"
    , dest = "data.json"
    , when = None Text
    , patch = None Text
    }
  , { strategy = "structured"
    , src = "config.yaml.gen"
    , dest = "config.yaml"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
}
