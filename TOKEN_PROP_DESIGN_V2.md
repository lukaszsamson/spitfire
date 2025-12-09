# Token-Driven Property Tests Design (V2)

This is a revised design for token-driven property tests addressing review
comments from `TOKEN_PROP_DESIGN_V1_*`. The main changes are:

- Aligning with **Toxic.to_string/1’s current linear-token API**
- Clarifying **metadata/layout policy** for tokens
- Correcting **phase contents** (especially around `fn`, `parens_call`,
  `no_parens_one_expr`, `capture_int`)
- Introducing **context-aware generation** and **structured shrinking**
- Making `eoe`/EOL handling, atom pools, and coverage/acceptance telemetry
  explicit

The ultimate goal remains: generate **valid Elixir programs as token sequences**
parameterized by `max_length`, `max_depth`, and `phase`, using the full Toxic
token set from `ALL_TOKENS.md` and the grammar in
`elixir/lib/elixir/src/elixir_parser.yrl`.

---

## 0. Assumptions and Step 0: Verify Toxic Interface

Before implementing generators, we will empirically verify the behavior of
`Toxic.to_string/1` with a small hand-written test module (outside property
infrastructure):

1. **Token format**
   - Try both **legacy** metas: `{kind, {line, col, extra}}` and
     **ranged** metas: `{kind, {{sl, sc}, {el, ec}, extra}}`.
   - Confirm which shapes `Toxic.to_string/1` accepts for linear streaming
     tokens (e.g. `{:int, meta, chars}`, `{:identifier, meta, atom}`,
     `{:",", meta}`, `{:eol, meta}`, `{:sigil_start, ...}`, etc.).
   - Decide on a single canonical meta format (likely ranged, to match current
     Toxic internals) and stick to it.

2. **Spacing / layout behavior**
   - Confirm how `Toxic.to_string/1` uses:
     - `meta` positions (`start_line`, `start_col`, `end_*`)
     - `meta.extra` (e.g. newline counts for `:eol`, `:","`, `:";"`)
     - Combined operators (`{:in_op, meta_span, :"not in", in_meta}`).
   - Validate that with **monotonic positions** and reasonable width
     approximations, `Toxic.to_string/1` preserves token ordering and minimal
     spacing without gluing tokens together or breaking operators.

3. **Minimal hand-crafted examples**
   - Build a tiny test with 5–10 token lists representing:
     - literals/identifiers
     - `fn -> ... end`
     - `foo(1, 2)` and `foo bar`
     - `&1`, `%{a: 1}`, `[1, 2]`, `if true do 1 end`
     - a simple sigil and string with interpolation
   - For each: `tokens -> Toxic.to_string(tokens) -> Code.string_to_quoted/2` and
     assert `{:ok, _}`.

Only after this step is green do we proceed to implementing generators.

All design below assumes:

- **Linear Toxic streaming tokens**, as described under
  "Streaming Tokens (Linear Output)" in `ALL_TOKENS.md`
- **Ranged metas** for simplicity, but abstracted via helper functions

---

## 1. High-Level Architecture

### 1.1. Generator pipeline

Property tests will follow this pipeline:

1. Use `Spitfire.Property.TokenGrammarGenerators.grammar/1` to generate a
   **grammar-level term** (structured nonterminal tree) together with a budget
   and context.
2. Compile this grammar tree into a **linear token list** of Toxic streaming
   tokens using a deterministic compiler:
   `Spitfire.Property.TokenGrammarGenerators.to_tokens/2`.
3. Render code with `Toxic.to_string(tokens)`.
4. Pass the code to the Elixir oracle and Spitfire, as in existing tests.
5. Optionally collect token coverage / acceptance metrics and (in a later
   phase) perform a token round-trip check.

Separating **grammar-structure generation** from **token emission** gives us:

- Grammar-aware shrinking (StreamData shrinks the structured tree, not raw
  tokens).
- A single place to enforce layout/meta policy for tokens.

### 1.2. Generator state

We represent state as:

