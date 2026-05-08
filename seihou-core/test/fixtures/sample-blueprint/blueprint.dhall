{ name = "sample-blueprint"
, version = Some "0.1.0"
, description = Some "Fixture blueprint for EP-29 tests"
, prompt =
    ''
    Scaffold a project for {{project.name}} using {{language}}.
    Reference example.md for the conventions to mirror.
    ''
, vars =
  [ { name = "project.name"
    , type = "text"
    , default = None Text
    , description = Some "Project name"
    , required = True
    , validation = None Text
    }
  , { name = "language"
    , type = "text"
    , default = Some "haskell"
    , description = None Text
    , required = False
    , validation = None Text
    }
  ]
, prompts =
    [] : List
           { var : Text
           , text : Text
           , when : Optional Text
           , choices : Optional (List Text)
           }
, baseModules =
    [] : List { module : Text, vars : List { name : Text, value : Text } }
, files = [ { src = "example.md", description = Some "Example reference snippet" } ]
, allowedTools = None (List Text)
, tags = [ "demo" ]
}
