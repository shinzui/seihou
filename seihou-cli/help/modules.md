MODULES

A module is the basic unit of project scaffolding in Seihou. Each module is a
directory containing a module.dhall definition file and optional supporting
files (templates, static files, Dhall expressions).

MODULE SEARCH PATH

  Seihou searches for modules in three locations, in order:

  1. Project modules    .seihou/modules/<name>/
  2. User modules       ~/.config/seihou/modules/<name>/
  3. Installed modules  ~/.config/seihou/installed/<name>/

  The first match wins. Project modules shadow user modules, which shadow
  installed modules.

MODULE STRUCTURE

  A minimal module directory looks like:

    my-module/
      module.dhall        Module definition (required)
      files/              Static and template files
        README.md.tpl     Template file (rendered with variables)
        .gitignore        Static file (copied as-is)

  The module.dhall file declares the module's name, description, variables,
  generation steps, and optional dependencies or exports.

GENERATION STRATEGIES

  Ordinary file steps use one of four content strategies:

  Copy        Copy a file verbatim from the module to the output.
  Template    Render placeholders and {{#if}} blocks with resolved variables.
  DhallText   Evaluate a Dhall expression that produces Text output.
  Structured  Evaluate a Dhall record and serialize JSON/YAML; supports composition.

  The strategy field selects processing; source extensions are conventions.
  A fifth strategy, symlink, is for checkout directory links (see below).

DEPENDENCIES

  Modules can declare dependencies on other modules using the record form:

    dependencies =
      [ { module = "nix-base", vars = [] : List { name : Text, value : Text } }
      ]

  When you run a module, Seihou loads its dependencies first (topological
  sort) and resolves variables across the full dependency graph. Dependencies
  can export variables for downstream modules to consume.

  Dependencies can also supply variable bindings to child modules:

    { module = "nix-flake"
    , vars = [ { name = "nix.system", value = "x86_64-linux" } ]
    }

SCHEMA PACKAGE

  Seihou publishes its Dhall schema at github.com/shinzui/seihou-schema.
  Modules import it via a pinned HTTPS URL with an integrity hash and
  use record completion (::) for concise authoring:

    let S =
          https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
            sha256:<hash>

    in  S.Module::{ name = "my-module"
                  , steps = [ S.Step::{ strategy = "template"
                                      , src = "foo.tpl", dest = "foo" } ]
                  }

  Running `seihou new-module` generates modules in this format.
  Record completion fills in defaults for optional fields automatically.

COMMON COMMANDS

  seihou list                          List all available modules
  seihou new-module my-template        Scaffold a new module
  seihou validate-module ./my-module   Check a module is well-formed
  seihou install <git-url>             Install modules, recipes, blueprints, or prompts from git
  seihou run <module> --var k=v        Run a module to generate files
  seihou update [target]                Update a recorded application and preserve user edits
  seihou remove <module>               Remove an applied module and its files
  seihou schema-upgrade ./my-module    Upgrade module.dhall to current schema

VERSIONING AND MIGRATIONS

  Modules carry a `version` field that follows dotted-version semantics
  (1.0.0, 1.2.3, etc.). When an author bumps a module's version and
  changes its file layout, they can ship migrations alongside the new
  version that move existing project files into the new shape. For a
  recorded application, `seihou update` fetches the newer source, applies
  its migrations, regenerates files, and preserves user edits in one
  operation. Run `seihou help update` for the project workflow or
  `seihou help migrations` for the authoring reference.

STEP LIFECYCLES

  Omitted lifecycle means managed. Some "seed" is accepted for whole-file
  copy/template/dhall-text steps without patches, and schema 8 has seed
  receipts, but create-once handoff behavior is not implemented yet. Do not
  rely on it to preserve a project-owned file across reruns or updates.

CHECKOUT DIRECTORY LINKS

A step with strategy `symlink` and lifecycle `Some "checkout"` declares a link from a real project source directory to an ignored local path. Run records portable intent; `seihou sync` reconstructs it in fresh clones without modules or commands. For example, link `config/editor` to `.editor-local/config` and ignore `.editor-local/`. Links have no patches or content hashes.

Run `seihou help sync` for fresh clones, worktrees and existing tracked-link adoption.
Run `seihou help recipes` for named compositions of modules.
