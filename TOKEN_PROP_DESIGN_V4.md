# Token-Driven Property Tests Design (V4)

V4 is a light refinement of V3 based on `TOKEN_PROP_DESIGN_V3_*` reviews. The
architecture (grammar-term generation → token compilation → Toxic → oracle)
remains the same; this version mainly:

- Removes remaining ambiguities (especially around `*_op_eol` and EOL tokens)
- Clarifies a few implementation-focused details (numbers/atoms, escaping,
  heredoc indentation, shrinking fallbacks)
- Tightens acceptance-rate assertions and layout rules

This document is intentionally concise and focused on additions/clarifications
relative to V3, which remains the main blueprint.

---

## 1. Clarifications on EOL and Layout

### 1.1. `_op_eol` / `eol` model – **explicit EOL tokens**

We adopt a single, explicit model:

- `_op_eol` grammar nodes always generate **both**:
  - An operator token whose `meta.extra` is the newline count
  - A separate `{:eol, meta}` token with the same newline count

Example grammar node and linearization:

```elixir
# Grammar
{:op_eol, {:match_op, :=}, 2}

# Tokens
[{:match_op, meta_op(extra: 2), :=}, {:eol, meta_eol(extra: 2)}]
```

This applies consistently to all `_op_eol` nonterminals (`match_op_eol`,
`dual_op_eol`, `when_op_eol`, etc.).

### 1.2. `open_paren` / `close_paren` EOL handling

We also commit to explicit `:eol` tokens for paren variants:

- `{:paren_open, true}` (i.e. `"(\n"` in the grammar) yields:

  ```elixir
  [{:"(", meta_open(extra: 1)}, {:eol, meta_eol(extra: 1)}]
  ```

- `{:paren_close, true}` (i.e. `"\n)"` in the grammar) yields:

  ```elixir
  [{:eol, meta_eol(extra: 1)}, {:")", meta_close(extra: 0)}]
  ```

We do not mix “implicit newlines via layout coordinates” with “no `:eol` token”;
all newlines visible to Toxic are carried by `:eol`, `:","`, or `:";"` with
non-zero `extra`.

### 1.3. Multi-line lexemes and layout advancement

`TokenLayout.advance/2` must handle lexemes that include newlines (string
fragments, heredoc chunks, interpolated code inside sigils, etc.):

- Compute `lexeme` as iodata; then:

  ```elixir
  lines = :binary.split(IO.iodata_to_binary(lexeme), "\n", [:global])
  case length(lines) do
    1 -> %{state | col: state.col + byte_size(hd(lines))}
    n ->
      last = List.last(lines)
      %{state | line: state.line + (n - 1), col: byte_size(last) + 1}
  end
  ```

- This ensures subsequent tokens start on the correct line/column after a
  multi-line string/heredoc fragment or interpolated expression code.

### 1.4. `%{` adhesion

Toxic emits **two** tokens for `%{`:

- `{:%{}, meta_percent}` and `{:"{", meta_brace}`.

`to_tokens/2` treats `%{` as an adhesive pair:

- The `{:%{}, ...}` lexeme is `"%"`, and `{:"{", ...}` is `"{"`; their metas
  use `stick_right` semantics so no whitespace appears between them in
  `Toxic.to_string/1` output.

### 1.5. Interpolation meta path

We make explicit the interpolation token layout:

- `begin_interpolation` starts at the current layout **before** emitting `"#{"`.
- Inner interpolation tokens advance layout over the rendered code in `#{...}`.
- `end_interpolation` starts immediately after the inner code and `"}"`.

This ensures metas are monotonic and the outer string’s meta covers the entire
`"#{...}"` span.

---

## 2. Token `extra` for Atoms/Aliases/Identifiers

For tokens where Toxic may use `extra` to reconstruct the original lexeme:

- **Identifiers / aliases / atoms**:
  - We set `meta.extra` to the original charlist (e.g. `~c"foo"`,
    `~c"MyApp.Context"`) when available.
  - We reserve `nil` for cases where the lexeme is trivially derivable from the
    atom name and no special formatting (quotes, case) is needed.

This matches `get_extra_or_atom/2` expectations in Toxic and avoids surprises
when rendering.

---

## 3. Acceptance-Rate Assertion

We strengthen the acceptance-rate check to catch both high rejection and zero
acceptance:

```elixir
{accepted, rejected} = get_acceptance_counts()

assert accepted > 0

total = accepted + rejected
rejection_rate = rejected / total
assert rejection_rate < 0.7
```

