# Token-Driven Property Tests Design (V3)

V3 refines V2 based on additional reviews in `TOKEN_PROP_DESIGN_V2_*`. The core
architecture (grammar-term generation → token compilation → Toxic → oracle) is
unchanged; this version:

- Keeps **grammar generation layout-free** (no `line/col` in generator state)
- Clarifies **`*_op_eol`, `open_paren`/`close_paren` EOL, and `//` after `..`**
- Tightens **layout/adhesion rules** for `Toxic.to_string/1`
- Refines **phase boundaries** (single-vs-multi-clause `fn`, keywords in
  `call_args_no_parens_one`, `block_list`, etc.)
- Adds explicit **Step 0 checklist**, **acceptance-rate assertions**, and more
  precise **context flags**

The goal remains: generate **valid Elixir programs as token sequences**
parameterized by `max_length`, `max_depth`, and `phase`, using the full Toxic
streaming token set and the Elixir grammar from
`elixir/lib/elixir/src/elixir_parser.yrl`.

---

## 0. Step 0 – Verify `Toxic.to_string/1`

Before implementing generators, we must empirically pin down `Toxic.to_string/1`.

### 0.1. Token meta format

- Try both:
  - Legacy: `{kind, {line, col, extra}}`
  - Ranged: `{kind, {{sl, sc}, {el, ec}, extra}}`
- Decide on **one canonical format** (likely ranged) and use it everywhere.
- Confirm `meta.extra` semantics for:
  - `:eol`, `:","`, `:";"` → newline-count
  - Numbers → parsed value or `nil`
  - Atoms/aliases → original charlist when needed for rendering

### 0.2. Layout & adhesion behavior

For a small hand-written set of linear token lists, verify that
`Toxic.to_string/1` → `Code.string_to_quoted/2` succeeds for:

- Basic literals and identifiers:
  - `123`, `1.0`, `?a`, `:foo`, `true`, `nil`
- Calls and operators:
  - `fn -> nil end`
  - `fn x -> x end`
  - `foo(1, 2)`
  - `foo.(1)`
  - `foo bar`
  - `&1`
  - `1..10`
  - `1..10//2` (range with step)
  - `not in` usage
  - Operator with trailing EOL: `a +\n 1`
- Containers and maps:
  - `[1, 2, 3]`
  - `{1, 2}`
  - `%{a: 1}`
  - `%Foo{a: 1}`
- Control / blocks:
  - `if true do 1 end`
  - `if true do 1 else 2 end`
- Strings/heredocs/sigils:
  - `"hello #{world}"`
  - `~r/foo/i`
  - A simple heredoc and sigil-heredoc

Also explicitly test:

- `capture_int` + `int` adjacency (`&1`, `&10`)
- `dot_call_op` + `("`): `fun.()` / `fun.(1)`
- `not in` combined token spacing

Once this suite passes, we can rely on `to_tokens/2` + `Toxic.to_string/1` as
our rendering mechanism.

---

## 1. High-Level Architecture

### 1.1. Pipeline

Property tests follow this pipeline:

1. **Grammar-term generation**: `TokenGrammarGenerators.grammar/1` produces a
   grammar tree `t :: GrammarTree.t()` plus internal generator state
   (budget/context only).
2. **Token compilation**: `TokenGrammarGenerators.to_tokens/2` walks the grammar
   tree, maintaining a **layout state** (line/col), and emits a linear list of
   Toxic streaming tokens with correct metas.
3. **Rendering**: `Toxic.to_string(tokens)` produces Elixir source.
4. **Parsing**: the source is fed to both the Elixir oracle and Spitfire.
5. **Assertions & telemetry**: AST equivalence, Toxic error/synthetic checks,
   token coverage, and acceptance-rate tracking.

### 1.2. Generator state (no layout)

Generators operate only on **structure**, not on concrete positions:

```elixir
@type budget :: %{
  depth: non_neg_integer(),        # remaining recursion depth
  nodes_left: non_neg_integer()    # approximate size cap (grammar nodes)
}

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

@type state :: %{budget: budget, context: context}

@spec gen_nonterminal(nonterminal(), state()) :: StreamData.t({GrammarTree.t(), state()})
```

