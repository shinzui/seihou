CONTEXTS

Contexts let you maintain separate configurations for different environments
— for example, "work" and "personal" — so that variables like author.email
resolve to different values depending on which context is active.

HOW CONTEXTS WORK

  A context is a named directory under ~/.config/seihou/contexts/ containing
  a config.dhall file:

    ~/.config/seihou/contexts/work/config.dhall
    ~/.config/seihou/contexts/personal/config.dhall

  When a context is active, its config values participate in variable
  resolution alongside local and global config. This means you can set
  author.email = "me@work.com" in your work context and
  author.email = "me@home.com" in your personal context.

SETTING AND CLEARING CONTEXTS

  seihou context set work              Set project context (writes .seihou/context)
  seihou context default personal      Set global default (~/.config/seihou/default-context)
  seihou context show                  Show active context and its source
  seihou context clear                 Remove project context
  seihou context clear-default         Remove global default

RESOLUTION CHAIN

  Seihou determines the active context by checking:

  1. Project context     .seihou/context file in the current directory
  2. Global default      ~/.config/seihou/default-context
  3. None                No context is active

  The project context takes priority, so you can have a global default of
  "personal" but override it to "work" in specific project directories.

TYPICAL USE CASE

  Set up two contexts with different author info:

    seihou config set author.name "Work Name" --context work
    seihou config set author.email "me@work.com" --context work
    seihou config set author.name "Personal Name" --context personal
    seihou config set author.email "me@home.com" --context personal

  Then in a work project:

    cd ~/work/my-project
    seihou context set work
    seihou run haskell-base    # uses work author info

  And in a personal project:

    cd ~/personal/my-project
    seihou context set personal
    seihou run haskell-base    # uses personal author info
