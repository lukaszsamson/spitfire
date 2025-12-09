# Token-Driven Property Tests Design (V6)

V6 is the final, consolidated implementation spec for token-driven properties.
It is based on V5 plus the V5 review documents (`*_V5_*`), and is intended to
stand alone as the blueprint for implementation.

The high-level pipeline is unchanged:

- Generate a **grammar tree** with `TokenGrammarGenerators.grammar/1`
- Compile that tree to **linear Toxic streaming tokens** via
  `TokenGrammarGenerators.to_tokens/2` using `TokenLayout`
- Render source with `Toxic.to_string(tokens)`
- Parse with the Elixir oracle and Spitfire, compare normalized ASTs, and check
  tokenizer properties

Only the deltas from V5 are emphasized; everything else from V5 that is not
contradicted here still applies.

---

## 1. Step 0 – `Toxic.to_string/1` Verification (Expanded)

Step 0 must be implemented and run before any property fuzzing.

### 1.1. Meta format and `extra`

- Use **ranged metas**: `{kind, {{sl, sc}, {el, ec}, extra}}`.
- Confirm `extra` behavior:
  - `:eol`, `:","`, `:";"` – newline count (>= 1)
  - Numbers – parsed numeric value (or `nil` if Toxic ignores it)
  - Atoms/aliases/identifiers/kw identifiers – original charlist when available
  - Operators, `:block_identifier` – `extra` `nil` or `0` (see 3.3)

### 1.2. Smoke-test checklist (extended)

For hand-written token sequences, assert
`Toxic.to_string(tokens) |> Code.string_to_quoted/2` succeeds for:

- Literals and numeric formats:
  - `123`, `1_000_000`
  - `0x1F`, `0x_1_F`, `0b1010`, `0b10_10`, `0o777`, `0o7_7_7`
  - `1.0`, `1_000.0`, `1.0e10`, `1.0e-10`, `1_000_000.0e-10`
  - `?a`, `?\n`, `?\\`
- Atoms/quoted forms:
  - `:foo`, `:"foo bar"`, `:"foo\nbar"`
- Calls/operators:
  - `fn -> nil end`, `fn x -> x end`
  - `foo(1, 2)`, `foo.(1)`, `foo bar`
  - `&1`, `&10`, `1..10`, `1..10//2`
  - `a +\n 1`, `foo |> bar |> baz`, `not in`-using expressions
- Containers and maps:
  - `[1, 2]`, `{1, 2}`, `%{a: 1}`, `%Foo{a: 1}`, `%{m | key: 1}`
- Blocks and guards:
  - `if true do 1 end`, `if true do 1 else 2 end`
  - `case x do\n  y when is_atom(y) -> y\nend`
- Strings/sigils/heredocs:
  - `"hello #{world}"`
  - `"""a\nb\n"""`
  - `~r/foo/iu`
  - A sigil heredoc with interpolation, e.g. `~s"""foo #{bar}\n"""`

Also verify all adhesion and EOL cases in Sections 3.3–3.5 & 8.

If any behavior deviates (e.g. double newlines, wrong adhesion), adjust
`TokenLayout`/`to_tokens/2` and **then freeze that behavior** before writing
any generators.

---

## 2. Grammar Tree – Complete Node Set (Reference)

V5’s Section 2.1 was illustrative; this section gives the **complete node
families** needed for implementation. You do not need every constructor if your
implementation chooses slightly different shapes, but nothing should be
conceptually missing.