- **No `layout`** in generator state – this is handled purely by `to_tokens/2`.
- `nodes_left` is an approximate size bound; we primarily rely on
  `StreamData.sized/1` plus `depth`, and only use `nodes_left` if necessary.

---

## 2. Grammar Tree and Token Mapping

### 2.1. Grammar tree types

We define a dedicated module for grammar trees:

```elixir
defmodule Spitfire.Property.GrammarTree do
  @type t ::
          {:grammar, [expr_t()]}
        | {:matched, matched_t()}
        | {:unmatched, unmatched_t()}
        | {:access, access_t()}
        | {:call_parens, target_t(), [expr_t()]}
        | {:call_no_parens_one, target_t(), expr_t()}
        | {:call_no_parens_many, target_t(), [expr_t()]}
        | {:call_no_parens_ambig, target_t(), expr_t()}
        | {:fn_single, [clause_t()]}
        | {:fn_multi, [clause_t()]}
        | {:list, [expr_t()]}
        | {:tuple, [expr_t()]}
        | {:map, map_t()}
        | {:bitstring, [expr_t()]}
        | {:string, string_t()}
        | {:sigil, sigil_t()}
        | {:op_eol, op_kind(), newline_count :: non_neg_integer()}
        | {:paren_open, with_eol? :: boolean()}
        | {:paren_close, with_leading_eol? :: boolean()}
        | {:eoe, kind :: :eol | :semicolon, newlines :: pos_integer()}
        | ...

  @type expr_t :: t()
end
```

This is schematic; implementation can refine shapes, but the key is a
**closed set of tagged tuples** used both by generators and `to_tokens/2`.

### 2.2. Context-sensitive identifiers and operators

The grammar tree encodes logical terminals; `to_tokens/2` chooses exact Toxic
kinds based on context:

- `{:id, :identifier, name}` → `{:identifier, meta, name}`
- `{:id, :alias, name}` → `{:alias, meta, name}` (must be capitalized)
- `{:dot, left, right_id}` → emits `{:.}` and appropriate identifier token
- `{:dot_call, expr}` → `to_tokens` emits tokens for `expr` then `{:dot_call_op, meta, :.}`
  followed by paren args (anonymous function call).
- Reserved words:

  ```elixir
  @reserved_literals [:true, :false, :nil]
  @block_identifiers [:after, :else, :catch, :rescue]
  @reserved_keywords [:when, :in, :not, :and, :or, :fn, :do, :end] ++ @block_identifiers
  ```

  `gen_identifier/1` never emits these as `:identifier`; instead, appropriate
  token kinds are used.

### 2.3. `*_op_eol` and EOL-aware productions

The grammar uses many `_eol` nonterminals:

```erlang
match_op_eol -> match_op : '$1'.
match_op_eol -> match_op eol : next_is_eol('$1', '$2').
```

We represent this as grammar tree nodes:

```elixir
{:op_eol, {:match_op, :=}, newlines :: non_neg_integer()}
```

`to_tokens/2` then:

- Emits `{:match_op, meta(extra: newlines), :=}`;
- Optionally follows with `{:eol, meta(extra: newlines)}` if we decide to model
  separate EOL tokens, depending on how `Toxic.to_string/1` expects them.

Similar handling applies to `dual_op_eol`, `when_op_eol`, etc.

### 2.4. `open_paren` / `close_paren` EOL variants

Grammar:

```erlang
open_paren -> '('      : '$1'.
open_paren -> '(' eol  : next_is_eol('$1', '$2').
close_paren -> ')'     : '$1'.
close_paren -> eol ')' : '$2'.
```

We encode:

- `{:paren_open, has_trailing_eol? :: boolean}`
- `{:paren_close, has_leading_eol? :: boolean}`

`to_tokens/2` ensures that:

- `(` meta has newline count in `extra` when `has_trailing_eol? == true`.
- A preceding `:eol` token is emitted before `)` when `has_leading_eol? == true`.

### 2.5. Range-step `//` semantics

Per `build_op/3` in the parser, `//` is **only valid** immediately following a
`..` range:

```erlang
build_op(AST, {_Kind, Location, '//'}, Right) ->
  case AST of
    {'..', Meta, [Left, Middle]} -> {'..//', Meta, [Left, Middle, Right]};
    _ -> return_error(...)
  end.
```