```elixir
@type budget :: %{
  depth: non_neg_integer(),        # remaining recursion depth
  tokens_left: non_neg_integer()   # remaining token budget
}

@type context :: %{
  phase: 1..5,
  in_do_block: boolean(),          # inside body of a do/end block
  in_no_parens_many: boolean(),    # inside no_parens_many args
  in_keyword_value: boolean(),     # inside kw value position
  allow_unmatched: boolean(),      # position where unmatched_expr is valid
  allow_do_block: boolean(),       # can we attach a do_block here?
  allow_no_parens_many: boolean(), # can we use multi-arg no-parens here?
  interpolation_depth: non_neg_integer()
}

@type layout :: %{
  line: pos_integer(),
  col: pos_integer()
}

@type state :: %{budget: budget, context: context, layout: layout}
```

- **Budget** enforces depth/size limits.
- **Context** enforces grammar/semantic constraints (no invalid no-parens
  nesting, do-block rules, etc.).
- **Layout** is used only for metadata: every emitted token gets a meta derived
  from layout, and layout is then advanced by an approximate token width;
  `:eol` and other EOL-carrying tokens advance `line` and reset `col`.

All nonterminal generators will have the shape:

```elixir
@spec gen_nonterminal(nonterminal(), state()) :: StreamData.t({grammar_term(), state()})
```

Where `grammar_term()` encodes a particular nonterminal (e.g. `{:matched_expr,
subtrees}`), not yet tokens.

---

## 2. Mapping Grammar to Toxic Tokens

### 2.1. Context-sensitive tokens

Some Toxic token kinds are **context-sensitive** (they encode adjacency or
special roles):

- `{:paren_identifier, meta, atom}` – identifier immediately followed by `(`.
- `{:bracket_identifier, meta, atom}` – identifier immediately followed by `[`.
- `{:do_identifier, meta, atom}` – identifier rewritten to support `if/try` etc.
- `{:op_identifier, meta, atom}` – operator-as-identifier (e.g. `def +/2`).
- `{:bracket_identifier, ...}` / `:dot_bracket_identifier` vs `:identifier`.

The **grammar tree** we generate will speak in terms of **grammar terminals**
(`identifier`, `paren_identifier`, `bracket_identifier`, `do_identifier`, etc.).
The compiler `to_tokens/2` is responsible for:

- Choosing the proper **streaming token kind** given the grammar terminal and
  neighboring tokens.
- Ensuring `bracket_identifier` and `paren_identifier` are used where
  `elixir_parser.yrl` expects them (e.g. `bracket_expr` must involve a
  `bracket_identifier`, not a plain `identifier`).

For example, during compilation we will have patterns like:

```elixir
# Dot-identifier production in grammar tree
{:dot_identifier, left_expr, identifier_atom} ->
  # to_tokens/2 will produce roughly:
  #   tokens_for(left_expr) ++ [{:., meta_dot}] ++ [{:identifier, meta_id, atom}]

{:dot_bracket_identifier, left_expr, identifier_atom} ->
  # produces {:bracket_identifier, ...} + ["[", ...]
```

### 2.2. Terminal → streaming-token mapping

We keep terminal names aligned with `elixir_parser.yrl` but map them to Toxic
**streaming** tokens (not collapsed) in `to_tokens/2`.

Representative mappings (not exhaustive):

- **Literals / scalars**
  - `int` → `{:int, meta(extra_int_value), chars}`
  - `flt` → `{:flt, meta(extra_float_value), chars}`
  - `char` → `{:char, meta(extra_original_chars), codepoint}`
  - `'true'` / `'false'` / `'nil'` → `{true, meta}` / `{false, meta}` / `{nil, meta}`
  - `atom` → `{:atom, meta(extra_chars_or_nil), atom}`

