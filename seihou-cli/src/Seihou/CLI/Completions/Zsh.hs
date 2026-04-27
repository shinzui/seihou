module Seihou.CLI.Completions.Zsh
  ( generateZshCompletion,
  )
where

import Data.Text qualified as T
import Seihou.Prelude

generateZshCompletion :: Text
generateZshCompletion =
  T.unlines
    [ "#compdef seihou",
      "",
      "_seihou() {",
      "    local -a completions",
      "    local CMDLINE",
      "    local IFS=$'\\n'",
      "",
      "    CMDLINE=(--bash-completion-enriched --bash-completion-index $((CURRENT - 1)))",
      "",
      "    for arg in ${words[@]}; do",
      "        CMDLINE=(${CMDLINE[@]} --bash-completion-word \"$arg\")",
      "    done",
      "",
      "    local line",
      "    for line in $(seihou \"${CMDLINE[@]}\" 2>/dev/null); do",
      "        local word=${line%%$'\\t'*}",
      "        local desc=${line#*$'\\t'}",
      "        if [[ \"$word\" != \"$desc\" ]]; then",
      "            completions+=(\"${word//:/\\\\:}:${desc}\")",
      "        else",
      "            completions+=(\"$word\")",
      "        fi",
      "    done",
      "",
      "    if [[ ${#completions[@]} -gt 0 ]]; then",
      "        _describe 'seihou' completions",
      "    fi",
      "}",
      "",
      "_seihou"
    ]