We enforce this in the grammar tree and context:

- `context.allow_ternary_after_range` is set to `true` when `range_op` was just
  used.
- The generator for `ternary_op` (`://`) only fires when
  `allow_ternary_after_range == true`.

Thus we only generate constructs like `1..10//2`, not `a // b`.

### 2.6. `capture_int` adjacency

`capture_int` + `int` must be immediately adjacent to render `&1`, `&2`, etc.
We encode this as a single grammar node, e.g. `{:capture_int, n}` and let
`to_tokens/2` emit two tokens whose metas touch:

```elixir
{:capture_int, 1} ->
  [{:capture_int, meta_for("&"), :&}, {:int, meta_for("1", after: "&"), ~c"1"}]
```

The layout helper must compute exact widths for both pieces (see Section 3).

### 2.7. Atom & alias pools; alias capitalization

We reuse existing atom/alias pools from `Spitfire.Property.Generators`:

- Aliases must be capitalized atoms (`:Foo`, `:MyApp.Context`). The alias pool
  enforces this, or we post-process by capitalizing.
- `existing_atoms_only: true` means our pools must only contain atoms known to
  be safe under the literal encoder (`elixir_literal_encoder`).

---

## 3. Layout and `TokenLayout`

Layout is used **only** in `to_tokens/2`.

```elixir
defmodule Spitfire.Property.TokenLayout do
  @type t :: %{line: pos_integer(), col: pos_integer()}

  @spec meta(t, lexeme :: iodata(), extra :: term()) :: {{line, col}, {line, col}, extra}
  @spec advance(t, lexeme :: iodata()) :: t
end
```

### 3.1. Exact widths, not approximate

- Width for each token is computed from the **exact lexeme** we will render:
  - For numbers: `Integer.to_charlist/1` or `Float.to_charlist/1`
  - For operators: the actual operator string (`"+"`, "//", "not in")
  - For sigils, heredocs, and strings: actual delimiters and fragment contents
- `advance/2` increments `col` by `IO.iodata_length(lexeme)` (or equivalent)
  and leaves `line` unchanged; EOL-handling tokens manipulate both.

### 3.2. Adhesion rules

Some tokens **must be adjacent** (no inserted whitespace):

- `{:capture_int, :&}` followed by `:int` → `"&1"`
- `{:dot_call_op, :.}` followed by `"("` → `".("`
- `paren_identifier` / `bracket_identifier` + their delimiters
- Sigil start + first fragment (`~r/` + content)
- String start + first fragment (`"` + content)
- Heredoc/sigil-heredoc start and the leading newline/indentation

`TokenLayout` provides helpers:

- `stick_right(layout, lexeme)` – no extra spacing before this lexeme.
- `space_before(layout, lexeme)` – ensure at least one space before lexeme.

`to_tokens/2` uses these rules to compute starting positions for each lexeme.

### 3.3. Interpolation lowering

For `"#{expr}"`-style interpolation:

- We emit `:string_fragment` for the part before `"#{"`.
- `begin_interpolation` and `end_interpolation` metas start from the current
  layout; inner expression tokens **advance layout** according to their
  rendered widths.
- The outer string’s layout effectively includes the width of
  `"#{" <> inner_code <> "}"`.

Same principle applies to sigils and heredocs.

### 3.4. Meta shapes and `extra`

- Ranged metas: `{{sl, sc}, {el, ec}, extra}`.
- `extra` population:
  - `:eol`/`;`/`,` → newline-count
  - Operators with `_eol` → newline-count
  - Numbers → parsed numeric value
  - Atoms/aliases → original charlist when Toxic expects it (for
    `get_extra_or_atom/2`), or `nil`.

We generate with `token_metadata: true` so `newlines_pair/2`, `newlines_op/1`,
`annotate_eoe/2`, etc. behave as expected.

---

## 4. Generator Infrastructure & Shrinking

### 4.1. Grammar-term-based generation

- `grammar/1` uses `StreamData.sized/1` and recursive generators to build
  `GrammarTree.t`:
  - Each nonterminal chooses a production via `frequency/1`.
  - Shrinking uses `StreamData.tree/2` or carefully-structured `bind/2` calls.
- Shrinks always produce **valid grammar trees**; thus they compile into valid
  token sequences.

### 4.2. Budget and context

