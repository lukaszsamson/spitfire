# Implementation Review: Token Grammar Generators

## Overview

This document reviews the property test implementation for generating Elixir tokens from grammar rules, comparing the implementation against `elixir_parser.yrl`.

## Files Reviewed

- `test/spitfire/property/token_grammar_generators.exs` - StreamData generators
- `test/spitfire/token_property_test.exs` - Property tests
- `lib/spitfire/property/token_compiler.ex` - Token compiler

---

## 1. `grammar` Rule Review

### Grammar Definition (elixir_parser.yrl lines 101-106)

```erlang
grammar -> eoe : {'__block__', meta_from_token('$1'), []}.
grammar -> expr_list : build_block(reverse('$1')).
grammar -> eoe expr_list : build_block(reverse('$2')).
grammar -> expr_list eoe : build_block(reverse(annotate_eoe('$2', '$1'))).
grammar -> eoe expr_list eoe : build_block(reverse(annotate_eoe('$3', '$2'))).
grammar -> '$empty' : {'__block__', [], []}.
```

### Implementation (TokenGrammarGenerators.grammar/1)

**✅ Correctly implements:**
- `grammar -> expr_list` via `gen_grammar_expr_list`
- `grammar -> expr_list eoe` via `gen_grammar_expr_list_eoe`
- `grammar -> eoe expr_list` via `gen_grammar_eoe_expr_list`
- `grammar -> eoe expr_list eoe` via `gen_grammar_eoe_expr_list_eoe`

**⚠️ Missing cases:**
- `grammar -> eoe` (just eoe, empty program) - noted as omitted "edge cases"
- `grammar -> '$empty'` (completely empty) - noted as omitted

**Recommendation:** The omissions are intentional for testing non-trivial programs. Document this choice in the generators.

---

## 2. `expr_list` Rule Review

### Grammar Definition (elixir_parser.yrl lines 109-110)

```erlang
expr_list -> expr : ['$1'].
expr_list -> expr_list eoe expr : ['$3' | annotate_eoe('$2', '$1')].
```

### Implementation (gen_expr_list)

**✅ Correctly implements:**
- Single expression case: `gen_expr_list(_state, 1)` returns `[{expr, nil}]` (no trailing eoe)
- Multiple expressions: eoe goes BETWEEN expressions, not after the last one

**Implementation Detail:**
The format `[{expr, eoe | nil}, ...]` correctly models that:
- The last expression has `nil` for eoe
- Earlier expressions have eoe markers between them

**✅ Correct**

---

## 3. `eoe` Rule Review

### Grammar Definition (elixir_parser.yrl lines 331-333)

```erlang
eoe -> eol : '$1'.
eoe -> ';' : '$1'.
eoe -> eol ';' : '$1'.
```

### Implementation (gen_eoe)

```elixir
def gen_eoe do
  StreamData.frequency([
    {7, StreamData.constant(:eol)},      # eoe -> eol
    {2, StreamData.constant(:semi)},     # eoe -> ';'
    {1, StreamData.constant(:eol_semi)}  # eoe -> eol ';'
  ])
end
```

**✅ Correct:** All three variants are covered with appropriate frequency weights.

### TokenCompiler (compile_eoe)

```elixir
defp compile_eoe(:eol, layout) -> [{:eol, eol_meta}]
defp compile_eoe(:semi, layout) -> [{:";", semi_meta}]
defp compile_eoe(:eol_semi, layout) -> [{:eol, eol_meta}, {:";", semi_meta}]
```

**✅ Correct:** Token emission matches grammar.

---

## 4. `matched_expr` Rule Review

### Grammar Definition (elixir_parser.yrl lines 155-161)

```erlang
matched_expr -> matched_expr matched_op_expr : build_op('$1', '$2').
matched_expr -> unary_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> at_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> capture_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> ellipsis_op matched_expr : build_unary_op('$1', '$2').
matched_expr -> no_parens_one_expr : '$1'.
matched_expr -> sub_matched_expr : '$1'.
```

### Implementation (gen_matched_expr)

```elixir
def gen_matched_expr(state) do
  StreamData.frequency([
    {4, gen_sub_matched_expr(state)},           # ✅ sub_matched_expr
    {3, gen_matched_op(state)},                  # ✅ matched_expr matched_op_expr
    {2, gen_matched_unary(state)},               # ✅ unary_op_eol matched_expr
    {1, gen_at_op(state)},                       # ✅ at_op_eol matched_expr
    {1, gen_capture_op(state)},                  # ✅ capture_op_eol matched_expr
    {1, gen_ellipsis_prefix(state)},             # ✅ ellipsis_op matched_expr
    {1, gen_call_no_parens_one(state)}           # ✅ no_parens_one_expr
  ])
end
```

**✅ All productions covered**

### Missing from matched_op_expr

The grammar defines `matched_op_expr` with 18+ operator types (lines 187-204):
```erlang
matched_op_expr -> match_op_eol matched_expr
matched_op_expr -> dual_op_eol matched_expr
matched_op_expr -> mult_op_eol matched_expr
...
```

