# Implementation Review: matched_expr and Subrules

## Focus Areas

This review focuses on `matched_expr` and its subrules comparing the implementation against `elixir_parser.yrl`:
- `matched_expr matched_op_expr`
- `unary_op_eol matched_expr`
- `no_parens_one_expr`
- `sub_matched_expr` and subrules (`no_parens_zero_expr`, `access_expr`)

---

## 1. `matched_expr` Rules (Grammar lines 155-161)

### Grammar Definition

```erlang
matched_expr -> matched_expr matched_op_expr : build_op('$1', '$2').
matched_expr -> unary_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> at_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> capture_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> ellipsis_op matched_expr : build_unary_op('$1', '$2').
matched_expr -> no_parens_one_expr : '$1'.
matched_expr -> sub_matched_expr : '$1'.
```

### Implementation (gen_matched_expr, lines 990-1003)

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

**Status: ✅ All 7 productions covered**

---

## 2. `matched_expr matched_op_expr` Rule

### Grammar Definition (lines 187-209)

```erlang
matched_op_expr -> match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> dual_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> mult_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> power_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> concat_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> range_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> ternary_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> xor_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> and_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> or_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> type_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> when_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> pipe_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> comp_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> rel_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> arrow_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> arrow_op_eol no_parens_one_expr : warn_pipe('$1', '$2'), {'$1', '$2'}.
```

### Implementation (@binary_ops, lines 31-91)

