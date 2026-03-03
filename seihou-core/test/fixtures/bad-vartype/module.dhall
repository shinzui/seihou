{ name = "bad-vartype"
, description = None Text
, vars =
  [ { name = "project.name"
    , type = "strng"
    , default = None Text
    , description = None Text
    , required = True
    , validation = None Text
    }
  ]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
, dependencies = [] : List Text
}
