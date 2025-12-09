# Review of Matched Expression Rules (IMPL_G3_1)

## Overview

This review focuses on the coverage of `matched_expr` and its sub-rules in `TokenGrammarGenerators` and `TokenCompiler` against `elixir_parser.yrl`.

## 1. Matched Expression (`matched_expr`)

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

### 1.1. Matched Binary Op (`matched_expr matched_op_expr`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_matched_op`
- **Notes:** Flattens left-recursion. Handles `op_eol` correctly.

### 1.2. Unary Op (`unary_op_eol matched_expr`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_matched_unary`
- **Notes:** Explicitly handles newlines (`unary_op eol`).

### 1.3. At Op (`at_op_eol matched_expr`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_at_op`

### 1.4. Capture Op (`capture_op_eol matched_expr`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_capture_op`

### 1.5. Ellipsis Op (`ellipsis_op matched_expr`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_ellipsis_prefix`

### 1.6. No Parens One (`no_parens_one_expr`)
- **Status:** ⚠️ **Partially Covered**
- **Generator:** `gen_call_no_parens_one`
- **Covered:**
  - Simple identifier calls: `foo 1` (`dot_identifier call_args_no_parens_one`)
- **Missing / TODO:**
  - `dot_op_identifier`: Operator-like identifiers (e.g., `.+ 1`).
  - `call_args_no_parens_kw`: Keyword arguments (e.g., `foo a: 1`).
  - Complex `dot_identifier`: `matched_expr.identifier arg` (e.g., `Mod.fun arg`).
  - `matched_expr` as argument (currently uses `gen_simple_expr`).

### 1.7. Sub Matched Expr (`sub_matched_expr`)
- **Status:** ✅ **Covered** (Delegates to sub-rules)
- **Generator:** `gen_sub_matched_expr`

## 2. Sub Matched Expression Rules

### 2.1. No Parens Zero Expr (`no_parens_zero_expr`)
- **Status:** ⚠️ **Partially Covered**
- **Generator:** `gen_no_parens_zero_expr`
- **Covered:**
  - Simple identifiers (`identifier`).
- **Missing / TODO:**
  - `dot_do_identifier`: Identifiers that can be followed by do blocks.
  - Complex `dot_identifier`: `matched_expr.identifier` (e.g., `Map.put`).

### 2.2. Nullary Operators (`range_op`, `ellipsis_op`)
- **Status:** ✅ **Covered**
- **Generator:** `gen_nullary_range`, `gen_nullary_ellipsis`

### 2.3. Access Expression (`access_expr`)
- **Status:** ⚠️ **Partially Covered**
- **Generator:** `gen_access_expr`
- **Covered:**
  - Literals: `int`, `flt`, `char`, `atom`, `true`, `false`, `nil`.
  - `capture_int`: `&1`.
  - `fn_eoe`: `fn ... end` (single clause).
  - `parens_call`: `foo(...)` and `expr.(...)`.
  - `empty_paren`: `()`.
  - `open_paren ... )`: `(expr)`.
  - `dot_alias`: Simple aliases (`Foo`).
- **Missing / TODO (Marked in Code):**
  - `bracket_expr`: `foo[bar]`.
  - `bracket_at_expr`: `@foo[bar]`.
  - `list`: `[...]`.
  - `map`: `%{...}`.
  - `tuple`: `{...}`.
  - `bitstring`: `<<...>>`.
  - Strings/Heredocs: `bin_string`, `list_string`, etc.
  - Sigils: `~r/.../`.
  - Quoted atoms: `:"foo"`.
  - Complex `dot_alias`: `Expr.Alias`.
  - `open_paren ; ... )`: Parenthesized expressions with semicolons.

## Conclusion

The core structure of `matched_expr` is well-implemented, covering all top-level productions. However, the leaf nodes (`access_expr`, `no_parens_zero_expr`) and specific call variants (`no_parens_one_expr`) have significant gaps, particularly regarding complex identifiers (dot syntax), collections (lists, maps), and strings. These are correctly identified as TODOs or future phases in the generator code.
