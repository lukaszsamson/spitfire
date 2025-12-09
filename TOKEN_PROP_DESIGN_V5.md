# Token-Driven Property Tests Design (V5)

V5 is the **consolidated, implementation-ready spec** for token-driven
properties. It merges V3+V4 and folds in the final review notes
(`TOKEN_PROP_DESIGN_V4_*`) so implementers do not need to cross-reference
multiple documents.

The core architecture remains:

- Generate a **grammar tree** (nonterminal-based) via `grammar/1`
- Compile the tree to **linear Toxic streaming tokens** via `to_tokens/2`
- Render source with `Toxic.to_string/1`
- Parse with the Elixir oracle and Spitfire, then compare normalized ASTs and
  check tokenizer properties

This document focuses on decisions that affect implementation; it omits
repetitive prose where earlier versions agreed.

---

## 1. Step 0 – Verify `Toxic.to_string/1`

Before implementing generators, implement `ToxicToStringSmokeTest` with these
checks.

### 1.1. Meta format and `extra`

- Use **ranged metas**: `{kind, {{sl, sc}, {el, ec}, extra}}`.
- Confirm `extra` behavior:
  - `:eol`, `:","`, `:";"` – newline count (>= 1)
  - Numbers – parsed numeric value (or `nil` if Toxic doesn’t require it)
  - Atoms/aliases/identifiers/kw identifiers – original charlist when available
    (see 3.2)
  - Operators, `:block_identifier` – `extra` `nil` unless clearly required

### 1.2. Layout & adhesion expectations

For hand-written token sequences, assert
`Toxic.to_string(tokens) |> Code.string_to_quoted/2` succeeds for:

- Literals/ids: `123`, `1_000_000`, `0x1F`, `0b10_10`, `0o7_7_7`, `1.0e-10`,
  `?a`, `:foo`, `true`, `nil`
- Calls/operators: `fn -> nil end`, `fn x -> x end`, `foo(1, 2)`, `foo.(1)`,
  `foo bar`, `&1`, `&10`, `1..10`, `1..10//2`, `a +\n 1`, `not in` constructs
- Containers: `[1, 2]`, `{1, 2}`, `%{a: 1}`, `%Foo{a: 1}` (note `%{` dual tokens)
- Blocks: `if true do 1 end`, `if true do 1 else 2 end`
- Strings/sigils/heredocs: `"hello #{world}"`, `~r/foo/iu`, heredocs, sigil
  heredocs

Pay special attention to:

- `_op_eol` + `:eol` (Section 2.4)
- `capture_int` + `int` adhesion (`&10`)
- `%{` dual tokens and layout
- `foo.(1)` dot-call layout

If any behavior diverges from assumptions below (e.g. double newlines), adjust
`to_tokens/2` and `TokenLayout` before writing generators.

---

## 2. Grammar Tree and Phase Overview

### 2.1. Grammar tree

We define a closed set of tagged tuples (module name illustrative):

```elixir
defmodule Spitfire.Property.GrammarTree do
  @type t ::
          {:grammar, [expr_t()]}
        | {:matched, matched_t()}
        | {:unmatched, unmatched_t()}
        | {:access, access_t()}
        | {:call_parens, target_t(), [expr_t()]}             # foo(1,2), foo.(1)
        | {:call_nested_parens, target_t(), [expr_t()], [expr_t()]} # foo(1)(2)
        | {:call_no_parens_one, target_t(), expr_t()}
        | {:call_no_parens_many, target_t(), [expr_t()]}
        | {:call_no_parens_ambig, target_t(), expr_t()}
        | {:fn_single, [stab_clause_t()]}                    # 1 clause in Phase 1
        | {:fn_multi, [stab_clause_t()]}                     # multi-clause in Phase 2+
        | {:stab_clause, pattern_t(), guard_t(), expr_t()}   # fn patterns
        | {:list, [expr_t()]}
        | {:tuple, [expr_t()]}
        | {:map, map_t()}
        | {:bitstring, [expr_t()]}
        | {:string, string_t()}
        | {:sigil, sigil_t()}
        | {:dot, expr_t(), id_t()}                          # foo.bar
        | {:dot_call, expr_t()}                             # foo.()
        | {:dot_container, expr_t(), [id_t()]}              # Foo.{Bar, Baz}
        | {:bracket_access, expr_t(), [expr_t()]}           # foo[0]
        | {:op_eol, op_kind(), newline_count :: non_neg_integer()}
        | {:paren_open, has_trailing_eol? :: boolean()}
        | {:paren_close, has_leading_eol? :: boolean()}
        | {:eoe, kind :: :eol | :semicolon | :eol_then_semicolon,
                    newlines :: pos_integer()}

  @type expr_t :: t()
end
```

Notes:

- `{:eoe, :eol_then_semicolon, n}` corresponds to the `eol ';'` grammar
  alternative; `to_tokens/2` will emit an `:eol` with count `n`, then `:";"`.
- `stab_clause_t` encodes pattern/guard/body (see 4.1).

### 2.2. Phases (high level)

