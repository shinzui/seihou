CONFIG

Seihou uses Dhall config files to store variable values that modules can
reference during scaffolding. Config values are organized into scopes, and
the effective config is the merge of all applicable scopes.

CONFIG SCOPES

  Seihou resolves config from four scopes, in priority order:

  1. Local          .seihou/config.dhall in the current project
  2. Namespace      ~/.config/seihou/namespaces/<ns>/config.dhall
  3. Context        ~/.config/seihou/contexts/<ctx>/config.dhall
  4. Global         ~/.config/seihou/config.dhall

  Higher-priority scopes override lower ones. Local config is specific to
  a single project, while global config applies everywhere.

READING AND WRITING CONFIG

  seihou config set project.name my-app          Set a local value
  seihou config get project.name                 Read a value
  seihou config unset project.name               Remove a value
  seihou config list                             List all values in scope
  seihou config list --effective                 Show merged config across all scopes

  Scope flags:

  --global, -g          Target global scope
  --namespace NS, -n    Target a namespace scope
  --context CTX, -c     Target a context scope

  Without any scope flag, commands operate on the local project scope.

INITIALIZATION

  seihou init

  Creates ~/.config/seihou/ with subdirectories for modules, installed
  modules, and a default config.dhall. Safe to run multiple times.

HOW CONFIG FEEDS INTO MODULES

  When you run a module, Seihou resolves each declared variable by
  checking (in order): CLI overrides, config scopes, exported values
  from dependencies, and finally defaults or prompts. Use 'seihou vars
  MODULE --explain' to see where each value comes from.

TYPICAL SETUP

  Set up global defaults that apply everywhere:

    seihou config set author.name "Your Name" --global
    seihou config set author.email "you@example.com" --global
    seihou config set license MIT --global

  Override per-project:

    cd ~/projects/my-app
    seihou config set project.name my-app

  Use namespaces for language-specific defaults:

    seihou config set ghc-version 9.12.2 --namespace haskell
