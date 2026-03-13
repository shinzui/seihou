module Seihou.CLI.Completions.Bash
  ( generateBashCompletion,
  )
where

import Data.Text qualified as T
import Seihou.Prelude

generateBashCompletion :: Text
generateBashCompletion =
  T.unlines
    [ "_seihou_completions() {",
      "    local CMDLINE",
      "    local IFS=$'\\n'",
      "    CMDLINE=(--bash-completion-index $COMP_CWORD)",
      "",
      "    for arg in ${COMP_WORDS[@]}; do",
      "        CMDLINE=(${CMDLINE[@]} --bash-completion-word \"$arg\")",
      "    done",
      "",
      "    COMPREPLY=( $(seihou \"${CMDLINE[@]}\" 2>/dev/null) )",
      "}",
      "",
      "complete -o filenames -F _seihou_completions seihou"
    ]
