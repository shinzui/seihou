let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/7d02695f5a716384ec2174a018c20ee680ab3d13/package.dhall
        sha256:5a24b98eada6628e3e7da267f4e6c31c1e169179d2bacd5fed7254fc4cc55183

in  S.Blueprint::{
    , name = "adopt-seed-lifecycle"
    , version = Some "0.1.0"
    , description = Some
        "Audit authored modules and adopt Seihou 0.11 project-owned seed files, preserving managed policy, checkout outputs and consumer edits"
    , prompt = ./prompt.md as Text
    , baseModules = [] : List S.Dependency.Type
    , files =
      [ S.Blueprint.BlueprintFile::{
        , src = "seed-lifecycle.md"
        , description = Some
            "Ownership decision table, supported schema pin and runtime, and adoption acceptance scenarios"
        }
      ]
    , migrations =
      [ S.BlueprintMigration::{
        , from = "0.10.1.0"
        , to = "0.11.0.0"
        , prompt = ./migrations/0.10.1.0-to-0.11.0.0.md as Text
        }
      ]
    , tags = [ "seihou", "authoring", "seed", "lifecycle", "migration" ]
    }
