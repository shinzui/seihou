# Registries and Multi-Module Repositories

A Seihou **registry** lets a single git repository provide multiple modules,
recipes, and blueprints. Instead of one runnable file at the root, you create a
`seihou-registry.dhall` file that lists every item in the repository with its
name, path, description, version, and tags. Users can then browse, filter, and
install individual items — or all of them at once.

This guide covers the registry format, how to create a multi-module repository, and how users interact with it via the CLI. For single-module repositories, see the [Getting Started Guide](getting-started.md).


## When to use a registry

Use a registry when a single repository contains multiple related runnable
items. For example:

- A **language starter kit** with modules for different build tools: `haskell-cabal`, `haskell-stack`, `haskell-nix`
- A **team template collection** with modules for different project types: `api-service`, `cli-tool`, `library`
- A **framework ecosystem** where each module adds a layer: `base`, `testing`, `ci`, `deployment`
- An **agent-guided starter collection** with blueprints for open-ended project shapes: `api-service`, `worker-service`, `frontend-app`

If your repository contains a single module, recipe, or blueprint, you don't
need a registry — just place `module.dhall`, `recipe.dhall`, or
`blueprint.dhall` at the root.


## Repository layout

A multi-module repository looks like this:

```
my-templates/
├── seihou-registry.dhall      # Registry definition (required)
├── modules/
│   ├── haskell-base/
│   │   ├── module.dhall
│   │   └── files/
│   │       └── ...
│   ├── nix-flake/
│   │   ├── module.dhall
│   │   └── files/
│   │       └── ...
│   └── github-ci/
│       ├── module.dhall
│       └── files/
│           └── ...
├── recipes/
│   └── haskell-library/
│       └── recipe.dhall       # Recipe composing modules above
└── blueprints/
    └── api-service/
        ├── blueprint.dhall
        ├── prompt.md
        └── files/
```

Each module is a standard Seihou module directory, each recipe contains a
`recipe.dhall`, and each blueprint contains a `blueprint.dhall` plus its
prompt/reference files. The `seihou-registry.dhall` file at the root tells
Seihou where to find each item.

Item directories can be organized however you like — flat, nested under
`modules/`, `recipes/`, or `blueprints/`, grouped by category. The `path` field
in each registry entry points to the directory relative to the repository root.


## The seihou-registry.dhall format

```dhall
{ repoName = "my-templates"
, repoDescription = Some "A collection of project templates"
, modules =
  [ { name = "haskell-base"
    , version = Some "1.0.0"
    , path = "modules/haskell-base"
    , description = Some "Base Haskell project with cabal"
    , tags = [ "haskell", "cabal" ]
    }
  , { name = "nix-flake"
    , version = Some "0.4.0"
    , path = "modules/nix-flake"
    , description = Some "Nix flake with devShell"
    , tags = [ "nix", "devops" ]
    }
  , { name = "github-ci"
    , version = Some "0.2.0"
    , path = "modules/github-ci"
    , description = Some "GitHub Actions CI workflow"
    , tags = [ "ci", "github" ]
    }
  ]
, recipes =
  [ { name = "haskell-library"
    , version = Some "0.1.0"
    , path = "recipes/haskell-library"
    , description = Some "Haskell library with Nix + Cabal"
    , tags = [ "haskell", "nix" ]
    }
  ]
, blueprints =
  [ { name = "api-service"
    , version = Some "0.1.0"
    , path = "blueprints/api-service"
    , description = Some "Agent-guided API service starter"
    , tags = [ "api", "agent" ]
    }
  ]
}
```

Keep entry `version` fields in sync with each module's `module.dhall` /
`recipe.dhall` / `blueprint.dhall` by running
[`seihou registry sync-versions`](../cli/registry.md).

### Fields

**repoName** (Text, required): A display name for the repository, shown in browse and install output.

**repoDescription** (Optional Text): A one-line description of the repository. Use `Some "description"` or `None Text`.

**modules** (List, required): The list of module entries. Each entry has:

| Field | Type | Description |
|-------|------|-------------|
| `name` | Text | Module identifier. Must match `[a-z][a-z0-9-]*`. |
| `version` | Optional Text | Declared version of the entry, copied from the underlying `module.dhall`, `recipe.dhall`, or `blueprint.dhall`. Populated by `seihou registry sync-versions`. Optional but recommended — tooling reads this instead of evaluating each item. |
| `path` | Text | Relative path from the repository root to the module directory. Must not start with `/` or contain `..`. |
| `description` | Optional Text | Human-readable description shown in browse output. |
| `tags` | List Text | Tags for filtering. Users can filter with `--tag` when browsing. |

**recipes** (List, optional): Recipe entries, using the same format as module entries. Each entry points to a directory containing `recipe.dhall` instead of `module.dhall`. The `recipes` field defaults to an empty list, so existing registry files without it continue to work.

