# Review: Token grammar property generators vs `elixir_parser.yrl`

Scope: `test/spitfire/property/token_grammar_generators.exs`, `test/spitfire/token_property_test.exs`, `lib/spitfire/property/token_compiler.ex`, `elixir_parser.yrl`. Focus rules: `grammar`, `expr_list`, `eoe`, `matched_expr` (and their generators/compilers).

## grammar (yrl lines ~101-106)
- Grammar rules: `eoe`, `expr_list`, `eoe expr_list`, `expr_list eoe`, `eoe expr_list eoe`, `'$empty'`.
- Generators: `grammar/1` emits only the four expr_list variants; `grammar -> eoe` and `grammar -> '$empty'` are intentionally skipped (commented as “edge cases”). Format `{:grammar_v2, leading_eoe, exprs, trailing_eoe}` requires `exprs` non-empty.
- Compiler: `do_to_tokens/3` supports `{:grammar_v2, leading_eoe, exprs, trailing_eoe}` (assumes at least one expr) plus legacy `{:grammar, forms}` / `{:grammar_eoe, forms_with_eoe}`. No clause for empty grammar/eoe-only; such shapes would currently fail.
- Tests: `token_property_test` consumes `Gen.grammar/1`; therefore property samples never cover the `grammar -> eoe` or `grammar -> '$empty'` paths in `elixir_parser.yrl`.

## expr_list (yrl lines ~109-110)
- Grammar: non-empty list; recursive with interleaved `eoe`.
- Generator: `gen_expr_list/2` enforces 1..max_forms; last tuple is `{expr, nil}`, intermediate items carry `eoe`, matching `expr_list -> expr_list eoe expr`.
- Compiler: `compile_expr_list/3` assumes that shape; aligns with generator output. Zero-length expr_list is impossible (consistent with grammar).

## eoe (yrl lines ~331-333)
- Grammar: `eol`, `;`, `eol ';'`.
- Generator: `gen_eoe/0` produces `:eol`, `:semi`, `:eol_semi` with weights 7/2/1; coverage complete.
- Compiler: `compile_eoe/2` renders newline, semicolon, or newline+semicolon with layout updates; matches grammar terminals.

## matched_expr (yrl lines ~155-161)
- Grammar clauses: (1) `matched_expr matched_op_expr`, (2) `unary_op_eol matched_expr`, (3) `at_op_eol matched_expr`, (4) `capture_op_eol matched_expr`, (5) `ellipsis_op matched_expr`, (6) `no_parens_one_expr`, (7) `sub_matched_expr`.
- Generator coverage:
  - `gen_matched_op` → clause (1) using `matched_op_expr`-like shape `{op_kind, op}` with optional newline via `gen_op_eol`.
  - `gen_matched_unary` → clause (2).
  - `gen_at_op` → clause (3).
  - `gen_capture_op` → clause (4).
  - `gen_ellipsis_prefix` → clause (5).
  - `gen_call_no_parens_one` → clause (6).
  - `gen_sub_matched_expr` → clause (7).
- **Binary operators** (all `matched_op_expr` categories now covered):
  - `match_op`: `=`
  - `dual_op`: `+`, `-`
  - `mult_op`: `*`, `/`
  - `power_op`: `**`
  - `concat_op`: `++`, `--`, `<>`, `+++`, `---`
  - `range_op`: `..` (as binary)
  - `xor_op`: `^^^`
  - `comp_op`: `==`, `!=`, `===`, `!==`, `=~`
  - `rel_op`: `<`, `>`, `<=`, `>=`
  - `and_op`: `and`, `&&`, `&&&`
  - `or_op`: `or`, `||`, `|||`
  - `in_op`: `in`
  - `in_match_op`: `<-`, `\\`
  - `type_op`: `::`
  - `when_op`: `when`
  - `arrow_op`: `<<<`, `>>>`, `<~`, `~>`, `<<~`, `~>>`, `<~>`, `<|>`
  - `pipe_op`: `|>`, `|`
  - Note: `ternary_op` (`//`) omitted - semantically restricted to follow `..` (e.g., `1..10//2`)
- **Unary operators** (all `unary_op_eol` categories now covered):
  - `unary_op`: `not`, `!`, `^`, `~~~`
  - `dual_op`: `+`, `-`
  - Note: `ternary_op` (`//`) omitted - same semantic restriction
- Nullary coverage: `gen_sub_matched_expr` includes nullary `range` and `ellipsis`, matching `sub_matched_expr` rules (263-265).
- Compiler alignment: `compile_binary_op/5` and `compile_arg_with_adhesion` handle all operator shapes generically via `op_kind` dispatch.

## Notes on tests (`token_property_test.exs`)
- Property tests use `Gen.grammar/1` (phase 1) with full operator coverage.
- The property tests have uncovered a Spitfire parsing bug where `not foo :baz` followed by nullary `..` and an `if` block are incorrectly grouped under the `not` expression instead of being separate top-level expressions.

## Recommendations
- Decide whether to cover `grammar -> eoe` and `grammar -> '$empty'` in property generation; if yes, add generators plus compiler handling for empty/eoe-only grammar_v2 inputs.
- ~~Consider expanding `@binary_ops`/`@unary_ops`~~ **DONE**: All operator categories from `matched_op_expr` and `unary_op_eol` are now covered, except `ternary_op` (`//`) which is semantically restricted to follow `..`.
- Investigate Spitfire bug: `not foo :baz` followed by `..` and block expressions incorrectly groups everything under `not`.
