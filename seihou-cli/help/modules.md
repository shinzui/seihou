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

  Each step in a module uses one of four strategies:

  Copy        Copy a file verbatim from the module to the output.
  Template    Render a Mustache-style template with resolved variables.
  DhallText   Evaluate a Dhall expression that produces Text output.
  Structured  (Reserved for future structured merge support.)

DEPENDENCIES

  Modules can declare dependencies on other modules. When you run a module,
  Seihou loads its dependencies first (topological sort) and resolves
  variables across the full dependency graph. Dependencies can export
  variables for downstream modules to consume.

COMMON COMMANDS

  seihou list                          List all available modules
  seihou new-module my-template        Scaffold a new module
  seihou validate-module ./my-module   Check a module is well-formed
  seihou install <git-url>             Install modules from git
  seihou run <module> --var k=v        Run a module to generate files