During generation:

- `depth` is decremented on recursive descent.
- `nodes_left` may be decremented per production as an approximate bound.
- If `depth == 0` or `nodes_left == 0`:
  - Prefer leaf forms (simple literals, identifiers).
  - Fall back to a canonical minimal expression when necessary (e.g. `nil`).

We do **not** thread layout through generators.

### 4.3. Context flags

Key context fields:

- `in_no_parens_many` / `allow_no_parens_many` – disallow nested multi-arg
  no-parens calls that would hit `error_no_parens_many_strict/1`.
- `in_do_block` / `allow_do_block` – prevent illegal nested `do` blocks
  (`warn_no_parens_after_do_op/1`).
- `in_keyword_value` – restrict nested no-parens under keywords to avoid
  `warn_nested_no_parens_keyword/2` in early phases.
- `in_parens_call_arg` – govern `no_parens_expr` allowed inside `call_args_parens`.
- `allow_unmatched` – disallow `unmatched_expr` in positions where only
  `matched_expr` should appear.
- `allow_ternary_after_range` – ensure `://` only after `..`.
- `interpolation_depth` – limit nested interpolation (e.g. ≤ 2), with a
  drastically reduced budget inside interpolation.

---

## 5. Phase Design (Updated)

Phases are cumulative; higher phases only add productions.

### 5.1. Phase 1 – Core matched expressions & simple calls

Scope:

- `expr` → `matched_expr` only.
- `matched_expr`:
  - Binary ops (`matched_op_expr`), unary ops (`unary_op_eol`, `at_op_eol`,
    `capture_op_eol`, `ellipsis_op`).
  - `matched_expr -> no_parens_one_expr` (single-arg no-parens call).
  - `matched_expr -> sub_matched_expr`.
- `sub_matched_expr`:
  - `no_parens_zero_expr` (zero-arg identifier, `dot_identifier` / `dot_do_identifier`).
  - Nullary `range_op`, `ellipsis_op`.
  - `access_expr`.
- `no_parens_one_expr`:
  - Only `matched_expr` args in Phase 1; **keyword-based
    `call_args_no_parens_one` with `kw` moves to Phase 4**.
- `access_expr`:
  - Literals: `int`, `flt`, `char`, `atom` variants, `true/false/nil`.
  - `capture_int int` (`&1`, `&2`, ...).
  - `fn` expressions – **single-clause only** in Phase 1
    (multi-clause moves to Phase 2).
  - Parenthesized stab (`(x -> x)` etc.), but limit to single-clause as well.
  - `empty_paren` (`()`) – valid but emits `warn_empty_paren/1` (oracle uses
    `emit_warnings: false`).
  - `parens_call` – `dot_call_identifier call_args_parens` only
    (`foo(1, 2)`, `foo.(1)`); the curried form with **two** `call_args_parens`
    (`foo(1)(2)`) is deferred to Phase 2.
- `call_args_parens`:
  - Can contain `matched_expr` and **also `no_parens_expr`** (`foo(bar baz)`),
    but we use `in_parens_call_arg` to avoid deeply nested ambiguous forms in
    early phases.

### 5.2. Phase 2 – Unmatched expressions, do-blocks, multi-clause `fn`

Additions:

- `expr -> unmatched_expr`.
- `unmatched_expr` productions (ops, unary, `block_expr`).
- `block_expr`:
  - `dot_call_identifier call_args_parens do_block`.
  - `dot_call_identifier call_args_parens call_args_parens do_block`.
  - `dot_do_identifier do_block` (bare `if/try/case ... do`).
- `do_block` + `stab`:
  - Multi-clause anonymous functions (`fn x -> ...; y -> ... end`).
  - `stab_parens_many` (pattern lists `(a, b) -> expr`) can be introduced here
    or in Phase 3.
- `block_list`:
  - `else`, `rescue`, `catch`, `after` forms via `block_eoe` and `block_list`.

Context:

- Entering a `do_block` sets `in_do_block: true`, `allow_do_block: false` until
  we exit the block or re-enter with parentheses.

### 5.3. Phase 3 – Full no-parens expressions & `when` interactions

Additions:

- `expr -> no_parens_expr`.
- `no_parens_expr`:
  - `matched_expr no_parens_op_expr`.
  - `no_parens_one_ambig_expr`, `no_parens_many_expr`.
