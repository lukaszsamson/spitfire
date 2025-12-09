# Review of Token Grammar Generators (IMPL_G3)

## Overview

This review covers the alignment between the property test generators in `test/spitfire/property/token_grammar_generators.exs` and the Elixir grammar definitions in `elixir_parser.yrl`.

## 1. Grammar Rule (`grammar`)

**YRL Definition:**
```erlang
grammar -> expr_list : '$1'.
grammar -> eoe : ['$1'].
grammar -> '$empty' : [].
```

**Generator Implementation (`grammar/1`):**
- Generates `expr_list` (with optional leading/trailing `eoe`).
- Explicitly omits `grammar -> eoe` and `grammar -> '$empty'` (documented in code comments).

**Assessment:**
- **Status:** ✅ Mostly Aligned (with intentional omissions)
- **Notes:** The generator focuses on meaningful content (`expr_list`). The omission of empty or single-EOE grammars is acceptable for property testing purposes as they represent edge cases with little structural complexity.

## 2. Expression List Rule (`expr_list`)

**YRL Definition:**
```erlang
expr_list -> expr_list eoe expr : '$1' ++ ['$2', '$3'].
expr_list -> expr : ['$1'].
```

**Generator Implementation (`gen_expr_list/2`):**
- Generates a list of `{expr, eoe}` tuples.
- Recursively builds the list as `expr` -> `eoe` -> `rest`.
- Produces the sequence `expr eoe expr eoe ... expr`.

**Assessment:**
- **Status:** ✅ Aligned
- **Notes:** The generator correctly models the sequence of expressions separated by EOE markers. While the recursion direction differs (right-recursive vs left-recursive), the resulting token sequence is identical.

## 3. End of Expression Rule (`eoe`)

**YRL Definition:**
```erlang
eoe -> eol : '$1'.
eoe -> ';' : {';', ?line('$1')}.
eoe -> eol ';' : '$1'.
```

**Generator Implementation (`gen_eoe/0`):**
- Generates `:eol`, `:semi`, or `:eol_semi`.
- `TokenCompiler` compiles `:eol_semi` to `[{:eol, ...}, {:";", ...}]`.

**Assessment:**
- **Status:** ✅ Aligned
- **Notes:** The generator correctly supports all three forms of EOE defined in the grammar, including the `eol ';'` combination.

## 4. Matched Expression Rule (`matched_expr`)

**YRL Definition:**
```erlang
matched_expr -> matched_expr matched_op_expr
matched_expr -> unary_op_eol matched_expr
matched_expr -> at_op_eol matched_expr
matched_expr -> capture_op_eol matched_expr
matched_expr -> ellipsis_op matched_expr
matched_expr -> no_parens_one_expr
matched_expr -> sub_matched_expr
```

**Generator Implementation (`gen_matched_expr/1`):**

### 4.1. Matched Binary Op (`gen_matched_op`)
- **Covers:** `matched_expr matched_op_expr`
- **Implementation:** Generates `{:matched_op, left, op_eol, right}`. `op_eol` includes optional newlines.
- **Status:** ✅ Aligned. The generator flattens the left-recursive structure but preserves the token sequence and `eol` handling.

### 4.2. Matched Unary Op (`gen_matched_unary`)
- **Covers:** `matched_expr -> unary_op_eol matched_expr`
- **YRL Detail:** `unary_op_eol -> unary_op` | `unary_op eol`.
- **Implementation:** Generates `{:matched_unary, {op_kind, op}, newlines, operand}`.
- **Status:** ✅ **Aligned**. Generator now produces optional newlines via `gen_newlines()`. TokenCompiler emits `:eol` tokens when `newlines > 0`.

### 4.3. At Op (`gen_at_op`)
- **Covers:** `matched_expr -> at_op_eol matched_expr`
- **YRL Detail:** `at_op_eol -> at_op` | `at_op eol`.
- **Implementation:** Generates `{:at_op, newlines, operand}`.
- **Status:** ✅ Aligned. Explicitly generates `newlines`.

### 4.4. Capture Op (`gen_capture_op`)
- **Covers:** `matched_expr -> capture_op_eol matched_expr`
- **YRL Detail:** `capture_op_eol -> capture_op` | `capture_op eol`.
- **Implementation:** Generates `{:capture_op, newlines, operand}`.
- **Status:** ✅ Aligned. Explicitly generates `newlines`.

### 4.5. Ellipsis Prefix (`gen_ellipsis_prefix`)
- **Covers:** `matched_expr -> ellipsis_op matched_expr`
- **YRL Detail:** `ellipsis_op` (no `eol` variant in rule name).
- **Implementation:** Generates `{:ellipsis_prefix, operand}`.
- **Status:** ✅ Aligned. Correctly omits newline generation as the grammar rule does not imply `eol` support for this operator position.

### 4.6. No Parens One (`gen_call_no_parens_one`)
- **Covers:** `matched_expr -> no_parens_one_expr`
- **Implementation:** Generates `{:call_no_parens_one, identifier, arg}`.
- **Status:** ✅ Aligned. Covers the structural essence of `identifier arg`.

### 4.7. Sub Matched Expr (`gen_sub_matched_expr`)
- **Covers:** `matched_expr -> sub_matched_expr`
- **Implementation:** Delegates to `gen_access_expr`, `gen_nullary_range`, `gen_nullary_ellipsis`.
- **Status:** ✅ Aligned.

## Conclusion

The property test generators are fully aligned with the `elixir_parser.yrl` grammar definitions for `matched_expr`.

**All Issues Resolved:**
- ~~`gen_matched_unary` fails to generate the optional newline after the unary operator~~ **FIXED**: Generator now uses `gen_newlines()` and produces `{:matched_unary, op_kind, newlines, operand}`. TokenCompiler updated to emit `:eol` tokens.
