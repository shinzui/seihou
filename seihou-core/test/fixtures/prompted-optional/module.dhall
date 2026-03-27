{ name = "prompted-optional"
, version = Some "1.0.0"
, description = Some "Demonstrates required and optional prompted variables"
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the project"
    , required = True
    , validation = Some "[a-z][a-z0-9-]*"
    }
  , { name = "license"
    , type = "text"
    , default = None Text
    , description = Some "License type (optional)"
    , required = False
    , validation = None Text
    }
  , { name = "enable.ci"
    , type = "bool"
    , default = None Text
    , description = Some "Enable GitHub Actions CI"
    , required = False
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts =
  [ { var = "project.name"
    , text = "What is the project name?"
    , when = None Text
    , choices = None (List Text)
    }
  , { var = "license"
    , text = "Include a license?"
    , when = None Text
    , choices = Some [ "MIT", "Apache-2.0", "BSD-3-Clause" ]
    }
  , { var = "enable.ci"
    , text = "Enable GitHub Actions CI?"
    , when = None Text
    , choices = None (List Text)
    }
  ]
, steps =
  [ { strategy = "template"
    , src = "README.md.tpl"
    , dest = "README.md"
    , when = None Text
    , patch = None Text
    }
  ]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
