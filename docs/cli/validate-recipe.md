# seihou validate-recipe

Validate a local recipe descriptor without running its composition.

## Usage

```sh
seihou validate-recipe [PATH]
```

`PATH` is a directory containing `recipe.dhall`. It defaults to the current
directory. Paths containing spaces work with ordinary shell quoting:

```sh
seihou validate-recipe './my stack'
```

No configuration, registry, installed modules, or variable values are required.
Required variables without defaults are valid. The command never asks questions,
executes member commands, generates project files, or installs members. A successful
check prints `Recipe 'my-stack' is valid.`; it validates the descriptor, not the
availability or behavior of its members.

## Checks

The command evaluates Dhall and checks field shapes, variable types and defaults,
and condition syntax. It also checks the recipe name, a nonempty module list,
unique members, binding-name syntax, unique variable declarations, declared prompt
targets, and declared variable references throughout nested prompt conditions.
Semantic failures are reported together with their fields and affected names.

Member bindings remain literal text and may name variables declared only by member
modules. This command does not inspect member schemas, require answers, evaluate
prompt conditions, or check prompt ordering or cycles. Existing recipes with empty
`vars` and `prompts` remain valid.

Dhall imports are evaluated normally: descriptor-authored remote imports may use
the network or the Dhall cache. A self-contained descriptor or local imports can
be validated offline with an empty cache. Missing imports are loading errors;
they never trigger module installation. Validation does not modify project files
or Seihou configuration/install state; normal Dhall evaluator caching may occur.

## CI and exit codes

Use the same command with stdin closed; no special CI flag is needed:

```sh
seihou validate-recipe ./my-stack </dev/null
```

| Exit | Meaning |
|------|---------|
| 0 | Recipe descriptor is valid |
| 1 | Descriptor cannot be read/evaluated/decoded or fails semantic checks |
| 4 | No `recipe.dhall` found in the selected directory |

Correct the named field or import and rerun the command.

## Authoring and composition

```sh
seihou new-recipe my-stack --module unpublished-member
seihou validate-recipe ./my-stack
```

`seihou registry validate` checks published entry metadata. `validate-recipe`
checks a descriptor directly. Once its members are available through normal search
paths, `seihou run my-stack --dry-run` resolves values and previews composition;
it may need answers. These checks answer different questions.