**blueprints** (List, optional): Blueprint entries, using the same format as module entries. Each entry points to a directory containing `blueprint.dhall`. The `blueprints` field defaults to an empty list for backwards compatibility.

Modules, recipes, and blueprints share one namespace — no name may appear in more than one list.


## Browsing a repository

The `seihou browse` command clones a repository into a temporary directory and shows what's available — without installing anything:

```sh
seihou browse https://github.com/user/my-templates.git
```

For a multi-module repository, the output shows the registry listing:

```
my-templates
A collection of project templates

Available modules, recipes, and blueprints:

  haskell-base   Base Haskell project with cabal  [haskell, cabal]
  nix-flake      Nix flake with devShell  [nix, devops]
  github-ci      GitHub Actions CI workflow  [ci, github]
  api-service    Agent-guided API service starter  [api, agent] [blueprint]

4 items available. Install with:
  seihou install https://github.com/user/my-templates.git --module <name>
  seihou install https://github.com/user/my-templates.git --all
```

### Filtering by tag

Use `--tag` to show only items with a specific tag:

```sh
seihou browse https://github.com/user/my-templates.git --tag haskell
```

```
my-templates
A collection of project templates

Available modules, recipes, and blueprints:

  haskell-base   Base Haskell project with cabal  [haskell, cabal]

1 item available. Install with:
  seihou install https://github.com/user/my-templates.git --module <name>
  seihou install https://github.com/user/my-templates.git --all
```

### Single-item repositories

If the repository has no `seihou-registry.dhall` but has a `module.dhall` at the root, browse shows a simpler output:

```
haskell-base
  Base Haskell project with cabal

Single-module repository. Install with:
  seihou install https://github.com/user/haskell-base.git
```

Similarly, repositories containing a `recipe.dhall` or `blueprint.dhall` (but no
registry and no higher-priority runnable file) are detected as single-recipe or
single-blueprint repositories.


## Installing from a registry

### Install specific items

Use `--module` (repeatable) to install specific modules, recipes, or blueprints:

```sh
seihou install https://github.com/user/my-templates.git --module haskell-base --module nix-flake
```

Each selected item is validated and copied to `~/.config/seihou/installed/<name>/`.

### Install all items

Use `--all` to install every module, recipe, and blueprint in the registry:

```sh
seihou install https://github.com/user/my-templates.git --all
```

### Interactive selection

If you run `seihou install` on a multi-module repository without `--module` or `--all`, Seihou prompts you to choose:

```sh
seihou install https://github.com/user/my-templates.git
```

```
my-templates — A collection of project templates

Available modules, recipes, and blueprints:
  1) haskell-base   Base Haskell project with cabal
  2) nix-flake      Nix flake with devShell
  3) github-ci      GitHub Actions CI workflow
  4) api-service    Agent-guided API service starter

Enter item numbers to install (comma-separated), or 'all':
```

### Origin tracking

When items are installed from a registry, Seihou writes a `.seihou-origin.json`
file alongside each installed directory. This records the source URL,
repository name, kind, version, and tags. The `seihou list` command uses this
to show where installed items came from:

```
Available modules, recipes, and blueprints:

  haskell-base   Base Haskell project with cabal   (installed: my-templates)
  nix-flake      Nix flake with devShell           (installed: my-templates)
  api-service    Agent-guided API service starter  (installed: my-templates [blueprint])
  my-local-mod   A local module                    (user)

4 items found (3 sources searched)
```

### Overriding the install name

For single-module repositories, use `--name` to override the installed module name:

```sh
seihou install https://github.com/user/haskell-base.git --name my-haskell
```


## Creating a registry

### Step 1: Organize your items

Create a directory for each module, recipe, or blueprint. A common convention is
to put them under `modules/`, `recipes/`, and `blueprints/` directories, but any
layout works.

### Step 2: Write seihou-registry.dhall

Create `seihou-registry.dhall` at the repository root. List every item with its path relative to the root:

```dhall
{ repoName = "my-templates"
, repoDescription = Some "Project templates for my team"
, modules =
  [ { name = "api-service"
    , path = "modules/api-service"
    , description = Some "REST API service scaffold"
    , tags = [ "backend", "api" ]
    }
  , { name = "cli-tool"
    , path = "modules/cli-tool"
    , description = Some "Command-line tool scaffold"
    , tags = [ "cli" ]
    }
	  ]
, recipes = [] : List { name : Text, path : Text, description : Optional Text, tags : List Text }
, blueprints = [] : List { name : Text, path : Text, description : Optional Text, tags : List Text }
}
```

### Step 3: Validate each item

Validate each item individually to catch errors before publishing:

```sh
seihou validate-module modules/api-service
seihou validate-module modules/cli-tool
seihou validate-blueprint blueprints/api-service
```

### Step 4: Test with browse

Push to a git remote and test that browsing works:

```sh
seihou browse https://github.com/your-org/my-templates.git
```