- **Collapsed string-like constructs (Phase 5)**
  - `bin_string` → `{:bin_string_start, meta, ?"}` + `:string_fragment` /
    interpolation markers + `{:bin_string_end, meta2, ?"}`
  - `list_string` → same with single-quote variants
  - `bin_heredoc` / `list_heredoc` → `*_start`, `:string_fragment`, `*_end`
  - `sigil` → `{:sigil_start, ...}`, `:string_fragment`/interpolation,
    `{:sigil_end, ...}`, `{:sigil_modifiers, ...}`

  The grammar tree will use high-level nodes (`{:bin_string, parts}`,
  `{:sigil, sigil_atom, parts, modifiers, indent, delim}`), which are then
  **lowered** to the linear start/fragment/end tokens in `to_tokens/2`.

- **Identifiers & aliases**
  - `identifier` → `{:identifier, meta(extra_chars), atom}`
  - `paren_identifier` → `{:paren_identifier, meta(extra_chars), atom}`
  - `bracket_identifier` → `{:bracket_identifier, meta(extra_chars), atom}`
  - `do_identifier` → `{:do_identifier, meta(extra_chars), atom}`
  - `op_identifier` → `{:op_identifier, meta(extra_chars), atom}`
  - `alias` → `{:alias, meta(extra_chars), atom}`
  - `dot_call_op` → `{:dot_call_op, meta, :.}`

- **Operators** (all as described in `ALL_TOKENS.md`)
  - `unary_op` → `{:unary_op, meta, op}`
  - `dual_op` → `{:dual_op, meta, op}`
  - `mult_op` → `{:mult_op, meta, op}`
  - `rel_op` → `{:rel_op, meta, op}`
  - `comp_op` → `{:comp_op, meta, op}`
  - `and_op` → `{:and_op, meta, op}`
  - `or_op` → `{:or_op, meta, op}`
  - `xor_op` → `{:xor_op, meta, op}`
  - `concat_op` → `{:concat_op, meta, op}`
  - `arrow_op` → `{:arrow_op, meta, op}`
  - `power_op` → `{:power_op, meta, op}`
  - `range_op` → `{:range_op, meta, :..}`
  - `in_match_op` → `{:in_match_op, meta, op}`
  - `type_op` → `{:type_op, meta, :"::"}`
  - `stab_op` → `{:stab_op, meta, :->}`
  - `match_op` → `{:match_op, meta, :=}`
  - `pipe_op` → `{:pipe_op, meta, :|}`
  - `ellipsis_op` → `{:ellipsis_op, meta, :...}`
  - `ternary_op` → `{:ternary_op, meta, :"//"}`
  - `assoc_op` → `{:assoc_op, meta, :"=>"}`
  - `at_op` → `{:at_op, meta, :@}`
  - `capture_op` → `{:capture_op, meta, :&}`
  - `capture_int` → `{:capture_int, meta, :&}` followed by `{:int, meta2, chars}`
  - `when_op` → `{:when_op, meta, :when}`
  - `in_op` → either `{:in_op, meta, :in}` or
    `{:in_op, meta_span, :"not in", in_meta}` (single token)

- **Punctuation & delimiters**
  - `'.'` → `{:., meta}`
  - `','` → `{:",", meta(extra_newlines)}`
  - `';'` → `{:";", meta(extra_newlines)}`
  - `'('` / `')'` → `{:"(", meta}`, `{:")", meta}`
  - `'['` / `']'` → `{:"[", meta}`, `{:"]", meta}`
  - `'{'` / `'}'` → `{:"{", meta}`, `{:"}", meta}`
  - `'<<'` / `'>>'` → `{:"<<", meta}`, `{:">>", meta}`
  - `'%{}'` → `{:%{}, meta}` (emitted with `{:"{", meta2}` as per Toxic)
  - `'%'` → `{:%, meta}`

- **Control & reserved words**
  - `'do'` / `'end'` / `'fn'` → `{:do, meta}` / `{:end, meta}` / `{:fn, meta}`
  - `block_identifier` → `{:block_identifier, meta, :after | :else | :catch | :rescue}`

- **Structural**
  - `eol` → `{:eol, meta(extra_newline_count)}`