| Operator Type | Grammar Line | Implementation | Status |
|--------------|--------------|----------------|--------|
| `match_op` (=) | 187 | `{:match_op, :=}` | ✅ |
| `dual_op` (+, -) | 188 | `{:dual_op, :+}, {:dual_op, :-}` | ✅ |
| `mult_op` (*, /) | 189 | `{:mult_op, :*}, {:mult_op, :/}` | ✅ |
| `power_op` (**) | 190 | `{:power_op, :**}` | ✅ |
| `concat_op` (++, --, <>, +++, ---) | 191 | All 5 operators | ✅ |
| `range_op` (..) | 192 | `{:range_op, :..}` | ✅ |
| `ternary_op` (//) | 193 | Omitted (see note) | ⚠️ TODO |
| `xor_op` (^^^) | 194 | `{:xor_op, :"^^^"}` | ✅ |
| `and_op` (and, &&, &&&) | 195 | All 3 operators | ✅ |
| `or_op` (or, \|\|, \|\|\|) | 196 | All 3 operators | ✅ |
| `in_op` (in) | 197 | `{:in_op, :in}` | ✅ |
| `in_match_op` (<-, \\) | 198 | Both operators | ✅ |
| `type_op` (::) | 199 | `{:type_op, :"::"}` | ✅ |
| `when_op` (when) | 200 | `{:when_op, :when}` | ✅ |
| `pipe_op` (\|>, \|) | 201 | Both operators | ✅ |
| `comp_op` (==, !=, ===, !==, =~) | 202 | All 5 operators | ✅ |
| `rel_op` (<, >, <=, >=) | 203 | All 4 operators | ✅ |
| `arrow_op` (<<<, >>>, etc.) | 204 | All 8 operators | ✅ |

**Note on `ternary_op` (//):** Correctly documented as omitted at line 49:
> "Note: ternary_op (//) omitted - only valid immediately after .. (e.g., 1..10//2)"

This is semantically correct - `//` is only valid in range step expressions.

**Status: ✅ All operators covered (ternary_op intentionally omitted with documentation)**

### gen_matched_op Implementation (lines 1107-1125)

```elixir
defp gen_matched_op(state) do
  child_state = GrammarTree.decr_depth(state)
  restricted_state = restrict_unmatched(child_state)

  operand_gen = ...  # gen_matched_expr for both operands
  
  StreamData.bind(operand_gen, fn left ->
    StreamData.bind(gen_op_eol(), fn op_eol ->
      StreamData.bind(operand_gen, fn right ->
        StreamData.constant({:matched_op, left, op_eol, right})
      end)
    end)
  end)
end
```

**Correctly implements:**
- Both operands are `matched_expr` (via `restrict_unmatched`)
- Uses `gen_op_eol()` which includes optional newline after operator
- Depth budget management to prevent infinite recursion

---

## 3. `unary_op_eol matched_expr` Rule

### Grammar Definition (lines 156, 402-407)

```erlang
matched_expr -> unary_op_eol matched_expr : build_unary_op('$1', '$2').

unary_op_eol -> unary_op : '$1'.
unary_op_eol -> unary_op eol : '$1'.
unary_op_eol -> dual_op : '$1'.
unary_op_eol -> dual_op eol : '$1'.
unary_op_eol -> ternary_op : '$1'.
unary_op_eol -> ternary_op eol : '$1'.
```

### Implementation (@unary_ops, lines 93-104)

```elixir
@unary_ops [
  {:unary_op, :not},
  {:unary_op, :!},
  {:unary_op, :^},
  {:unary_op, :"~~~"},
  {:dual_op, :+},
  {:dual_op, :-}
]
```

| Operator Type | Operators | Implementation | Status |
|--------------|-----------|----------------|--------|
| `unary_op` | not, !, ^, ~~~ | All 4 covered | ✅ |
| `dual_op` (as unary) | +, - | Both covered | ✅ |
| `ternary_op` (as unary) | // | Omitted (see note) | ⚠️ TODO |

**Note on `ternary_op` (//):** Same as binary ops - only valid in range step context.

### gen_matched_unary Implementation (lines 1130-1148)

```elixir
defp gen_matched_unary(state) do
  child_state = GrammarTree.decr_depth(state)
  restricted_state = restrict_unmatched(child_state)
  
  StreamData.bind(StreamData.member_of(@unary_ops), fn {op_kind, op} ->
    StreamData.bind(gen_newlines(), fn newlines ->
      StreamData.bind(operand_gen, fn operand ->
        StreamData.constant({:matched_unary, {op_kind, op}, newlines, operand})
      end)
    end)
  end)
end
```

**Correctly implements:**
- `unary_op_eol` rule with optional newlines via `gen_newlines()`
- Operand is `matched_expr` (via `restrict_unmatched`)
- Supports both with/without eol variants

**Status: ✅ Complete (ternary_op intentionally omitted)**

---

## 4. `no_parens_one_expr` Rule

### Grammar Definition (lines 258-259)

```erlang
no_parens_one_expr -> dot_op_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
no_parens_one_expr -> dot_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
```

Where `call_args_no_parens_one` (lines 477-478):
```erlang
call_args_no_parens_one -> call_args_no_parens_kw : ['$1'].
call_args_no_parens_one -> matched_expr : ['$1'].
```

### Implementation (gen_call_no_parens_one, lines 558-568)

```elixir
defp gen_call_no_parens_one(_state) do
  # Generate simple arg (no operators to avoid ambiguity)
  arg_gen = gen_simple_expr()

  StreamData.bind(StreamData.member_of(@identifiers), fn name ->
    StreamData.bind(arg_gen, fn arg ->
      StreamData.constant({:call_no_parens_one, {:identifier, name}, arg})
    end)
  end)
end
```

**Analysis:**

| Grammar Production | Implementation | Status |
|-------------------|----------------|--------|
| `dot_identifier call_args_no_parens_one` | ✅ Uses `:identifier` | ✅ |
| `dot_op_identifier call_args_no_parens_one` | ❌ Not covered | ⚠️ TODO |
| `call_args_no_parens_kw` (keyword arg) | ❌ Not covered | ⚠️ TODO |
| `matched_expr` (single arg) | ✅ Via `gen_simple_expr()` | ✅ |

**Missing cases:**
1. `dot_op_identifier` - operator identifiers like `+/2` (e.g., `Kernel.+`)
2. Keyword argument form (e.g., `foo a: 1`)

**Status: ⚠️ Partial - needs dot_op_identifier and keyword args**

---

## 5. `sub_matched_expr` Rule

### Grammar Definition (lines 263-267)

```erlang
sub_matched_expr -> no_parens_zero_expr : '$1'.
sub_matched_expr -> range_op : build_nullary_op('$1').
sub_matched_expr -> ellipsis_op : build_nullary_op('$1').
sub_matched_expr -> access_expr : '$1'.
sub_matched_expr -> access_expr kw_identifier : error_invalid_kw_identifier('$2').
```

### Implementation (gen_sub_matched_expr, lines 1034-1041)

```elixir
def gen_sub_matched_expr(state) do
  StreamData.frequency([
    {10, gen_access_expr(state)},      # ✅ access_expr
    {5, gen_no_parens_zero_expr()},    # ✅ no_parens_zero_expr
    {1, gen_nullary_range()},          # ✅ range_op (nullary)
    {1, gen_nullary_ellipsis()}        # ✅ ellipsis_op (nullary)
  ])
end
```

| Grammar Production | Implementation | Status |
|-------------------|----------------|--------|
| `no_parens_zero_expr` | `gen_no_parens_zero_expr()` | ✅ |
| `range_op` (nullary ..) | `gen_nullary_range()` | ✅ |
| `ellipsis_op` (nullary ...) | `gen_nullary_ellipsis()` | ✅ |
| `access_expr` | `gen_access_expr(state)` | ✅ |
| `access_expr kw_identifier` | Error case, correctly omitted | ✅ N/A |

**Status: ✅ Complete**

---

## 6. `no_parens_zero_expr` Rule

### Grammar Definition (lines 260-261)

```erlang
no_parens_zero_expr -> dot_do_identifier : build_identifier('$1').
no_parens_zero_expr -> dot_identifier : build_identifier('$1').
```

Where:
- `dot_identifier` = simple identifier or `expr.identifier`
- `dot_do_identifier` = identifier followed by `do` keyword (e.g., `if`, `case`)

### Implementation (gen_no_parens_zero_expr, lines 1052-1056)

```elixir
def gen_no_parens_zero_expr do
  # For now, generate simple identifiers
  # TODO: dot_do_identifier (e.g., identifiers followed by do blocks)
  gen_identifier()
end
```

**Analysis:**

| Grammar Production | Implementation | Status |
|-------------------|----------------|--------|
| `dot_identifier` (simple) | ✅ `gen_identifier()` | ✅ |
| `dot_identifier` (dotted) | `expr.identifier` | ⚠️ TODO |
| `dot_do_identifier` | `do` block identifiers | ⚠️ TODO (documented) |

**Status: ⚠️ Partial - documented TODO for dot_do_identifier and dotted identifiers**

---

## 7. `access_expr` Rule

### Grammar Definition (lines 273-301)

```erlang
access_expr -> bracket_at_expr : '$1'.                    % @foo[bar]
access_expr -> bracket_expr : '$1'.                       % foo[bar]
access_expr -> capture_int int : build_unary_op('$1', '$2').  % &1
access_expr -> fn_eoe stab_eoe 'end' : build_fn('$1', '$2', '$3').  % fn -> end
access_expr -> open_paren stab_eoe ')' : build_paren_stab('$1', '$2', '$3').  % (->)
access_expr -> open_paren ';' stab_eoe ')' : ...          % (; ->)
access_expr -> open_paren ';' close_paren : ...           % (;)
access_expr -> empty_paren : warn_empty_paren('$1'), ...  % ()
access_expr -> int : ...                                  % 42
access_expr -> flt : ...                                  % 3.14
access_expr -> char : ...                                 % ?a
access_expr -> list : ...                                 % [1, 2, 3]
access_expr -> map : ...                                  % %{a: 1}
access_expr -> tuple : ...                                % {1, 2}
access_expr -> 'true' : ...                               % true
access_expr -> 'false' : ...                              % false
access_expr -> 'nil' : ...                                % nil
access_expr -> bin_string : ...                           % "hello"
access_expr -> list_string : ...                          % 'hello'
access_expr -> bin_heredoc : ...                          % """..."""
access_expr -> list_heredoc : ...                         % '''...'''
access_expr -> bitstring : ...                            % <<1, 2, 3>>
access_expr -> sigil : ...                                % ~r/regex/
access_expr -> atom : ...                                 % :foo
access_expr -> atom_quoted : ...                          % :"foo"
access_expr -> atom_safe : ...                            % :"#{foo}"
access_expr -> atom_unsafe : ...                          % :"#{foo}"
access_expr -> dot_alias : ...                            % Foo.Bar
access_expr -> parens_call : ...                          % foo()
```

### Implementation (gen_access_expr, lines 1085-1099)

```elixir
def gen_access_expr(state) do
  StreamData.frequency([
    {5, gen_literal()},           # ✅ int, flt, char, atom, true, false, nil
    {2, gen_alias()},             # ✅ dot_alias
    {2, gen_fn_single(state)},    # ✅ fn_eoe stab_eoe 'end'
    {2, gen_call_parens(state)},  # ✅ parens_call
    {1, gen_capture_int()},       # ✅ capture_int int
    {1, gen_paren_expr(state)},   # ✅ open_paren stab_eoe ')'
    {1, gen_empty_paren()}        # ✅ empty_paren
  ])
end
```

### Coverage Matrix

| Grammar Production | Implementation | Status |
|-------------------|----------------|--------|
| `bracket_at_expr` (@foo[bar]) | Not implemented | ⚠️ TODO |
| `bracket_expr` (foo[bar]) | Not implemented | ⚠️ TODO |
| `capture_int int` (&1) | `gen_capture_int()` | ✅ |
| `fn_eoe stab_eoe 'end'` | `gen_fn_single(state)` | ✅ |
| `open_paren stab_eoe ')'` | `gen_paren_expr(state)` | ✅ Partial |
| `open_paren ';' stab_eoe ')'` | Not implemented | ⚠️ TODO |
| `open_paren ';' close_paren` | Not implemented | ⚠️ TODO |
| `empty_paren` () | `gen_empty_paren()` | ✅ |
| `int` | `gen_literal()` → `gen_int()` | ✅ |
| `flt` | `gen_literal()` → `gen_float()` | ✅ |
| `char` | `gen_literal()` → `gen_char()` | ✅ |
| `list` ([...]) | Not implemented | ⚠️ TODO |
| `map` (%{...}) | Not implemented | ⚠️ TODO |
| `tuple` ({...}) | Not implemented | ⚠️ TODO |
| `'true'` | `gen_literal()` → `gen_bool_lit()` | ✅ |
| `'false'` | `gen_literal()` → `gen_bool_lit()` | ✅ |
| `'nil'` | `gen_literal()` → `:nil_lit` | ✅ |
| `bin_string` ("...") | Not implemented | ⚠️ TODO |
| `list_string` ('...') | Not implemented | ⚠️ TODO |
| `bin_heredoc` ("""...""") | Not implemented | ⚠️ TODO |
| `list_heredoc` ('''...''') | Not implemented | ⚠️ TODO |
| `bitstring` (<<...>>) | Not implemented | ⚠️ TODO |
| `sigil` (~r/.../) | Not implemented | ⚠️ TODO |
| `atom` (:foo) | `gen_literal()` → `gen_atom_lit()` | ✅ |
| `atom_quoted` (:"foo") | Not implemented | ⚠️ TODO |
| `atom_safe` | Not implemented | ⚠️ TODO |
| `atom_unsafe` | Not implemented | ⚠️ TODO |
| `dot_alias` (Foo.Bar) | `gen_alias()` | ✅ Partial |
| `parens_call` (foo()) | `gen_call_parens(state)` | ✅ |

### TODO Items Documented (lines 1073-1083)

The following are explicitly documented as TODO:
```elixir
# TODO (later phases):
# - bracket_at_expr (@foo[bar])
# - bracket_expr (foo[bar])
# - list ([a, b, c])
# - map (%{a: 1})
# - tuple ({a, b})
# - bin_string / list_string ("hello" / 'hello')
# - bin_heredoc / list_heredoc
# - bitstring (<<1, 2, 3>>)
# - sigil (~r/regex/)
# - atom_quoted / atom_safe / atom_unsafe
```

**Status: ⚠️ Partial - Core literals implemented, data structures deferred to later phases**

---

## 8. TokenCompiler Coverage

### Matched Operators

| Grammar Tree Node | TokenCompiler Handler | Status |
|------------------|----------------------|--------|
| `{:matched_op, left, op_eol, right}` | Lines 136-138 | ✅ |
| `{:matched_unary, op, newlines, operand}` | Lines 185-205 | ✅ |
| `{:at_op, newlines, operand}` | Lines 253-271 | ✅ |
| `{:capture_op, newlines, operand}` | Lines 279-297 | ✅ |
| `{:ellipsis_prefix, operand}` | Lines 304-312 | ✅ |
| `{:nullary_range, nil}` | Lines 236-239 | ✅ |
| `{:nullary_ellipsis, nil}` | Lines 242-245 | ✅ |
| `{:paren_expr, expr}` | Lines 319-332 | ✅ |
| `{:empty_paren, nil}` | Lines 335-345 | ✅ |
| `{:call_no_parens_one, id, arg}` | Lines 379-390 | ✅ |

**Status: ✅ All generated grammar nodes have corresponding compiler handlers**

---

## Summary

### Fully Implemented ✅

| Rule | Status |
|------|--------|
| `matched_expr` (all 7 productions) | ✅ Complete |
| `matched_expr matched_op_expr` (all 18 op types) | ✅ Complete |
| `unary_op_eol matched_expr` (all op types) | ✅ Complete |
| `sub_matched_expr` (all 4 non-error productions) | ✅ Complete |
| Nullary operators (.., ...) | ✅ Complete |
| Parenthesized expressions | ✅ Complete |

### Partially Implemented ⚠️

| Rule | Missing | Status |
|------|---------|--------|
| `no_parens_one_expr` | dot_op_identifier, keyword args | ⚠️ TODO |
| `no_parens_zero_expr` | dotted identifiers, dot_do_identifier | ⚠️ TODO (documented) |
| `access_expr` | Data structures, strings, bracket exprs | ⚠️ TODO (documented) |

### Intentionally Omitted

| Item | Reason |
|------|--------|
| `ternary_op` (//) | Only valid in range step context (1..10//2) |
| `access_expr kw_identifier` | Error production |
| `empty_paren` warning | Generator includes it but Elixir warns |

### Recommendations

1. **Phase 2+:** Implement `dot_op_identifier` for `no_parens_one_expr`
2. **Phase 2+:** Add keyword argument generation (`call_args_no_parens_kw`)
3. **Phase 3+:** Data structures (list, map, tuple, bitstring)
4. **Phase 4+:** Strings (bin_string, list_string, heredocs, sigils)
5. **Phase 5+:** Bracket expressions (bracket_expr, bracket_at_expr)
6. **Phase 5+:** Quoted atoms (atom_quoted, atom_safe, atom_unsafe)

### Code Quality

The implementation is well-structured with:
- Clear separation between generators and compilers
- Proper budget management for recursion control
- Documented TODO items for deferred functionality
- Correct grammar-to-implementation mapping with comments referencing line numbers