```elixir
defmodule Spitfire.Property.GrammarTree do
  @type t ::
          # Top-level / expression categories
          {:grammar, [expr_t()]}
        | {:matched, matched_t()}
        | {:unmatched, unmatched_t()}
        | {:no_parens, no_parens_t()}
        | {:sub_matched, sub_matched_t()}
        | {:access, access_t()}

        # Literals
        | {:int, integer(), format :: :dec | :hex | :bin | :oct, chars :: charlist()}
        | {:float, float(), chars :: charlist()}
        | {:char, codepoint :: integer()}
        | {:atom_lit, atom()}
        | {:atom_quoted_lit, atom(), delimiter :: char()}
        | {:bool_lit, true | false}
        | :nil_lit

        # Identifiers and aliases
        | {:identifier, atom()}
        | {:paren_identifier, atom()}
        | {:bracket_identifier, atom()}
        | {:do_identifier, atom()}
        | {:op_identifier, atom()}
        | {:alias, atom()}

        # Calls and dot
        | {:call_parens, target_t(), [expr_t()]}
        | {:call_nested_parens, target_t(), [expr_t()], [expr_t()]}
        | {:call_no_parens_one, target_t(), expr_t()}
        | {:call_no_parens_many, target_t(), [expr_t()]}
        | {:call_no_parens_ambig, target_t(), expr_t()}
        | {:dot, expr_t(), id_t()}
        | {:dot_call, expr_t()}
        | {:dot_container, expr_t(), [alias_t()]}

        # Operators / ranges / captures
        | {:binary_op, expr_t(), {:op_eol, op_kind(), non_neg_integer()}, expr_t()}
        | {:unary_op, op_kind(), expr_t()}
        | {:at_op, expr_t()}
        | {:capture_op, expr_t()}
        | {:capture_int, pos_integer()}  # &1, &2, ...
        | {:range, expr_t(), expr_t()}
        | {:range_step, expr_t(), expr_t(), expr_t()}  # 1..10//2
        | :nullary_range
        | :nullary_ellipsis

        # Blocks / do-blocks
        | {:block_expr, call_t(), do_block_t()}
        | {:do_block, stab_or_exprs :: stab_t() | [expr_t()], [block_item_t()]}
        | {:block_item, ident :: :after | :else | :catch | :rescue, stab_or_exprs}

        # Functions / stabs
        | {:fn_single, [stab_clause_t()]}
        | {:fn_multi, [stab_clause_t()]}
        | {:stab_clause, pattern_t(), guard_t(), expr_t()}

        # Containers
        | {:list, [expr_t()]}
        | {:tuple, [expr_t()]}
        | {:bitstring, [expr_t()]}
        | {:map, [assoc_t()]}
        | {:map_update, expr_t(), [assoc_t()]}
        | {:struct, alias_t(), [assoc_t()]}
        | {:struct_update, alias_t(), expr_t(), [assoc_t()]}

        # Assocs / keyword data
        | {:assoc, expr_t(), expr_t()}      # key => value
        | {:kw, atom(), expr_t()}           # key: value
        | {:kw_list, [{atom(), expr_t()}]}

        # Bracket access
        | {:bracket_access, expr_t(), [expr_t()]}
        | {:bracket_at_access, expr_t(), [expr_t()]}

        # Strings / sigils / heredocs
        | {:bin_string, [string_part_t()]}
        | {:list_string, [string_part_t()]}
        | {:bin_heredoc, non_neg_integer(), [string_part_t()]}
        | {:list_heredoc, non_neg_integer(), [string_part_t()]}
        | {:sigil, sigil_atom :: atom(), delimiter :: binary(),
                  [string_part_t()], modifiers :: charlist(), indent :: non_neg_integer()}

        # Quoted forms
        | {:atom_safe, [string_part_t()]}
        | {:atom_unsafe, [string_part_t()]}
        | {:kw_identifier_safe, [string_part_t()]}
        | {:kw_identifier_unsafe, [string_part_t()]}
        | {:quoted_identifier, [string_part_t()],
           kind :: :identifier | :paren | :bracket | :do | :op}

        # Structural / EOL / keywords
        | {:op_eol, op_kind(), newlines :: non_neg_integer()}
        | {:paren_open, has_trailing_eol? :: boolean()}
        | {:paren_close, has_leading_eol? :: boolean()}
        | {:eoe, :eol | :semicolon | :eol_then_semicolon, newlines :: pos_integer()}
        | {:fn_kw, newlines :: non_neg_integer()}
        | {:do_kw, newlines :: non_neg_integer()}
        | {:block_kw, ident :: :after | :else | :catch | :rescue,
                     newlines :: non_neg_integer()}

  @type expr_t :: t()
end
```