### 2.3. Identifiers vs reserved words

`gen_identifier/1` must respect Toxic’s distinction between:

- Reserved literals: `{true, meta}`, `{false, meta}`, `{nil, meta}`
- Keyword operators: `{:when_op, meta, :when}`, `{:in_op, ...}`
- Block identifiers: `{:block_identifier, meta, atom}`
- Regular identifiers: `{:identifier, meta, atom}`

We will:

- Maintain **dedicated pools** for identifiers/aliases and atoms, reusing
  `Spitfire.Property.Generators` pools where possible.
- Ensure `gen_identifier` excludes all reserved words unless the grammar rule
  explicitly requires them in a specific token kind.

### 2.4. Atom & alias pools and `existing_atoms_only`

Given current property opts (`existing_atoms_only: true`), arbitrary random
atoms and aliases may cause oracle/Toxic failures. We will:

- Reuse atom/alias pools and `touch_atom_pools/0` from
  `Spitfire.Property.Generators`.
- Prefer **known-safe atom values** (those preloaded in tests) when generating
  `:atom`, `:atom_safe`, `:atom_unsafe`, `:kw_identifier` variants, and alias
  tokens.
- Optionally drop `existing_atoms_only` for exploratory fuzzing in non-CI
  runs.

---

## 3. Layout / Metadata Policy

We introduce a small **Layout** helper to consistently generate metas:

```elixir
defmodule Spitfire.Property.TokenLayout do
  @type t :: %{line: pos_integer(), col: pos_integer()}

  @spec meta(t, extra :: term()) :: {{line, col}, {line, col}, extra}
  @spec advance(t, token_repr :: term()) :: t
end
```

Key points:

- All tokens get **monotonic** `(line, col)` positions.
- `advance/2` approximates token width from its value (e.g. length of charlist
  for `:int`, atom name length, etc.). We do not need pixel-perfect width, only
  enough for `to_string/1` to place whitespace correctly.
- `:eol`, `:","`, and `:";"` set `extra` to the newline count and advance
  `line` and reset `col`.
- For `{:in_op, meta_span, :"not in", in_meta}`, `to_tokens/2` constructs both
  metas from layout so `Toxic.to_string` can render `not in` with required
  space.

We also define a helper:

```elixir
@spec gen_eoe(state()) :: StreamData.t({grammar_eoe_term(), state()})
```

that emits either an `eol`-based or `;`-based end-of-expression, updating
layout appropriately and occasionally coalescing multiple newlines
(`extra > 1`).

---

## 4. Generator Infrastructure and Shrinking

### 4.1. Grammar-term-based generation

Instead of directly generating `[token]`, we generate a **grammar term tree**
that mirrors `elixir_parser.yrl` nonterminals, e.g.:

- `{:grammar, [expr1, expr2, ...]}`
- `{:matched_expr, left, {:op, op_kind, right}}`
- `{:access_expr, literal_or_call}`
- `{:fn_expr, clauses}`
- `{:call_parens, target, args}`
- `{:no_parens_one_call, target, arg}`
- `{:list, elems}`
- etc.

Properties:

- **Shrinking** is performed by StreamData on this tree, using
  `StreamData.tree/2` and `StreamData.bind/2`.
- Each nonterminal generator returns a tree whose structure mirrors the chosen
  production.
- We can explicitly define **simpler alternatives** for shrinking a given
  nonterminal (e.g. any `expr` can shrink to a simple literal or identifier).

Only at the end do we call `to_tokens/2` to flatten the tree into linear
streaming tokens using our layout helpers.

This guarantees that shrinking **never produces syntactically invalid token
sequences**: a shrunk tree is still a valid grammar tree.

### 4.2. Budget and context handling

Each nonterminal generator uses and updates `state`:

- On recursive descent:
  - Decrement `depth` in `budget`.
  - Potentially tweak `context` flags (e.g. entering a no-parens call sets
    `in_no_parens_many: true` for its args, which disallows further
    `no_parens_many` nesting).