**⚠️ Implementation only includes a subset of operators:**
```elixir
@binary_ops [
  {:dual_op, :+}, {:dual_op, :-},      # ✅
  {:mult_op, :*}, {:mult_op, :/},      # ✅
  {:comp_op, :==}, {:comp_op, :!=},... # ✅
  {:and_op, :and}, {:or_op, :or},      # ✅
  {:pipe_op, :|>}                       # ✅
]
```

**Missing operators from grammar:**
- `match_op` (`:=`)
- `power_op` (`:**)
- `concat_op` (`:++`, `:--`, `:<>`)
- `range_op` (`:..`)
- `ternary_op` (`://`)
- `xor_op` (`:^^^`)
- `in_op` (`:in`, `:"not in"`)
- `in_match_op` (`:<-`, `:\\`)
- `type_op` (`:::`)
- `when_op` (`:when`)
- `arrow_op` (`:<<<`, `:>>>`, `:~>>`, etc.)

**Recommendation:** Expand `@binary_ops` to cover all operator types for comprehensive testing.

---

## 5. `sub_matched_expr` Rule Review

### Grammar Definition (elixir_parser.yrl lines 263-267)

```erlang
sub_matched_expr -> no_parens_zero_expr : '$1'.
sub_matched_expr -> range_op : build_nullary_op('$1').
sub_matched_expr -> ellipsis_op : build_nullary_op('$1').
sub_matched_expr -> access_expr : '$1'.
sub_matched_expr -> access_expr kw_identifier : error_invalid_kw_identifier('$2').
```

### Implementation (gen_sub_matched_expr)

```elixir
def gen_sub_matched_expr(state) do
  StreamData.frequency([
    {10, gen_access_expr(state)},      # ✅ access_expr
    {5, gen_no_parens_zero_expr()},    # ✅ no_parens_zero_expr (bare identifiers)
    {1, gen_nullary_range()},          # ✅ range_op (nullary)
    {1, gen_nullary_ellipsis()}        # ✅ ellipsis_op (nullary)
  ])
end
```

**✅ All productions covered:**
- `no_parens_zero_expr` - now implemented via `gen_no_parens_zero_expr()` which generates bare identifiers

**Note:** The `access_expr kw_identifier` case is an error production, correctly omitted.

---

## 6. `access_expr` Rule Review

### Grammar Definition (elixir_parser.yrl lines 273-301)

```erlang
access_expr -> bracket_at_expr
access_expr -> bracket_expr
access_expr -> capture_int int
access_expr -> fn_eoe stab_eoe 'end'
access_expr -> open_paren stab_eoe ')'
access_expr -> open_paren ';' stab_eoe ')'
access_expr -> open_paren ';' close_paren
access_expr -> empty_paren
access_expr -> int
access_expr -> flt
access_expr -> char
access_expr -> list
access_expr -> map
access_expr -> tuple
access_expr -> 'true'
access_expr -> 'false'
access_expr -> 'nil'
access_expr -> bin_string
access_expr -> list_string
access_expr -> bin_heredoc
access_expr -> list_heredoc
access_expr -> bitstring
access_expr -> sigil
access_expr -> atom
access_expr -> atom_quoted
access_expr -> atom_safe
access_expr -> atom_unsafe
access_expr -> dot_alias
access_expr -> parens_call
```

### Implementation (gen_access_expr)

```elixir
def gen_access_expr(state) do
  StreamData.frequency([
    {5, gen_literal()},         # ✅ int, flt, char, true, false, nil, atom
    {2, gen_alias()},           # ✅ dot_alias
    {2, gen_fn_single(state)},  # ✅ fn_eoe stab_eoe 'end'
    {2, gen_call_parens(state)},# ✅ parens_call
    {1, gen_capture_int()},     # ✅ capture_int int
    {1, gen_paren_expr(state)}, # ✅ open_paren stab_eoe ')' (partial)
    {1, gen_empty_paren()}      # ✅ empty_paren
  ])
end
```

**✅ Fixed:** `gen_identifier()` removed from `gen_access_expr` - identifiers now correctly generated via `gen_no_parens_zero_expr()` in `gen_sub_matched_expr`.

**TODO (later phases) - Missing from access_expr:**
- `bracket_at_expr` - `@foo[bar]`
- `bracket_expr` - `foo[bar]`
- `list` - `[a, b, c]`
- `map` - `%{a: 1}`
- `tuple` - `{a, b}`
- `bin_string` / `list_string` - `"hello"` / `'hello'`
- `bin_heredoc` / `list_heredoc` - `"""..."""`
- `bitstring` - `<<1, 2, 3>>`
- `sigil` - `~r/regex/`
- `atom_quoted` / `atom_safe` / `atom_unsafe` - `:"quoted"`, `:"#{interpolated}"`

---

## 7. `unmatched_expr` Rule Review

### Grammar Definition (elixir_parser.yrl lines 163-171)

```erlang
unmatched_expr -> matched_expr unmatched_op_expr : build_op('$1', '$2').
unmatched_expr -> unmatched_expr matched_op_expr : build_op('$1', '$2').
unmatched_expr -> unmatched_expr unmatched_op_expr : build_op('$1', '$2').
unmatched_expr -> unmatched_expr no_parens_op_expr : warn_no_parens_after_do_op('$2'), build_op('$1', '$2').
unmatched_expr -> unary_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> at_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> capture_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> ellipsis_op expr : build_unary_op('$1', '$2').
unmatched_expr -> block_expr : '$1'.
```

### Implementation (gen_unmatched_expr)

```elixir
def gen_unmatched_expr(state) do
  StreamData.frequency([
    {5, gen_call_do(state)},      # ✅ block_expr (if/unless/case)
    {3, gen_unmatched_op(state)}  # ✅ matched_expr unmatched_op_expr
  ])
end
```

**⚠️ Missing:**
- `unmatched_expr matched_op_expr` - binary op where left is unmatched
- `unmatched_expr unmatched_op_expr` - both sides unmatched
- `unary_op_eol expr` - unary with any expr (not just matched)
- `at_op_eol expr` - @ with any expr
- `capture_op_eol expr` - & with any expr
- `ellipsis_op expr` - ... with any expr

**Note:** These are recursive and complex. Current coverage of `block_expr` and basic `unmatched_op` is reasonable for initial phases.

---

## 8. `no_parens_expr` Rule Review (Not Implemented)

### Grammar Definition (elixir_parser.yrl lines 173-179)

```erlang
no_parens_expr -> matched_expr no_parens_op_expr : build_op('$1', '$2').
no_parens_expr -> unary_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> at_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> capture_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> ellipsis_op no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> no_parens_one_ambig_expr : '$1'.
no_parens_expr -> no_parens_many_expr : '$1'.
```

**⚠️ Status:** Noted as "deferred to Phase 3+" in comments. This is a complex expression category involving ambiguous calls like `foo bar baz, qux`.

---

## Summary of Findings

### Correct Implementations ✅
1. `grammar` - All main variants covered
2. `expr_list` - Correct eoe placement between expressions
3. `eoe` - All three variants (eol, semi, eol semi)
4. `matched_expr` - Core productions covered
5. `sub_matched_expr` - All productions covered (including no_parens_zero_expr)
6. `access_expr` - Core productions covered (identifiers correctly moved to no_parens_zero_expr)

### Issues Resolved ✅

| Issue | Status | Resolution |
|-------|--------|------------|
| `gen_identifier()` in `gen_access_expr()` | **FIXED** | Removed from access_expr, added via `gen_no_parens_zero_expr()` in sub_matched_expr |
| Missing `no_parens_zero_expr` | **FIXED** | Added `gen_no_parens_zero_expr()` to `gen_sub_matched_expr()` |
| Limited binary operator coverage | **FIXED** | All operator categories now covered in `@binary_ops` |
| Missing `empty_paren` | **FIXED** | Added `gen_empty_paren()` to `gen_access_expr()` |

### TODO (Later Phases)

| Feature | Phase | Description |
|---------|-------|-------------|
| Data structures | Phase 4 | list, tuple, map, bitstring |
| Strings | Phase 5 | bin_string, list_string, heredocs |
| Sigils | Phase 5 | `~r/regex/` and other sigils |
| Bracket expressions | Phase 4 | `foo[bar]`, `@foo[bar]` |
| `no_parens_expr` | Phase 3 | `no_parens_many_expr`, ambiguous calls |

### Test Coverage
The property tests correctly:
- Use acceptance guards to detect high rejection rates
- Normalize ASTs for comparison
- Round-trip through both Code.string_to_quoted and Spitfire
- **Continue to find Spitfire parsing bugs** (expected behavior)

---

## Appendix: Grammar Rule Quick Reference

| Rule | Lines | Status |
|------|-------|--------|
| grammar | 101-106 | ✅ Implemented |
| expr_list | 109-110 | ✅ Implemented |
| expr | 112-114 | ✅ Partial |
| matched_expr | 155-161 | ✅ Implemented |
| unmatched_expr | 163-171 | ⚠️ Partial (Phase 3+) |
| no_parens_expr | 173-179 | ❌ Deferred (Phase 3+) |
| block_expr | 181-185 | ✅ via gen_call_do |
| matched_op_expr | 187-209 | ✅ All operators covered |
| unmatched_op_expr | 211-228 | ✅ All operators covered |
| sub_matched_expr | 263-267 | ✅ Implemented (incl. no_parens_zero_expr) |
| access_expr | 273-301 | ✅ Core implemented (containers Phase 4+) |
| eoe | 331-333 | ✅ Implemented |
| stab_expr | 350-363 | ✅ via fn_single/fn_multi |