- **Phase 1**: literals, identifiers/aliases, matched/unary/binary ops,
  `no_parens_one_expr` (one arg, no keywords), simple `fn` (single clause),
  parens calls (`foo(...)` / `foo.(...)`), `capture_int`.
- **Phase 2**: unmatched expressions, `do_block`, multi-clause `fn`, block
  lists (`else`/`rescue`/`catch`/`after`), simple stab patterns.
- **Phase 3**: full `no_parens_expr` family, `when` + keywords, more complex
  do-block / no-parens interactions.
- **Phase 4**: containers (lists/tuples/maps/bitstrings), keyword lists,
  bracket access, map/struct updates, `dot_container`.
- **Phase 5**: strings/heredocs/sigils, quoted atoms/keywords/identifiers,
  interpolation.

`grammar/1` is phase-aware (and accepts e.g. `phase: 3`), and `to_tokens/2`
respects the phase when lowering constructs.

---

## 3. Token Layout and `extra`

### 3.1. Layout

`TokenLayout` is responsible for position math; generators never see `line/col`.

```elixir
defmodule Spitfire.Property.TokenLayout do
  @type t :: %{line: pos_integer(), col: pos_integer()}

  @spec meta(t, lexeme :: iodata(), extra :: term()) :: {{line, col}, {line, col}, extra}
  @spec advance(t, lexeme :: iodata()) :: t
  @spec stick_right(t, lexeme :: iodata()) :: {meta, t}
  @spec space_before(t, lexeme :: iodata()) :: {meta, t}
end
```

- `advance/2` counts newlines inside `lexeme` as in V4 (Section 1.3).
- `stick_right/2` does not insert extra spaces; `space_before/2` ensures there
  is at least one space before `lexeme` when needed.

### 3.2. `extra` rules per token family

We use a consistent rule:

- `:identifier`, `:paren_identifier`, `:bracket_identifier`, `:do_identifier`,
  `:op_identifier`, `:alias`, `:atom`, `:kw_identifier_*` – `extra` is the
  original charlist (e.g. `~c"foo"`, `~c"MyApp.Context"`, quoted form for
  quoted identifiers), so `get_extra_or_atom/2` can reproduce the exact text.
- `:block_identifier` – `extra` `nil` (name is in the atom).
- Operator tokens – `extra` is either `nil` or newline counts (for `_eol`
  variants) as required by Toxic; we **do not** encode operator text in `extra`.
- Numbers – `extra` is the parsed numeric value (if Toxic expects it), not the
  string representation.

If Step 0 reveals a discrepancy, adjust on a per-token basis, but the default
rule above is the starting point.

### 3.3. `_op_eol` and keyword-EOL variants

We adopt a consistent pattern for `_op_eol` and keyword-EOL forms:

- Grammar tree nodes:

  ```elixir
  {:op_eol, {:match_op, :=}, n}
  {:op_eol, {:when_op, :when}, n}
  {:op_eol, {:dual_op, :+}, n}
  ```

- Tokens (model 1 – explicit `:eol`):

  ```elixir
  [{:match_op, meta_op(extra: n), :=}, {:eol, meta_eol(extra: n)}]
  ```

Same pattern for `fn_eoe`, `do_eoe`, `block_eoe`:

- Grammar tree:

  ```elixir
  {:fn_kw, newlines :: non_neg_integer()}      # 0 = no trailing eoe
  {:do_kw, newlines :: non_neg_integer()}
  {:block_kw, ident :: :after | :else | :catch | :rescue, newlines :: non_neg_integer()}
  ```

- Tokens: keyword with `extra: newlines` and a following `:eol` token when
  `newlines > 0`.

**Important for Step 0**: confirm that Toxic **does not** render newlines both
from operator/keyword `extra` and from `:eol`. If it does, flip the model:
set `extra: 0` on these tokens and rely entirely on `:eol` for rendering.

### 3.4. `%{` and other adhesion rules

Adhesive sequences include:

- `%{` → `{:%{}, "%"}`, `{:"{", "{"}`
- `&1` → `{:capture_int, :&}`, `:int` for `"1"` / `"10"`
- `foo.()` → tokens for `foo`, then `{:dot_call_op, :.}` and `"("`
- `paren_identifier`/`bracket_identifier` + their delimiters
- String/sigil start + first fragment
- `begin_interpolation`/`end_interpolation` + `"#{"`/`"}"`

`to_tokens/2` ensures no whitespace is introduced in these positions by using
`stick_right/2` appropriately.

### 3.5. Interpolation meta ordering

We make metas explicit for interpolation:

- `begin_interpolation` meta spans the `"#{"` lexeme.
- Inner tokens start **after** `{` and advance layout over their rendered code
  (which may be multi-line).
- `end_interpolation` meta spans `"}"` and starts immediately after the inner
  code.

This yields fully monotonic ranges even with multi-line inner code.

### 3.6. Heredoc positioning

For heredocs and sigil heredocs:

- After emitting `*_heredoc_start`, layout advances one line to column 1.
- Each `:string_fragment` advances over its text, including internal `\n`.
- The closing `*_heredoc_end` is placed at column `indent + 1` on the line
  after the last fragment, where `indent` is determined from the leading spaces
  of the closing delimiter.
- Tokens after heredoc start at the position just after the closing delimiter.

This matches Toxic’s behavior (to be double-checked in Step 0 against a small
set of heredoc examples).

---

## 4. Stab Expressions and `fn`

We use a single grammar tree shape for all stab clauses:

```elixir
{:stab_clause, pattern :: :empty | {:single, expr_t()} | {:many, [expr_t()]},
               guard :: nil | expr_t(),
               body :: expr_t()}
```

Phase behavior:

- Phase 1: only simple patterns (`:empty` or `{:single, expr}`), no guards; one
  clause per `fn_single`.
- Phase 2+: allow `{:many, [...]}` and guarded forms for `fn_multi` and
  `stab_parens_many`.
- Empty stab clause (`fn -> end`) is allowed but low-weight; it triggers
  `warn_empty_stab_clause/1` but warnings are suppressed in oracle options.

For guarded `stab_expr` in Phase 2 we restrict guards to `matched_expr` trees
(bounded depth) to avoid early combinatorial explosion.

---

## 5. Generators, Shrinking, and Fallback

- Generation uses `StreamData.sized/1` plus explicit `depth`.
- Each nonterminal’s generator is built using `StreamData.tree/2` so shrinks
  prefer simpler grammar trees while preserving syntactic validity.

Example for `matched_expr`:

```elixir
def gen_matched_expr(state) do
  StreamData.tree(
    gen_simple_literal(state),
    fn _simple ->
      StreamData.frequency([
        {3, gen_simple_literal(state)},
        {2, gen_binary_op_expr(state)},
        {1, gen_call_parens_expr(state)}
      ])
    end
  )
end
```

When `budget.depth == 0` or `nodes_left == 0`, all nonterminals fall back to a
small set of literals:

```elixir
@fallback_literals [nil, 0, :ok]  # ensure :ok is touched in atom pool

defp gen_fallback_literal(state) do
  StreamData.member_of(@fallback_literals)
  |> StreamData.map(fn lit -> {{:literal, lit}, state} end)
end
```

We must ensure `:ok` is present in the atom pool (or adjust the list to atoms
known to exist).

---

## 6. Keyword / No-Parens Warning Gating

We avoid generating constructs that trigger grammar warnings in the core
“valid-only” properties:

- `warn_trailing_comma/1` – avoid `foo(a,)` and similar in generators.
- `warn_pipe/2` – use context flags to avoid ambiguous `foo 1 |> bar 2` forms
  in early phases.
- `warn_no_parens_after_do_op/1` – avoid no-parens expressions immediately
  after a `do` operator without parentheses.
- `warn_nested_no_parens_keyword/2` – **disabled by default** in core
  properties; nested keyword/no-parens forms only appear when an explicit
  `warnings_on` mode is enabled.

The table from V4 Section 8 applies; V5 just clarifies that the default path is
“warnings suppressed and avoided where possible”.

---

## 7. AST Normalization

`normalize_ast/1` must strip metadata that differs between oracle and Spitfire:

- Keys to strip at minimum: `:from_brackets`, `:ambiguous_op`, `:parens`,
  `:format`, `:closing`.
- Consider also stripping `:end_of_expression` if the parser attaches it via
  `annotate_eoe/2` and it proves unstable across versions.

Implementation sketch (unchanged from V4):

```elixir
def normalize_ast(ast) do
  ast
  |> do_existing_normalization()
  |> remove_meta_keys([:from_brackets, :ambiguous_op, :parens, :format, :closing])
end
```

---

## 8. Properties and Acceptance-Rate Guard

Core property (V3/V4) stands, with the strengthened guard:

- Track `accepted` and `rejected` via helper functions.
- Assert:

  ```elixir
  assert accepted > 0
  rejection_rate = rejected / (accepted + rejected)
  assert rejection_rate < 0.7
  ```

We also add a small, **deterministic** test suite for `to_tokens/2` itself
(before property fuzzing), covering at least:

- `%{a: 1}` (dual `%{` tokens, adhesion and layout)
- `&10` (capture_int + multi-digit int)
- `foo.(1)` (dot-call adhesion)
- `1..10//2` (range + `://` semantics)
- A heredoc and sigil heredoc (indentation and closing column)

Once these pass, we can safely enable property tests per phase.

---

## 9. Final Notes

- Any ambiguity about `_op_eol` vs `:eol` rendering must be resolved by Step 0;
  if Toxic double-renders newlines, treat `extra` on operators/keywords as
  purely informational (`0` or `nil`) and rely solely on `:eol`.
- `TokenGrammarGenerators.grammar/1` returns only a grammar tree; all state and
  layout are internal.
- Phase boundaries and feature sets are as described in V3, with the clarifying
  additions here.

V5 plus the earlier phase descriptions is the **single source of truth** for
implementing the token-based property tests. It is designed to minimize
surprises when wiring up Toxic, the Elixir grammar, and Spitfire. 