- On emitting a terminal (at compile time):
  - Decrement `tokens_left` (we can also approximate token count during term
    construction to avoid overshooting too badly).

If `depth` or `tokens_left` are exhausted, generators:

- Prefer **leaf productions** for that nonterminal (e.g. literal, identifier).
- If no leaf is available, fall back to a canonical minimum (e.g. `nil`, `0`,
  a 1-expression grammar block).

### 4.3. Context fields and restrictions

We use `context` to enforce constraints not expressible in the bare grammar:

- `in_no_parens_many` and `allow_no_parens_many`
  - Prohibit nested multi-arg no-parens calls where the grammar and
    `error_no_parens_many_strict/1` would reject them.
- `in_do_block` and `allow_do_block`
  - Prevent attaching `do` blocks inside contexts where they are invalid (e.g.
    nested no-parens calls without parens) and avoid constructs that would
    trigger `warn_no_parens_after_do_op/1`.
- `in_keyword_value`
  - Used to control nested no-parens inside keyword lists and avoid triggering
    `warn_nested_no_parens_keyword/2` in early phases.
- `allow_unmatched`
  - Certain positions (e.g. the right side of `->` or inside containers) may
    disallow `unmatched_expr`.

Interpolation uses a dedicated `interpolation_depth` and drastically reduced
budget:

- On entering interpolation: increment `interpolation_depth`, but enforce a
  hard limit (e.g. `<= 2`). If the limit is reached, restrict inner expressions
  to simple matched literals/identifiers only.

---

## 5. Phase Design (Corrected)

Phases are cumulative; each phase adds productions while reusing existing
infrastructure.

### 5.1. Phase 1 – Core matched expressions and basic calls

Goal: exercise `matched_expr`, `access_expr`, and the **subset of no-parens
syntax that is integrated into matched expressions**.

Included (non-exhaustive but representative):

- `grammar`, `expr_list`, `expr` restricted to:
  - `expr -> matched_expr`.
- `matched_expr` productions:
  - `matched_expr -> matched_expr matched_op_expr`.
  - `matched_expr -> unary_op_eol matched_expr`.
  - `matched_expr -> at_op_eol matched_expr`.
  - `matched_expr -> capture_op_eol matched_expr`.
  - `matched_expr -> ellipsis_op matched_expr`.
  - `matched_expr -> no_parens_one_expr` (single-arg no-parens call).
  - `matched_expr -> sub_matched_expr`.
- `sub_matched_expr` productions:
  - `sub_matched_expr -> no_parens_zero_expr` (zero-arg identifier use).
  - `sub_matched_expr -> range_op` (nullary range).
  - `sub_matched_expr -> ellipsis_op` (nullary ellipsis).
  - `sub_matched_expr -> access_expr`.
- `no_parens_zero_expr`:
  - `dot_do_identifier` and `dot_identifier` forms via `build_identifier/1`.
- `no_parens_one_expr`:
  - Single-argument calls `dot_op_identifier call_args_no_parens_one` and
    `dot_identifier call_args_no_parens_one` (where `call_args_no_parens_one`
    is just `[matched_expr]` or a keyword-only arg in later phases).
- `access_expr` (Phase 1 subset):
  - `capture_int int` (`&1`, `&2`, etc.).
  - `fn_eoe stab_eoe 'end'` – basic `fn` expressions.
  - `open_paren stab_eoe ')'` and variants – parenthesized stab/clauses.
  - `empty_paren` – `()` (valid but emits warning).
  - Numeric literals: `int`, `flt`, `char`.
  - Literals: `'true'`, `'false'`, `'nil'`.
  - Atoms: `atom`, `atom_quoted`, `atom_safe`, `atom_unsafe`.
  - `dot_alias`.
  - `parens_call` (via `dot_call_identifier call_args_parens` and nested
    variants): `foo(1, 2)`, `foo.(1)`.

Tokens covered:

- All numeric/char literals, atom variants, reserved bool/nil.
- Identifiers, aliases, `dot_call_op` (for `fun.()`), `capture_int`.
- Unary and binary operator families via `matched_op_expr` and `unary_op_eol`.
- `fn`, stabs (`stab_op`), and paren calls.

### 5.2. Phase 2 – Unmatched expressions and do-blocks

Goal: introduce `unmatched_expr` and `block_expr`, including bare `if/try` and
simple multi-clause anonymous functions.

Additions:

- `expr -> unmatched_expr`.
- `unmatched_expr` productions:
  - `unmatched_expr -> matched_expr unmatched_op_expr`.
  - `unmatched_expr -> unmatched_expr matched_op_expr`.
  - `unmatched_expr -> unmatched_expr unmatched_op_expr`.
  - `unmatched_expr -> unmatched_expr no_parens_op_expr` (with guardrails via
    `context.allow_no_parens_many`).
  - `unmatched_expr -> unary_op_eol expr`.
  - `unmatched_expr -> at_op_eol expr`.
  - `unmatched_expr -> capture_op_eol expr`.
  - `unmatched_expr -> ellipsis_op expr`.
  - `unmatched_expr -> block_expr`.
- `block_expr` forms (Phase 2 subset):
  - `dot_call_identifier call_args_parens do_block`.
  - `dot_call_identifier call_args_parens call_args_parens do_block`.
  - `dot_do_identifier do_block` (bare `if expr do ... end`).
  - We delay no-parens `call_args_no_parens_all` + `do_block` combinations to
    Phase 3.
- `do_block` / `stab` / `stab_expr`:
  - Start with simpler forms:
    - `do_block -> do_eoe 'end'`.
    - `do_block -> do_eoe stab_eoe 'end'`.
  - `stab_expr -> expr` and `stab_expr -> stab_op_eol_and_expr`.
  - Defer when-guards and complex `stab_parens_many` patterns to later phases.
- Handle `fn_eoe`, `do_eoe`, `block_eoe` and their `eol`-aware productions to
  exercise metadata-sensitive paths (`newlines_pair/2`, `annotate_eoe/2`).

Context updates:

- Entering a `do_block` sets `in_do_block: true`, `allow_do_block: false` for
  nested contexts unless parentheses are used.

### 5.3. Phase 3 – Full no-parens expressions

Goal: enable all `no_parens_expr` variants (one, many, ambig) and their
interactions with `do` blocks and unmatched expressions, while respecting the
no-parens grammar constraints.

Additions:

- `expr -> no_parens_expr`.
- `no_parens_expr` productions as in the grammar, now including:
  - `no_parens_expr -> no_parens_one_ambig_expr`.
  - `no_parens_expr -> no_parens_many_expr`.
- `call_args_no_parens_*` family:
  - `call_args_no_parens_expr`, `call_args_no_parens_comma_expr`,
    `call_args_no_parens_one`, `call_args_no_parens_ambig`,
    `call_args_no_parens_many`, `call_args_no_parens_many_strict`.
- `block_expr` extensions that combine no-parens call heads with `do_block`.

Context-driven restrictions:

- Inside `call_args_no_parens_many`, set `in_no_parens_many: true` and
  `allow_no_parens_many: false` for nested calls to avoid invalid
  `foo a, bar b, c`-style constructs.
- Inside keyword values and inside `do_block` args, restrict nested no-parens
  to avoid triggering `warn_nested_no_parens_keyword/2` and similar warnings in
  early phases.

### 5.4. Phase 4 – Containers, keyword lists, access

Goal: exercise lists, tuples, maps/structs, bitstrings, keyword lists, access
syntax (`value[...]`), and `assoc_update` forms.

Additions:

- Containers:
  - `list`, `list_args`, `container_expr`, `container_args_base`,
    `container_args`.
  - `tuple`.
  - `bitstring` (`open_bit`, `close_bit`).
  - `map`, `map_op`, `map_args`, `map_base_expr`, `map_close`, `assoc`,
    `assoc_base`, `assoc_expr`, `assoc_update`, `assoc_update_kw`.