Helper aliases (not types in the AST itself):

```elixir
@type target_t ::
        {:identifier, atom()}
      | {:paren_identifier, atom()}
      | {:dot, expr_t(), id_t()}
      | {:dot_call, expr_t()}

@type id_t :: {:identifier, atom()} | {:op_identifier, atom()}
@type alias_t :: {:alias, atom()}
```

Implementations may choose to simplify some node families, but this list should
serve as a complete reference.

### 2.3. Context flags (consolidated)

We collect all context flags used across V3–V5:

```elixir
@type context :: %{
  phase: 1..5,
  in_do_block: boolean(),
  in_no_parens_many: boolean(),
  in_keyword_value: boolean(),
  in_parens_call_arg: boolean(),
  allow_unmatched: boolean(),
  allow_do_block: boolean(),
  allow_no_parens_many: boolean(),
  allow_ternary_after_range: boolean(),
  interpolation_depth: non_neg_integer()
}
```

---

## 3. Token Layout and `extra` – Canonical Model

V6 removes the branching in V5 around `_op_eol` and newlines.

### 3.1. Canonical newline model

- **Canonical rule**: **only `:eol`/`;`/`,` tokens render newlines**.
- Operators and keywords **never** render newlines from `extra`.
- For `_op_eol` and `*_eoe` variants:
  - We set operator/keyword `extra` to `0` or `nil`.
  - We emit an explicit `{:eol, meta(extra: n)}` token carrying the newline
    count.

Step 0 must confirm that Toxic indeed renders newlines solely from `:eol`/
`;`/`,` tokens under this model; if not, we adapt **only in code**, but this
spec remains the canonical abstraction for the property tests.

### 3.2. Atom/identifier `extra` table

We make the `extra` policy explicit per token family:

| Token kind family                              | `extra` value                            |
|-----------------------------------------------|------------------------------------------|
| `:identifier`, `:paren_identifier`            | original chars (e.g. `~c"foo"`)         |
| `:bracket_identifier`, `:do_identifier`       | original chars                           |
| `:op_identifier`                              | original chars                           |
| `:alias`                                      | original chars (e.g. `~c"MyApp.Mod"`)   |
| `:atom` / `:atom_quoted`                      | original chars                           |
| `:kw_identifier_*`                            | original chars                           |
| `:block_identifier`                           | `nil`                                    |
| Operator tokens (all op families)             | `nil` (newline info carried by `:eol`)   |
| `:eol`, `:","`, `:";"`                     | newline count (`extra >= 1`)             |
| Numbers (`:int`, `:flt`)                      | parsed numeric value or `nil`            |

This matches earlier textual guidance and prevents implementation drift.

### 3.3. Interpolation and heredoc metas

- `begin_interpolation` meta spans from `#` through `{` (`"#{"`).
- Inner interpolation tokens start after `{` and advance layout over their
  entire rendered code.
- `end_interpolation` meta covers only `"}"` and starts immediately after the
  inner code (even if multi-line).

Heredoc/sigil heredoc rules:

- After `*_heredoc_start`, layout moves to the next line at column 1.
- Each `:string_fragment` advances layout over its bytes (including newlines).
- The closing `*_heredoc_end` meta starts at column `indent + 1` on the line
  after the last fragment, where `indent` equals the count of leading spaces in
  the closing delimiter.
- Tokens after the heredoc start immediately after that closing delimiter.

Deterministic tests (Section 8) must include a concrete heredoc/sigil-heredoc
example that asserts the closing delimiter’s column.

---

## 4. Stab Expressions and Guards

The `{:stab_clause, pattern, guard, body}` node remains as in V5.

Per phase:

- **Phase 1**:
  - Patterns: `:empty` and `{:single, expr}` only.
  - Guards: **disabled** (must be `nil`).
  - All `fn` are `fn_single` and single-clause.
