let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/58523ea11e120f3be1c978e509d67f51311a8280/package.dhall
        sha256:e4acbb565c9f4e4b3831dabf084e50f8687dda780b7874ced90ae88d6f349f4f

in  { project =
      { name = "seihou"
      , namespace = "shinzui"
      , type = Schema.PackageType.Application
      , description = Some
          "Composable, type-safe project scaffolding system"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "Developer Tooling", "Code Generation" ]
      , owners = [ "shinzui" ]
      , origin = Schema.Origin.Own
      }
    , repos =
      [ { name = "seihou"
        , github = Some "shinzui/seihou"
        , gitlab = None Text
        , git = None Text
        , localPath = None Text
        }
      ]
    , packages =
      [ { name = "seihou-core"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "seihou-core"
        , description = Some "Core library for Seihou project scaffolding"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Public
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Schema.Dependency
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        }
      , { name = "seihou-cli"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "seihou-cli"
        , description = Some "CLI for Seihou project scaffolding"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Public
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        }
      , { name = "seihou-core-test"
        , type = Schema.PackageType.Other "TestSuite"
        , language = Schema.Language.Haskell
        , path = Some "seihou-core/test"
        , description = Some "Tests for seihou-core"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Internal
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        }
      , { name = "seihou-cli-test"
        , type = Schema.PackageType.Other "TestSuite"
        , language = Schema.Language.Haskell
        , path = Some "seihou-cli/test"
        , description = Some "Tests for seihou-cli"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Internal
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/seihou:seihou-core"
          , Schema.Dependency.ByName "shinzui/seihou:seihou-cli"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        }
      ]
    , bundles = [] : List Schema.PackageBundle
    , dependencies =
      [ "effectful/effectful"
      , "pcapriotti/optparse-applicative"
      , "shinzui/seihou-schema"
      ]
    , apis = [] : List Schema.Api
    , agents = [] : List Schema.AgentHint
    , skills =
      [ { name = "update-seihou-schema"
        , description = "Update Seihou Schema"
        , path = Some "claude/skills/update-seihou-schema"
        , tools = [] : List Schema.SkillTool
        , compatibility = None Text
        , metadata = [] : List { mapKey : Text, mapValue : Text }
        }
      , { name = "seihou-update-docs"
        , description =
            "Update seihou documentation after code changes"
        , path = Some "claude/skills/seihou-update-docs"
        , tools = [] : List Schema.SkillTool
        , compatibility = None Text
        , metadata = [] : List { mapKey : Text, mapValue : Text }
        }
      ]
    , subagents = [] : List Schema.Subagent
    , standards = [] : List Text
    , docs =
      [ { key = "architecture"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.Internal
        , description = Some
            "System architecture, execution pipeline, effect stack"
        , location =
            Schema.DocLocation.LocalFile
              "docs/dev/architecture/overview.md"
        }
      , { key = "roadmap"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Internal
        , description = Some "V1 implementation milestones (M0-M6)"
        , location =
            Schema.DocLocation.LocalFile "docs/dev/roadmap/v1-milestones.md"
        }
      ]
    }