- Keyword lists:
  - `kw_eol`, `kw_base`, `kw_call`, `kw_data`.
  - `call_args_no_parens_kw_expr`, `call_args_no_parens_kw`.
- Access / brackets:
  - `bracket_arg`, `bracket_expr`, `bracket_at_expr`.
  - Ensure use of `:bracket_identifier` tokens via `dot_bracket_identifier`.

Special care:

- `assoc_update` (`struct_expr |>` map): bias grammar so its left side is
  actually a map/struct-like expression (`%{}`, `%Alias{}`) to avoid
  oracle-level errors.
- Access syntax `foo[0]` must generate `{:bracket_identifier, ...}` rather than
  a plain `:identifier`.
- We gate productions that would hit `bad_keyword/3` or
  `error_no_parens_container_strict/1` until we are ready to exercise those
  error paths (possibly in a dedicated negative property).

### 5.5. Phase 5 – Strings, heredocs, sigils, interpolation, quoted forms

Goal: cover remaining token families: string/heredoc tokens, sigils, quoted
atoms/keywords/identifiers, interpolation.

Additions:

- High-level grammar terms for:
  - `bin_string`, `list_string` with parts: `[binary | interpol_part]`.
  - `bin_heredoc`, `list_heredoc` with indentation and parts.
  - `sigil` with `sigil_atom`, parts, modifiers, indent, delimiter.
  - `atom_quoted`, `atom_safe`, `atom_unsafe` with parts.
  - `kw_identifier_safe`, `kw_identifier_unsafe`.
- Interpolation helper:

  ```elixir
  @type interpol_part :: {begin_meta, end_meta, [tokens]}

  @spec gen_interpolated_expr(state()) :: StreamData.t({interpol_part(), state()})
  ```

  which uses a **restricted grammar** (typically just `matched_expr`, small
  depth/budget) when `context.interpolation_depth` is below a hard limit
  (e.g. `2`).

Lowering to linear tokens in `to_tokens/2` produces:

- Proper start/end tokens (`*_start`/`*_end`, `:begin_interpolation`,
  `:end_interpolation`).
- String fragments that avoid unescaped delimiters and `"#{` when not in
  interpolation.
- Consistent heredoc indentation and delimiters.

---

## 6. Properties

### 6.1. Core positive property (Phase-selectable)

As in V1, but with additional telemetry:

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
end
```

- `track_acceptance/1` keeps counts of accepted vs rejected examples (ETS or
  agent). We can assert in a separate test that acceptance rate per phase stays
  above some threshold (e.g. 30–50%).
- `track_token_coverage/1` inserts token kinds into an ETS table for a summary
  at the end of the run.

### 6.2. Token round-trip property (later phase)

Given the fragility of round-tripping (identifier kind rewrites, `:eol`
coalescing, `:in` vs `:"not in"`), we treat this as a **Phase 6** / opt-in
property once generators are stable:

```elixir
@property_timeout 120_000
@tag :skip
property "token grammar round-trips through Toxic (normalized)" do
  check all grammar <- TokenGrammarGenerators.grammar(phase: phase(), max_tokens: 80, max_depth: 10) do
    tokens = TokenGrammarGenerators.to_tokens(grammar, phase: phase())
    code = Toxic.to_string(tokens)

    tokens2 =
      code
      |> Toxic.new(1, 1,
        error_mode: :tolerant,
        insert_structural_closers: true,
        existing_atoms_only: true
      )
      |> TokenIntrospection.collect_tokens()

    assert normalize_tokens(tokens2) == normalize_tokens(tokens)
  end