- `call_args_no_parens_*` family fully enabled.
- `block_expr` variants with `call_args_no_parens_all do_block`.
- Special `when_op` + keywords:

  ```erlang
  no_parens_op_expr -> when_op_eol call_args_no_parens_kw : {'$1', '$2'}.
  ```

Context:

- `in_no_parens_many` / `allow_no_parens_many` prevents invalid nested cases.
- `in_keyword_value` + `when_op` handling ensures we don’t immediately step into
  known-ambiguous keyword/no-parens patterns in early runs (we can later enable
  a “warnings allowed” mode).

### 5.4. Phase 4 – Containers, keyword lists, access, map/struct updates

Additions:

- Containers: `list`, `tuple`, `bitstring`, all `container_expr` variants.
- Maps and structs:
  - `%{}` and `%{...}` (`map`, `map_op`, `map_args`, `assoc`, `kw_data`).
  - `%Alias{}` and updates via `assoc_update` and `assoc_update_kw`.
  - `map_base_expr` constraints (what can appear after `%`).
- Keyword lists:
  - `kw_eol`, `kw_base`, `kw_call`, `kw_data`.
  - `call_args_no_parens_kw_expr`, `call_args_no_parens_kw`.
  - `call_args_no_parens_one` now includes the `kw`-only-flavor.
- Access:
  - `bracket_expr`, `bracket_at_expr`, `bracket_arg`.
  - `dot_bracket_identifier` + `:bracket_identifier` emission.
- `dot_container` (`Foo.{Bar, Baz}`) multi-alias container, placed here with
  other container forms.

Error/warning paths to avoid in “valid-only” mode:

- `error_too_many_access_syntax/1` – disallow `value[a, b, c]`.
- `bad_keyword/3` – avoid keyword lists directly inside tuple/bitstring
  positions that grammar forbids.
- `error_no_parens_container_strict/1` – avoid ambiguous no-parens inside
  containers.

We can later add a dedicated “warnings/errors exercise” property that enables
these branches explicitly.

Map/struct update bias:

- `gen_assoc_update/1` only selects `%{}` or `%Alias{}` shapes as LHS in normal
  mode to avoid oracle rejections; arbitrary `matched_expr` LHS can be reserved
  for a separate negative/stress mode.

### 5.5. Phase 5 – Strings, heredocs, sigils, quoted identifiers/atoms

Additions:

- Strings:
  - Binary and list strings with interpolated parts.
- Heredocs:
  - Binary and list heredocs, including indentation/strip behavior.
- Sigils:
  - Regular sigils (`~r/foo/iu`) vs heredoc sigils (`~S"""..."""`).
- Quoted atoms and keywords:
  - `atom_quoted`, `atom_safe`, `atom_unsafe`, `kw_identifier_safe`,
    `kw_identifier_unsafe`.
- Quoted identifiers:
  - Forms that collapse into `identifier`, `paren_identifier`,
    `bracket_identifier`, `do_identifier`, `op_identifier` depending on
    following token.

Interpolation restrictions:

- Interpolation contents use a **restricted grammar**:
  - Only `matched_expr` inside `#{...}`.
  - No nested strings of the same delimiter.
  - Small `depth` and `nodes_left`.
- `interpolation_depth` ≤ 2 to prevent explosion.

String/sigil fragment safety:

- Fragments avoid unescaped delimiters.
- If no interpolation is present, avoid producing `"#{` in literal fragments.
- Sigil start/end delimiters must match; modifiers consistent with sigil start.

---

## 6. Properties & Telemetry

### 6.1. Core positive property

As in V2, but with an explicit **acceptance-rate assertion**:

```elixir
@property_timeout 120_000
@tag :skip
property "parses oracle-accepted programs from token grammar" do
  oracle_opts = [columns: true, token_metadata: true, emit_warnings: false, existing_atoms_only: true]
  parser_opts = [tokenizer: :toxic, columns: true, token_metadata: true, existing_atoms_only: true]

  check all grammar <- TokenGrammarGenerators.grammar(phase: phase(), max_tokens: 80, max_depth: 10),
            max_runs: 1500,
            max_size: 5 do
    tokens = TokenGrammarGenerators.to_tokens(grammar, phase: phase())
    code = Toxic.to_string(tokens)

    case Code.string_to_quoted(code, oracle_opts) do
      {:ok, oracle_ast} ->
        track_acceptance(:accepted)
        track_token_coverage(tokens)

        assert {:ok, spitfire_ast} = Spitfire.parse(code, parser_opts)
        assert normalize_ast(spitfire_ast) == normalize_ast(oracle_ast)
        assert_no_toxic_errors(code)
        assert_no_synthetic_tokens(code)

      {:error, _reason} ->
        track_acceptance(:rejected)
        :ok
    end
  end

  {accepted, rejected} = get_acceptance_counts()
  total = max(accepted + rejected, 1)
  rejection_rate = rejected / total
  assert rejection_rate < 0.7
end
```

### 6.2. Token round-trip property (later)

Same as V2, but with more explicit `normalize_tokens/1` rules:

- Drop metas entirely.
- Treat `:eol` count differences as irrelevant.
- Normalize `identifier` vs `paren_identifier` only when followed by `(`.
- Normalize `capture_int` + `int` tokens into a canonical `{:capture_int, n}`
  shape for comparison.
- Assume combined `:"not in"` form is the only valid `in_op` in the stream; if
  Toxic later changes, extend normalization accordingly.

### 6.3. Warning-producing productions

Document per phase which warning paths are **enabled**:

- Early phases: keep `warn_empty_paren` and similar but accept that warnings are
  suppressed by `emit_warnings: false`.
- More complex warnings (`warn_nested_no_parens_keyword`, `warn_pipe`,
  `warn_no_parens_after_do_op`) can be gated behind an option
  (`warnings_mode: :off | :on`) and tested separately.

### 6.4. Negative property for `error_token`

As in V2: a separate property that generates malformed token sequences to
exercise `{:error_token, ...}` and structural recovery. Not part of the
valid-program design.

---

## 7. Implementation Plan (Refined)

### 7.1. Step 0 checklist

Implement a small `ToxicToStringSmokeTest` module with explicit tests for the
checklist in Section 0.2. Only continue once all cases parse successfully.

### 7.2. Phase 1 implementation

1. Implement `Spitfire.Property.GrammarTree` type definitions.
2. Implement Phase-1 generators:
   - `gen_literal/1`, `gen_identifier/1`, `gen_matched_expr/1`,
     `gen_sub_matched_expr/1`, `gen_access_expr/1`, `gen_parens_call/1`,
     `gen_fn_single/1`.
3. Implement `TokenGrammarGenerators.to_tokens/2` for Phase-1 tree nodes.
4. Add **deterministic unit tests** for `to_tokens/2` + `Toxic.to_string/1` for
   a small set of hand-built trees: `&1`, `foo(1)`, `foo.(1)`, `fn x -> x end`,
   `1..10`, `1..10//2`.
5. Add a Phase-1-only property (tagged `:skip` initially) and tune budgets.

### 7.3. Phases 2–5

Incrementally add nonterminals, context updates, and `to_tokens/2` clauses per
phase as described in Section 5. For each phase, add:

- Unit tests for new grammar-tree cases → tokens → `Toxic.to_string/1`.
- A property run with modest budgets and acceptance monitoring.

---

## 8. How V3 Refines V2

V3 keeps the V2 architecture but:

- Removes `layout` from generator state, confining positional logic to
  `to_tokens/2` + `TokenLayout`.
- Makes layout widths **exact**, with explicit adhesion rules and interpolation
  lowering details.
- Specifies grammar-tree representations for `_op_eol`, `open_paren` /
  `close_paren` EOL variants, `//` after `..`, and alias/keyword constraints.
- Refines phase boundaries (single-clause `fn` only in Phase 1, multi-clause in
  Phase 2; keywords in `call_args_no_parens_one` in Phase 4; `block_list` and
  `dot_container` placement).
- Adds concrete context flags (`in_parens_call_arg`,
  `allow_ternary_after_range`, etc.) and guidance on which productions/warnings
  are enabled per phase.
- Strengthens telemetry with an explicit acceptance-rate assertion and more
  precise round-trip normalization rules.

This V3 document should serve as a precise, implementation-ready blueprint for
phaseable, token-driven property tests for Spitfire. 