Verify the output shows all your items with correct descriptions and tags.


## Keeping versions in sync

Every registry entry has an optional `version` field that should match the
version declared in the item's `module.dhall`, `recipe.dhall`, or
`blueprint.dhall`. Tooling (`seihou browse`, `seihou outdated`) reads the
registry `version` when present and falls back to evaluating each item only
when it isn't — so a populated registry saves N Dhall evaluations per repo.

Maintain the field with `seihou registry sync-versions`:

```sh
cd my-templates
seihou registry sync-versions --dry-run
seihou registry sync-versions
```

See [`docs/cli/registry.md`](../cli/registry.md) for flags and CI usage.
`seihou browse` and `seihou install` print a warning line per out-of-sync
entry when they detect drift — they don't block, but the warning is a hint
to run `registry sync-versions` before your next push.

For a single one-shot check that catches both version drift *and*
structural issues like a renamed module directory or an illegal path,
run `seihou registry validate`. The command exits non-zero on any
problem and is suitable for CI. See `docs/cli/registry.md` for the full
option reference.


## Registry validation

When Seihou loads a `seihou-registry.dhall`, it validates each entry:

- **Name format**: Must match `[a-z][a-z0-9-]*`.
- **Path safety**: Must be a relative path (no leading `/`) and must not contain `..`.
- **Item existence**: Module entries must contain `module.dhall`; recipe entries must contain `recipe.dhall`; blueprint entries must contain `blueprint.dhall`.
- **No name collisions**: No name may appear in more than one of the `modules`, `recipes`, and `blueprints` lists.

If the registry file exists but fails to parse, Seihou falls back to checking
for root runnable files. If none are found, the repository is reported as empty.


## Discovery order

When Seihou examines a cloned repository, it checks in this order:

1. **seihou-registry.dhall** — If present and valid, the repo is treated as a multi-module registry.
2. **module.dhall** (at root) — If present, the repo is treated as a single-module repository.
3. **recipe.dhall** (at root) — If present, the repo is treated as a single-recipe repository.
4. **blueprint.dhall** (at root) — If present, the repo is treated as a single-blueprint repository.
5. **None of the above** — The repo is empty and Seihou reports an error.

The registry file always takes precedence. If both `seihou-registry.dhall` and a root `module.dhall` exist, only the registry is used. If a single-item repository contains multiple runnable files, discovery prefers `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`.


## Tags best practices

Tags help users find relevant items when browsing large registries. Some conventions:

- **Language**: `haskell`, `python`, `rust`, `typescript`
- **Tool**: `cabal`, `nix`, `docker`, `github-actions`
- **Domain**: `backend`, `frontend`, `cli`, `library`
- **Purpose**: `ci`, `devops`, `testing`, `deployment`

Keep tags lowercase and use hyphens for multi-word tags (`github-actions`, not `GitHub Actions`). An item can have any number of tags.


## Modules within a registry can compose

Modules in a registry can declare dependencies on each other, just like any other Seihou modules. For example, `haskell-with-nix` can depend on both `haskell-base` and `nix-flake`:

```dhall
-- modules/haskell-with-nix/module.dhall
{ name = "haskell-with-nix"
, dependencies = [ "haskell-base", "nix-flake" ]
, ...
}
```

When a user installs `haskell-with-nix`, they should also install its dependencies. Seihou resolves the dependency graph at run time from the user's installed modules.


## Blueprints in registries

Blueprints are installed and listed like modules and recipes, but they run
through `seihou agent run`:

```sh
seihou install https://github.com/user/my-templates.git --module api-service
seihou agent run api-service --var project.name=payments
```

Their `baseModules` can reference modules and recipes from the same installed
set, but a blueprint cannot use another blueprint as a baseline.

See [Agent-Driven Blueprints](blueprints.md) for the authoring guide.


## Migrations in registries

Migrations are declared on each module's own `module.dhall`, not on
the registry. The version field that drives chain selection comes
from the **module** (i.e. `RegistryEntry.version` is used by
`seihou outdated` and `seihou upgrade` to decide *whether* to upgrade,
but the chain itself is computed from the per-module
`migrations` list once the upgraded module is on disk).

In practice, this means a module author who ships migrations does so
the same way whether they live alone in a single-module repo or
alongside siblings in a registry. Consumers run
`seihou migrate <module>` regardless of where the module came from.

See [migrations.md](migrations.md) for the full reference, or run
`seihou help migrations` for the in-binary version.


## Next steps

- Read the [Module Authoring Reference](module-authoring.md) for the complete module format and all generation strategies.
- Read [Agent-Driven Blueprints](blueprints.md) for blueprint authoring and agent-runner behavior.
- Read [Configuration and Variable Resolution](config-and-variables.md) for details on how variable values flow through the config hierarchy.
- Explore the test fixtures at `seihou-core/test/fixtures/` for working examples of module composition.
