{ name = "Invalid_Module"
, description = None Text
, vars =
  [ { name = "x"
    , type = "text"
    , default = None Text
    , description = None Text
    , required = True
    , validation = None Text
    }
  , { name = "x"
    , type = "bool"
    , default = None Text
    , description = None Text
    , required = False
    , validation = None Text
    }
  ]
, exports = [ { var = "nonexistent", alias = None Text } ]
, prompts =
  [ { var = "undeclared"
    , text = "?"
    , when = None Text
    , choices = None (List Text)
    }
  ]
, steps =
  [ { strategy = "template"
    , src = "missing.tpl"
    , dest = "/absolute/path"
    , when = None Text
    }
  ]
, dependencies = [] : List Text
}
