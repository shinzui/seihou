module Seihou.CLI.Completions.Fish
  ( generateFishCompletion,
  )
where

import Data.Text qualified as T
import Seihou.Prelude

generateFishCompletion :: Text
generateFishCompletion =
  T.unlines
    [ "# Disable file completion by default",
      "complete -c seihou -f",
      "",
      "function __seihou_complete",
      "    set -l tokens (commandline -cop)",
      "    set -l current (commandline -ct)",
      "    set -l index (count $tokens)",
      "",
      "    set -l args --bash-completion-enriched --bash-completion-index $index",
      "    for token in $tokens",
      "        set args $args --bash-completion-word $token",
      "    end",
      "    set args $args --bash-completion-word \"$current\"",
      "",
      "    for line in (seihou $args 2>/dev/null)",
      "        # Split on tab: word<TAB>description",
      "        set -l parts (string split \\t -- $line)",
      "        if test (count $parts) -ge 2",
      "            printf '%s\\t%s\\n' $parts[1] $parts[2]",
      "        else",
      "            echo $line",
      "        end",
      "    end",
      "end",
      "",
      "complete -c seihou -a '(__seihou_complete)'"
    ]
