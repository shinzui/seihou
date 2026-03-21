-- | Interactive prompt for collecting variable values.
--
-- Required fields (no default): var, text
-- Usage: Prompt::{ var = "project.name", text = "What is your project name?" }

{ Type =
    { var : Text
    , text : Text
    , when : Optional Text
    , choices : Optional (List Text)
    }
, default =
    { when = None Text
    , choices = None (List Text)
    }
}
