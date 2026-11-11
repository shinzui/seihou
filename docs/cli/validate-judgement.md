# seihou validate-judgement

Validate a judgement and its examples without any model request.

```sh
seihou validate-judgement [TARGET]
```

`TARGET` is a judgement directory, its `judgement.dhall`, or a judgement name found in
`.seihou/modules`, the user modules directory or the install cache. It defaults to
the current directory.

Validation decodes `judgement.dhall`, then checks that names are lowercase with
hyphens, check names and category names are unique, every threshold is between 0
and 1 with the pass value not above the block value, path patterns are
project-relative, and limits are positive. When `examples.json` exists it checks the
format version, unique non-empty ids, project-relative file paths, that every
expected outcome names a declared check, and that every expected finding names a
declared category, one of the example's files and a line of at least 1. Finally, when
gitleaks is available, it scans every example's contents; a hit is an error, because
evaluation sends examples to a model.

Each problem prints a stable code, such as `judgement_threshold_inverted` or
`judgement_example_unknown_category`, and a message naming the part as written. The
command exits nonzero when any problem is found.
