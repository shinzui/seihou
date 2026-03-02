{ name = "haskell-base"
, description = Some "A Haskell project template"
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Name of the project"
    , required = True
    , validation = Some "[a-z][a-z0-9-]*"
    }
  , { name = "project.version"
    , type = "text"
    , default = Some "0.1.0.0"
    , description = Some "Initial version"
    , required = False
    , validation = None Text
    }
  ]
, exports = [ { var = "project.name", alias = None Text } ]
, prompts =
  [ { var = "project.name"
    , text = "What is the project name?"
    , when = None Text
    , choices = None (List Text)
    }
  ]
, steps =
  [ { strategy = "template"
    , src = "README.md.tpl"
    , dest = "README.md"
    , when = None Text
    }
  , { strategy = "template"
    , src = "src/Lib.hs.tpl"
    , dest = "src/Lib.hs"
    , when = None Text
    }
  , { strategy = "copy"
    , src = "LICENSE"
    , dest = "LICENSE"
    , when = Some "IsSet license"
    }
  ]
, dependencies = [] : List Text
}