- **Phase 2+**:
  - Patterns: allow `{:many, [expr_t()]}` and parenthesized pattern lists.
  - Guards: enabled but restricted to `matched_expr` trees and small depth.
  - `fn_multi` and more complex `stab_parens_many` become available.

This keeps Phase 1 simple while still allowing full generality later.

---

## 5. Generators, Shrinking, Fallback (Unchanged Semantics)

The shrinking and fallback strategies from V5 remain, with the clarifications
above; refer back to V5 for examples. The key points:

- Use `StreamData.tree/2` to ensure shrinks preserve grammar validity.
- Use a small fallback literal set (`[nil, 0, :ok]`) when depth or node budget
  is exhausted, ensuring the atom pool includes any atoms used there.

---

## 6. Keyword / No-Parens Warnings – Default Gating

We make the default behavior explicit:

- Core properties run with `emit_warnings: false` and an internal
  `warnings_on: false` flag.
- In this mode, generators **do not** intentionally emit constructs known to
  trigger:
  - `warn_trailing_comma/1`
  - `warn_pipe/2`
  - `warn_no_parens_after_do_op/1`
  - `warn_nested_no_parens_keyword/2`
- A separate, opt-in mode (`warnings_on: true`) may be added later to exercise
  these paths; that mode will have its own properties.

This avoids accidental warning-producing shapes in the core “valid program”
properties.

---

## 7. Deterministic `to_tokens/2` Tests (Expanded)

Before enabling any fuzzing, add deterministic ExUnit tests that:

1. Construct small grammar trees by hand.
2. Run `to_tokens/2` and `Toxic.to_string/1`.
3. Assert:
   - `Code.string_to_quoted/2` succeeds.
   - Token kinds, adhesion-sensitive positions, and key metas (e.g. heredoc
     closing column) match expectations.

Test cases should include at least:

- Adhesion:
  - `%{a: 1}` (`%{` dual tokens, no space between `%` and `{`).
  - `&10` (capture + multi-digit int).
  - `foo.(1)` (no space between `.` and `(`).
- EOL variants:
  - Operator `_op_eol` with several newline counts and explicit `:eol` tokens.
  - `fn_kw`, `do_kw`, and `block_kw` with/without trailing EOL.
- Literals:
  - One example of each integer format, float format, and key char escape.
- Identifier families:
  - `identifier`, `paren_identifier`, `bracket_identifier`, `do_identifier`,
    `op_identifier` used in appropriate contexts.
- Strings/interpolation:
  - A multi-line string with interpolation where inner code is multi-line.
- Containers:
  - A map update expression (`%{m | key: value}`).
- Heredoc/sigil heredoc:
  - At least one example where you assert the column of the closing
    delimiter and the starting position of the following token.

These tests form a “golden suite” for `to_tokens/2` and `TokenLayout` and
should be run anytime token logic changes.

---

## 8. AST Normalization and Acceptance Guard (Unchanged)

V5’s AST normalization and acceptance-rate guard remain as-is:

- Strip meta keys: `:from_brackets`, `:ambiguous_op`, `:parens`, `:format`,
  `:closing` (and optionally `:end_of_expression` if unstable).
- Enforce:

  ```elixir
  assert accepted > 0
  rejection_rate = rejected / (accepted + rejected)
  assert rejection_rate < 0.7
  ```

These ensure we’re comparing structural ASTs and that the generators are
actually producing a healthy proportion of valid samples.

---

## 9. Final Notes

- V6 fixes the remaining ambiguities in V5 (newline source for `_op_eol`,
  interpolation/heredoc metas, guard scope, warning gating defaults) while
  keeping the overall design unchanged.
- Treat this file as the **single source of truth**; earlier versions are
  historical.
- Implementation should proceed in this order: Step 0 → `TokenLayout` →
  `GrammarTree` → Phase 1 generators + `to_tokens/2` + deterministic tests →
  property tests per phase.