end
```

`normalize_tokens/1` will:

- Drop metadata entirely.
- Map known-equivalent token kinds into canonical forms, e.g.:
  - `{:in_op, _, :"not in", _}` and `{:not, ...} + {:in, ...}` considered
    equivalent where appropriate.
  - Accept `identifier` vs `paren_identifier` differences if they still result
    in identical code under `Toxic.to_string/1`.
- Tolerate differences in `:eol` counts that do not change semantics.

### 6.3. Future negative property (error_token)

We keep the idea from V1: a separate property that intentionally generates
invalid token sequences to ensure `{:error_token, meta, %Toxic.Error{}}` is
emitted and that structural recovery behaves as expected. This uses a
**different generator** and is not part of the "valid program" design.

---

## 7. Implementation Plan (Updated)

### 7.1. Step order

1. **Step 0** – Verify `Toxic.to_string/1` behavior (Section 0).
2. Implement `Spitfire.Property.TokenLayout` with `meta/2` and `advance/2`.
3. Implement a minimal `TokenGrammarGenerators` with:
   - Grammar-term types (Elixir structs or tagged tuples) for Phase 1.
   - `gen_matched_expr/1`, `gen_access_expr/1`, `gen_literal/1`,
     `gen_identifier/1`, `gen_parens_call/1`, `gen_fn_expr/1`.
   - `grammar/1` producing one or more expressions separated by `eoe`.
   - `to_tokens/2` for Phase 1 terms.
4. Add a Phase-1-only property and run locally with small budgets.
5. Incrementally add Phase 2–5 nonterminals and extend `to_tokens/2`.
6. Add acceptance and coverage telemetry.
7. Once stable, add the optional round-trip property with permissive
   normalization.

### 7.2. Utilities and helpers

- **Token constructors** wrapping layout and pools, e.g.:

  ```elixir
  def int_token(state, value) do
    chars = Integer.to_charlist(value)
    meta = layout_meta(state.layout, value)
    token = {:int, meta, chars}
    {token, advance_layout(state, token)}
  end
  ```

- **Validation helper** used in early development (not in final property):

  ```elixir
  def valid_token_sequence?(tokens) do
    code = Toxic.to_string(tokens)
    match?({:ok, _}, Code.string_to_quoted(code, []))
  rescue
    _ -> false
  end
  ```

- **Nonterminal exposure** (for unit tests of individual generators):

  ```elixir
  @spec available_nonterminals(phase()) :: [atom()]
  def available_nonterminals(phase), do: ...
  ```

### 7.3. Debugging support

- `grammar/1` will accept a `:debug` option that logs grammar trees and/or token
  lists.
- Provide a small curated list of **tricky cases** to sanity-check `to_tokens/2`
  and layout behavior before enabling large fuzzing runs.

---

## 8. Summary of How V2 Addresses Review Comments

- **Toxic interface**: V2 explicitly targets **linear streaming tokens** and
  demands an empirical Step 0 for `Toxic.to_string/1`.
- **Layout/meta**: Introduces `TokenLayout` and a concrete policy for metas,
  newline counts, and `in_op :"not in"` handling.
- **Phase corrections**: Moves `fn`, `parens_call`, `capture_int`, `empty_paren`,
  parenthesized stabs, `no_parens_one_expr`, `no_parens_zero_expr` into
  **Phase 1**, and clarifies Phase 2–5 scopes accordingly.
- **Context tracking**: Adds a rich `context` map controlling no-parens,
  do-blocks, keyword contexts, and interpolation depth.
- **Shrinking**: Switches to **grammar-term-based** generation with structured
  shrinking, ensuring shrinks remain valid programs.
- **EOL/_eol handling**: Introduces `gen_eoe` and explicitly covers
  EOL-sensitive productions (`fn_eoe`, `do_eoe`, `open_paren` with `eol`).
- **Atom pools & `existing_atoms_only`**: Reuses existing pools and acknowledges
  the constraint explicitly.
- **Containers/access**: Clarifies `bracket_identifier` usage, struct/map
  updates, and biasing valid expressions.
- **Interpolation limits & coverage/acceptance telemetry**: Adds strict
  interpolation depth/budget, token coverage tracking, and acceptance rate
  monitoring.

This V2 design should be a practical and robust blueprint for implementing
phaseable, token-driven property tests for Spitfire while fully leveraging the
Elixir grammar and Toxic tokenizer. 