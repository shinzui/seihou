let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/8415b4b8a746a84eecf982f0f1d7194368bf7b54/package.dhall
        sha256:d19ae156d6c357d982a1aea0f1b6ba1f01d76d2d848545b150db75ed4c39a8a9

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
        , apiSource = None Schema.ApiSource
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
        , apiSource = None Schema.ApiSource
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
        , apiSource = None Schema.ApiSource
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
        , apiSource = None Schema.ApiSource
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
