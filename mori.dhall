let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/93104153ecf8817547229a867302a70a25c4b3d8/package.dhall
        sha256:5e00bba267f27069df1d3caadfec2ec6a8c4e797ce652d78c09528f981b71b42

in  Schema.Project::{ project =
      Schema.ProjectIdentity::{ name = "seihou"
      , namespace = "shinzui"
      , type = Schema.PackageType.Application
      , description = Some
          "Composable, type-safe project scaffolding system"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "Developer Tooling", "Code Generation" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{ name = "seihou"
        , github = Some "shinzui/seihou"
        }
      ]
    , packages =
      [ Schema.Package::{ name = "seihou-core"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "seihou-core"
        , description = Some "Core library for Seihou project scaffolding"
        }
      , Schema.Package::{ name = "seihou-cli"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "seihou-cli"
        , description = Some "CLI for Seihou project scaffolding"
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core" ]
        }
      , Schema.Package::{ name = "seihou-core-test"
        , type = Schema.PackageType.Other "TestSuite"
        , language = Schema.Language.Haskell
        , path = Some "seihou-core/test"
        , description = Some "Tests for seihou-core"
        , visibility = Schema.Visibility.Internal
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core" ]
        }
      , Schema.Package::{ name = "seihou-cli-test"
        , type = Schema.PackageType.Other "TestSuite"
        , language = Schema.Language.Haskell
        , path = Some "seihou-cli/test"
        , description = Some "Tests for seihou-cli"
        , visibility = Schema.Visibility.Internal
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core"
          , Schema.Dependency.ByName "shinzui/seihou:seihou-cli"
          ]
        }
      ]
    , dependencies =
      [ "effectful/effectful"
      , "pcapriotti/optparse-applicative"
      , "shinzui/seihou-schema"
      ]
    , skills =
      [ Schema.Skill::{ name = "update-seihou-schema"
        , description = "Update Seihou Schema"
        , path = Some "claude/skills/update-seihou-schema"
        }
      , Schema.Skill::{ name = "seihou-update-docs"
        , description =
            "Update seihou documentation after code changes"
        , path = Some "claude/skills/seihou-update-docs"
        }
      ]
    , docs =
      [ Schema.DocRef::{ key = "architecture"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.Internal
        , description = Some
            "System architecture, execution pipeline, effect stack"
        , location =
            Schema.DocLocation.LocalFile
              "docs/dev/architecture/overview.md"
        }
      , Schema.DocRef::{ key = "roadmap"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Internal
        , description = Some "V1 implementation milestones (M0-M6)"
        , location =
            Schema.DocLocation.LocalFile "docs/dev/roadmap/v1-milestones.md"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{ name = "improvement-requests"
        , path = "docs/improvement-requests"
        , okfVersion = "0.2"
        , profile = Some "docs/improvement-requests/profile.dhall"
        , description = Some
            "Cross-repository requests raised against seihou by the projects that consume it"
        }
      ]
    }
