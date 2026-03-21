-- | Generation step — describes a file to generate.
--
-- Required fields (no default): strategy, src, dest
-- Usage: Step::{ strategy = "template", src = "README.md.tpl", dest = "README.md" }

{ Type =
    { strategy : Text
    , src : Text
    , dest : Text
    , when : Optional Text
    , patch : Optional Text
    }
, default =
    { when = None Text
    , patch = None Text
    }
}
