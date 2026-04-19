TEMPLATING

The Template strategy is the middle rung of Seihou's four generation
strategies. It is dispatched by the .tpl file extension and gives a step
two powers: replace {{variable.name}} with the resolved value, and gate
regions of text on a boolean expression via {{#if ...}} blocks.

Templates stay intentionally dumb. Anything richer -- loops, arithmetic,
derived values, multi-way branching -- belongs to the DhallText strategy,
which evaluates a full Dhall expression after placeholder substitution.
When a template starts fighting you, switch the step to dhall-text rather
than contort the template.

PLACEHOLDERS

  Syntax:

    {{variable.name}}      standard form
    {{ variable.name }}    surrounding whitespace inside the braces is ignored
    \{{variable.name}}     literal "{{variable.name}}" in output (escape)

  Variable names match [a-zA-Z][a-zA-Z0-9._-]*. Dots are part of the
  name, not structural.

  Coercion from the resolved value to text:

    VText  "hello"       -> hello
    VBool  True          -> true
    VBool  False         -> false
    VInt   42            -> 42
    VList  ["a", "b"]    -> a,b         (comma-separated, recursive)

  Placeholder substitution runs in three positions:

    Template bodies   the .tpl file contents
    Destination path  the `dest` field of a step
    Shell commands    the `run` and `workDir` fields of command steps

ESCAPING {{

  \{{ is consumed and emits a literal {{ in the output. There is no
  corresponding \}} escape -- unmatched closers are emitted verbatim.

    Use \{{name}} for placeholders   ->   Use {{name}} for placeholders

  The escape applies to placeholder syntax only. There is no escape
  for block tags; a template cannot emit a literal {{#if sequence.
  Use the DhallText strategy when that is required.

CONDITIONAL BLOCKS

  Inline blocks gate regions of a template body on a boolean expression:

    {{#if EXPR}} ... {{/if}}
    {{#if EXPR}} ... {{#else}} ... {{/if}}

  Blocks nest to arbitrary depth; a {{/if}} always pairs with its
  nearest open {{#if}}.

  Only the selected branch is expanded. The untaken branch's text is
  discarded before it reaches the placeholder engine. Unresolved
  placeholders and malformed sub-expressions inside the untaken branch
  therefore do not produce errors. This is deliberate: it lets authors
  gate optional features without having to declare every variable
  referenced inside the gate.

  Conditional blocks work in template bodies only. They do NOT work in
  `dest`, `run`, or `workDir`; those positions accept placeholders only
  and will treat {{#if}} as a placeholder name that fails to resolve.
  The dhall-text and structured strategies express conditionals with
  Dhall's own if/then/else after placeholder substitution.

EXPRESSION LANGUAGE

  The grammar used by {{#if ...}} (and by step-level `when` clauses):

    expr     = or_expr
    or_expr  = and_expr  ("||" and_expr)*
    and_expr = not_expr  ("&&" not_expr)*
    not_expr = "!" atom  |  atom
    atom     = "IsSet" NAME
             | "Eq"    NAME VALUE
             | "(" expr ")"
             | "true"  |  "false"
    VALUE    = "quoted string"  |  bareWord

  IsSet foo        true iff foo has a resolved value.
  Eq foo VALUE     true iff foo's value equals VALUE. Values are
                   type-sensitive: a bool variable compares against
                   bare-word true/false, not against quoted "true".
                   A text variable compares against a quoted string.
  && || !          the usual boolean operators.
  ( ... )          parentheses group sub-expressions.
  true / false     literal constants.

STANDALONE TAG WHITESPACE

  A block tag is standalone on its line when everything before it on
  the line is spaces or tabs (or the line starts with the tag) AND
  everything after it is spaces or tabs followed by a newline (or the
  template ends). A standalone tag absorbs its leading indent and one
  trailing newline. A tag that shares a line with other content keeps
  all surrounding whitespace verbatim.

  So the readable form:

    prev
      {{#if Eq flag true}}
      body
      {{/if}}
    next

  emits `prev\n  body\nnext\n` when flag = True and `prev\nnext\n`
  when flag = False -- no blank-line cruft either way. The body's
  indentation is preserved; the tag lines' indentation is not.

  Only ASCII space (0x20) and tab (0x09) qualify. NBSP and other
  Unicode whitespace do NOT trigger the trim.

  A blank line INSIDE a block body survives the trim, so to emit a
  deliberate blank separator at the boundary of a gated region, put
  the blank inside the block body rather than outside it.

ERRORS

  The engine reports five error kinds, each with a line number:

    UnresolvedPlaceholder   {{name}} references a variable with no value.
    MalformedPlaceholder    {{ opened on a line without a closing }}.
    UnterminatedIf          {{#if}} opener with no matching {{/if}}.
    OrphanBlockToken        {{/if}} or {{#else}} outside any open {{#if}}.
    MalformedIfExpression   The expression inside {{#if ...}} failed to parse.

  Block-level errors point at the source line of the offending tag.
  Placeholder errors inside a taken branch report a line number measured
  in the post-expansion text, which may drift from the source line by
  the number of newlines absorbed by standalone-trim; the variable name
  and relative position are still informative.

COMMON PATTERNS

  Optional single line:

    nativeBuildInputs = [
      pkgs.cabal-install
      {{#if Eq nix.postgresql true}}
      pkgs.postgresql
      {{/if}}
    ];

  If / else with a default (kept on one line so the output is one line):

    runtime = "{{#if IsSet docker.registry}}{{docker.registry}}/{{project.name}}{{#else}}{{project.name}}{{/if}}";

  Version-gated content (Eq does string-equal for text variables):

    {{#if Eq ghc.version "ghc912"}}
      -- ghc912-specific build flags
      ghc-options: -Wno-x-partial
    {{/if}}

WHEN TO USE DHALL-TEXT INSTEAD

  Switch the step's strategy from `template` to `dhall-text` (freeform
  Text) or `structured` (JSON / YAML with record-level composition)
  when you need to loop over a list, compute a derived value (for
  example, major.minor from ghc.version), choose among more than a
  handful of discrete cases, or merge structured data across modules.
  Both strategies substitute {{variable}} placeholders first, then
  evaluate the resulting Dhall expression -- so you still get variable
  interpolation on the way in and the full power of Dhall on the way out.

FURTHER READING

  docs/user/templating.md            full reference (this topic condensed)
  docs/user/module-authoring.md      variables, steps, and strategies in context
  docs/user/config-and-variables.md  how variables are resolved