This ensures the generator actually produces valid samples and isn’t overly
skewed toward oracle rejections.

---

## 4. Numeric, Atom, String and Char Formats

### 4.1. Integer and float formats

We explicitly vary numeric formats to exercise Toxic and the grammar:

- Integers:
  - Decimal: `123`, `1_000_000`
  - Hex: `0x1F`, `0x1_F`
  - Binary: `0b1010`, `0b10_10`
  - Octal: `0o777`, `0o7_7_7`
- Floats:
  - Plain: `1.0`, `1_000.0`
  - Exponent: `1.0e10`, `1.0e-10`

Generator helper:

```elixir
@spec gen_int_literal(state()) :: StreamData.t({:int, integer(), format :: :dec | :hex | :bin | :oct})
```

`to_tokens/2` chooses the appropriate textual representation based on `format`,
then feeds it to `TokenLayout.meta/advance/2`.

### 4.2. Atom formats

We distinguish atom formats by phase:

- Phase 1:
  - Simple unquoted atoms from a safe pool: `:foo`, `:bar`, etc.
  - Operator atoms (e.g. `:++`, `:..`, `:"not in"`) only where needed as
    operator tokens, not general literals.
- Phase 5:
  - Quoted atoms: `:"foo bar"`, `:'foo'`.
  - Quoted atoms with interpolation via `atom_safe`/`atom_unsafe` containers.

`gen_atom/1` is phase-aware and uses pools accordingly.

### 4.3. Character literals & escapes

We define a helper for char lexemes:

```elixir
@spec char_to_lexeme(char()) :: iodata()

def char_to_lexeme(?\n), do: ~c"?\n"
def char_to_lexeme(?\t), do: ~c"?\t"
def char_to_lexeme(?\r), do: ~c"?\r"
def char_to_lexeme(?\"), do: ~c"?\""
def char_to_lexeme(?\\), do: ~c"?\\"
# Fallback: printable vs \x{..}
def char_to_lexeme(cp) when cp in 32..126, do: [??, cp]
def char_to_lexeme(cp), do: [??, ?\x, ?{] ++ Integer.to_charlist(cp, 16) ++ [?}]
```

`to_tokens/2` uses this to compute lexemes and exact widths for `:char` tokens.

### 4.4. String fragment escaping

String fragments must be safe with respect to delimiters and backslashes; we
introduce:

```elixir
@spec escape_string_fragment(binary(), delimiter :: char(), allow_interpolation? :: boolean()) :: binary()

def escape_string_fragment(content, delimiter, allow_interp?) do
  content
  |> String.replace("\\", "\\\\")
  |> String.replace(<<delimiter>>, "\\" <> <<delimiter>>)
  |> maybe_escape_interp(allow_interp?)
end

defp maybe_escape_interp(content, true), do: content
defp maybe_escape_interp(content, false), do: String.replace(content, "#\{", "\\#\{")
```

This is used when lowering `bin_string`/`list_string` and sigil fragments in
Phase 5.

### 4.5. Sigil modifiers and token sequence

For sigils like `~r/foo/iu`, we emit (simplified):

```elixir
[
  {:sigil_start, meta_start, :sigil_r, "/"},
  {:string_fragment, meta_frag, "foo"},
  {:sigil_end, meta_end, ?/, 0},
  {:sigil_modifiers, meta_mod, ~c"iu"}
]
```

Heredoc sigils differ only in delimiter representation and `indent` tracking.

### 4.6. Heredoc indentation

For heredocs:

- `indent` in `*_heredoc_end` is the indentation level Toxic computes; we
  reproduce the same logic:
  - Roughly: indent = column of closing `"""` or `'''` minus 1.
- `TokenLayout.advance/2` must:
  - Advance over the leading newline after `*_heredoc_start`.
  - Advance line/col across all heredoc content lines.
  - Position the closing delimiter at the correct indentation column for
    subsequent tokens.

We will follow Toxic’s current implementation for exact semantics.

---

## 5. Stab Expressions and `fn` Edge Cases

We refine `stab_expr` handling in the grammar tree to cover guarded and
parenthesized stabs:

```elixir
# Grammar tree
{:stab_clause, pattern :: :empty | {:single, expr_t()} | {:many, [expr_t()]},
               guard :: nil | expr_t(),
               body :: expr_t()}
```

Examples:

- `fn -> body end` → pattern `:empty`, guard `nil`, `body` as expr
- `fn x -> body end` → pattern `{:single, x}`, guard `nil`
- `fn (a, b) when g -> body end` → pattern `{:many, [a, b]}`, guard `g`

Empty stab clause (`fn -> end`) is grammar-valid but issues `warn_empty_stab_clause/1`:

- We treat it as allowed (since warnings are suppressed) but can give it lower
  weight in generators so it appears rarely.

Multi-clause `fn` remains Phase 2 as in V3.

---

## 6. Additional Generator Details

### 6.1. Shrinking strategy

We make shrinking patterns explicit, using `StreamData.tree/2`. Example for
`matched_expr`:

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

This guarantees shrinks prefer simpler structures while staying within the
grammar of `matched_expr`.

### 6.2. Fallback behavior when budget exhausted

When `depth == 0` or `nodes_left == 0`, all nonterminal generators fall back to
`gen_fallback_literal/1`:

```elixir
def gen_expr(%{budget: %{depth: 0} = _b} = state), do: gen_fallback_literal(state)

@fallback_literals [nil, 0, :ok]

defp gen_fallback_literal(state) do
  StreamData.member_of(@fallback_literals)
  |> StreamData.map(fn lit -> {{:literal, lit}, state} end)
end
```

This keeps generation total and avoids recursion blowups.

### 6.3. `access_expr kw_identifier` error path

We explicitly forbid generating `access_expr` immediately followed by
`kw_identifier` (which would hit `error_invalid_kw_identifier/1`):

- The generator for `sub_matched_expr` **never** chooses a production of the
  form `{:access, ...}` followed by a standalone `kw_identifier`.
- Keyword identifiers only appear in:
  - Keyword list contexts (`kw_call`, `kw_data`)
  - `call_args_no_parens_kw_expr`.

### 6.4. `dot_do_identifier` vs `dot_identifier`

We clarify use:

- `dot_do_identifier` is used when generating block-forming identifiers (`if`,
  `case`, `cond`, `try`, `receive`, etc.) that will be followed by `do_block`.
- `dot_identifier` is used for regular identifiers in zero-arg or call
  positions.
- In Phase 1 (no do-blocks), only `dot_identifier` is used.
- In Phases 2+, the generator selects `dot_do_identifier` only when
  `context.allow_do_block == true` and the production will indeed attach a
  `do_block`.

---

## 7. AST Normalization Notes

`normalize_ast/1` must be aware that oracle and Spitfire may differ in some
metadata keys. We recommend stripping at least:

- `:from_brackets`
- `:ambiguous_op`
- `:parens`
- `:format`
- `:closing`

Implementation sketch:

```elixir
def normalize_ast(ast) do
  ast
  |> do_existing_normalization()
  |> remove_meta_keys([:from_brackets, :ambiguous_op, :parens, :format, :closing])
end
```

This keeps comparisons robust while focusing on structural equality.

---

## 8. Warning Productions Summary (Reference)

We add a small table (non-binding but useful during implementation):

| Warning                        | Trigger example              | Typical phase | Default handling              |
|--------------------------------|------------------------------|---------------|------------------------------|
| `warn_empty_paren`             | `()`                         | 1+            | Allowed; warnings suppressed |
| `warn_empty_stab_clause`       | `fn -> end`                  | 2+            | Allowed but low-weight       |
| `warn_trailing_comma`          | `foo(a,)`                    | 4+            | Avoid in generators          |
| `warn_pipe`                    | `foo 1 |> bar 2`             | 3+            | Avoid via context flags      |
| `warn_no_parens_after_do_op`   | `do expr + no_parens`        | 3+            | Avoid via context flags      |
| `warn_nested_no_parens_keyword`| `foo(a: bar b, c)`           | 4+            | Avoid via context flags      |

We keep the main properties in “valid programs, warnings suppressed” mode and
can introduce a separate property to exercise warning paths if needed.

---

## 9. Consistency & API Notes

- `TokenGrammarGenerators.grammar/1` returns **only** the grammar tree
  (`GrammarTree.t`); generator state is internal.
- `gen_nonterminal/2` and other helpers are internal to the generators module.
- `to_tokens/2` respects the `phase` option for phase-specific lowering (e.g.
  not emitting Phase-5-only tokens when running Phase-1 tests).

---

V4, together with V3, should give a clear and implementation-ready picture of
how to build phaseable, token-driven property tests for Spitfire, with no major
ambiguities left around EOL handling, token adhesion, or complex edge cases. 