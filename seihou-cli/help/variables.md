VARIABLES

Variables are named, typed values that modules use to customize generated
output. They are declared in module.dhall and resolved at generation time
from multiple sources.

DECLARING VARIABLES

  Each variable in module.dhall has:

    name         Dotted name like "project.name" or "author.email"
    type         Text (the only type currently supported)
    default      Optional default value
    description  Human-readable explanation (shown in prompts)

  Variables without defaults are required — Seihou will prompt for them
  interactively or fail if no value is available.

RESOLUTION ORDER

  When resolving a variable's value, Seihou checks these sources in order:

  1. CLI overrides       --var project.name=my-app
  2. Config values       From config.dhall (local, namespace, or global)
  3. Context values      From the active context's config.dhall
  4. Exported values     From dependency modules that export the variable
  5. Default value       Declared in module.dhall
  6. Interactive prompt  If running in a TTY, prompt the user

  The first source that provides a value wins.

EXPORTS

  A module can export variables so that dependent modules can use them.
  Exports are declared in module.dhall and make a variable's resolved value
  available to any module that depends on this one.

INSPECTING VARIABLES

  seihou vars <module>                 List declared variables
  seihou vars <module> --explain       Show resolved values with provenance
  seihou vars <module> --var k=v       Supply values for resolution

  The --explain flag is especially useful for debugging: it shows where each
  variable's value came from (CLI, config, default, export, etc.).

NAMESPACING

  When composing multiple modules, variables are scoped by module namespace
  to avoid collisions. The namespace defaults to the module name but can be
  overridden with --namespace. Config keys under a namespace are looked up
  as namespace.variable.name.
