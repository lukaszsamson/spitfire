# Review: matched_expr generators vs `elixir_parser.yrl`

Scope: `test/spitfire/property/token_grammar_generators.exs`, `test/spitfire/token_property_test.exs`, `lib/spitfire/property/token_compiler.ex` against `elixir_parser.yrl` for `matched_expr` clauses (`matched_expr matched_op_expr`, `unary_op_eol matched_expr`, `no_parens_one_expr`, `sub_matched_expr` and subrules `no_parens_zero_expr`, `access_expr`).

## Coverage findings
- **matched_expr matched_op_expr**: `gen_matched_op` emits the shape, but the operator pool is a small subset (`+, -, *, /, ==, !=, ===, !==, <, >, <=, >=, and, or, |>`). Grammar also allows `match_op (=)`, `power (** )`, `concat ( <>)`, `range ..` (binary), `ternary/xor`, `in`, `in_match`, `type`, `when`, `arrow`, and other pipe variants—none generated. Compiler supports emitted shapes; ungenerated ops remain untested.
- **unary_op_eol matched_expr**: `gen_matched_unary` uses `@unary_ops` (`not, !, +, -`) with optional newlines; grammar also allows `^` and `~~~`, which are not generated (future phase needed).
- **no_parens_one_expr**: Generator path is `gen_call_no_parens_one` producing `{:call_no_parens_one, {:identifier, name}, arg}` with simple args only. Grammar requires `dot_op_identifier`/`dot_identifier` targets with `call_args_no_parens_one`; the generator omits `dot_op_identifier` variants and broader arg shapes (phased simplification).
- **sub_matched_expr**:
  - `no_parens_zero_expr`: Generator currently returns a bare identifier only; grammar has `dot_do_identifier` and `dot_identifier`. TODO is noted in code; dot/do variants are missing.
  - `range_op` / `ellipsis_op`: Nullary variants are covered via `gen_nullary_range/ellipsis`.
  - `access_expr`: Generator includes literals, aliases, `fn_single`, paren calls, capture ints, paren_expr, empty_paren. Grammar also includes bracket access (`foo[ ]`, `@foo[ ]`), lists, maps, tuples, binaries/strings/heredocs, bitstrings, sigils, quoted atoms, dot_alias, parens_call, etc.; these are marked TODO and currently not generated. The `access_expr kw_identifier` error branch is not exercised.

## Test scope
- `token_property_test.exs` uses `Gen.grammar/1` phase 1, so only the restricted sets above are sampled; missing operator families and richer access/no_parens_zero forms remain untested for now.

## Recommendations
- Expand operator pools to mirror `matched_op_expr`/`unary_op_eol` grammar (phase-gated if needed) before claiming full coverage.
- Implement `no_parens_zero_expr` proper (`dot_do_identifier`/`dot_identifier`) and broaden `no_parens_one_expr` targets/args toward the grammar shapes.
- Gradually add `access_expr` constructs (lists/maps/strings/brackets/sigils/quoted atoms) or explicitly defer them with TODO markers per phase plan.
