let Entry =
      { name : Text
      , version : Optional Text
      , path : Text
      , description : Optional Text
      , tags : List Text
      }

in  { repoName = "seihou"
    , repoDescription = Some
        "Release migrations and authoring blueprints for Seihou"
    , modules = [] : List Entry
    , recipes = [] : List Entry
    , blueprints =
      [ { name = "adopt-seed-lifecycle"
        , version = Some "0.1.0"
        , path = "blueprints/adopt-seed-lifecycle"
        , description = Some
            "Audit authored modules and adopt project-owned seed files introduced in Seihou 0.11"
        , tags = [ "seihou", "authoring", "seed", "lifecycle", "migration" ]
        }
      ]
    , prompts = [] : List Entry
    }
