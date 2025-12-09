# Token-Driven Property Tests Design (V1)

Goal: design a property-based test that generates **valid Elixir programs as token sequences** constrained by
`max_length` and `max_depth`, based on the original Elixir grammar
`elixir_parser.yrl`, and using the full Toxic token set described in
`ALL_TOKENS.md`. The generator should be **phaseable** (small grammar subsets
first, then progressively more language features), and the tests should work by
round-tripping tokens through `Toxic.to_string/1` and parsing the resulting
programs with both the Elixir oracle and Spitfire.

This document focuses on **design only**; implementation will live alongside the
existing property infrastructure in `Spitfire.Property.*`.

---

## 1. High-Level Approach

### 1.1. Token-level instead of string-level generation

Existing tests in `test/spitfire_property_test.exs` generate random programs as
**strings** via `Spitfire.Property.Generators.program/1`, then:

1. Parse with the Elixir oracle (`Code.string_to_quoted/2`).
2. Parse with Spitfire.
3. Compare normalized ASTs and assert no Toxic tokenizer errors.

For the new property we instead:

1. Generate **lists of collapsed/legacy tokens** whose *tags* match the
   terminals in `elixir_parser.yrl`.
2. Turn the token list into source code with `Toxic.to_string(tokens)`.
3. Re-use the same oracle + Spitfire pipeline as the existing property.
4. Optionally re-tokenize the resulting string with Toxic and assert that (up to
   metadata and normalizations) we get an **equivalent token sequence**.

This keeps the oracle unchanged while letting us directly control which tokens
and grammar rules we exercise.

### 1.2. Grammar-aware generator

The generator will be **grammar-driven**:

- We mirror the `Nonterminals` and key productions from `elixir_parser.yrl`.
- For each nonterminal `N` we define an Elixir generator function
  `gen_N(depth, budget, phase)` that returns a list of tokens and an updated
  budget.
- The generators are **depth- and length-bounded**:
  - `depth` – remaining recursive depth; recursive calls must decrease it.
  - `budget` – remaining token slots; terminal emissions decrement it.
- The top-level generator produces a `grammar` nonterminal, which (per yrl) is
  essentially a `__block__` of expressions separated by `eoe` (`eol` or `;`).

The generator is **phase-aware**: each phase exposes a subset of productions
and token kinds; higher phases are supersets of lower ones.

---

## 2. Mapping Elixir Grammar to Toxic Tokens

### 2.1. Token shape and compatibility

The yrl grammar expects tokens of shapes like:

- `{'true', Location}`
- `{identifier, Location, Atom}`
- `{int, Location, Value}`

The Toxic reference (`ALL_TOKENS.md`) defines **collapsed/legacy** tokens with
nearly identical shapes, differing mostly in metadata representation:

- `{:int, meta, chars}` with `meta.extra` being the parsed integer.
- `{:identifier, meta, atom}`.
- `{true, meta}` / `{false, meta}` / `{nil, meta}`.

For the property tests, we **do not feed the tokens directly** into
`elixir_parser.yrl`; instead we rely on `Toxic.to_string/1` → source → official
Elixir parser. This lets us:

- Use exactly the token shapes that `Toxic.to_string/1` expects.
- Ignore minor mismatches between the Elixir tokenizer and Toxic, because the
  oracle only sees the *string*.

We will still keep the **terminal names** aligned with the grammar (e.g.
`identifier`, `kw_identifier`, `range_op`, `'('`, `eol`, etc.) by mapping each
terminal to a constructor for the corresponding Toxic token.

### 2.2. Terminal → token mapping

We define a small table (or functions) mapping grammar terminals to token
constructors. Examples:

- Literals / scalars:
  - `int` → `{:int, meta(), chars}` where `chars` and `meta.extra` agree.
  - `flt` → `{:flt, meta(), chars}`.
  - `char` → `{:char, meta(), codepoint}`.
  - `atom` → `{:atom, meta(), atom}`.
  - `atom_quoted` → `{:atom_quoted, meta(), atom}`.
  - `atom_safe` / `atom_unsafe` → `{:atom_safe, meta(), parts}` /
    `{:atom_unsafe, meta(), parts}`.
  - `bin_string` → `{:bin_string, meta(), parts}`.
  - `list_string` → `{:list_string, meta(), parts}`.
  - `bin_heredoc` / `list_heredoc` → `{:bin_heredoc, meta(), indent, parts}` /
    `{:list_heredoc, meta(), indent, parts}`.
  - `sigil` → `{:sigil, meta(), sigil_atom, parts, modifiers, indent, delim}`.

- Identifiers & aliases:
  - `identifier` → `{:identifier, meta(), atom}`.
  - `paren_identifier` → `{:paren_identifier, meta(), atom}`.
  - `bracket_identifier` → `{:bracket_identifier, meta(), atom}`.
  - `do_identifier` → `{:do_identifier, meta(), atom}`.
  - `op_identifier` → `{:op_identifier, meta(), atom}`.
  - `alias` → `{:alias, meta(), atom}`.
  - `dot_call_op` → `{:dot_call_op, meta(), :.}`.
  - Grammar pseudo-terminals `dot_identifier`, `dot_alias`, etc. are *derived
    nonterminals* that combine these tokens with `:{".", meta}`.

- Operators (all have Toxic counterparts):
  - `unary_op` → `{:unary_op, meta(), op}`.
  - `dual_op` → `{:dual_op, meta(), op}`.
  - `mult_op` → `{:mult_op, meta(), op}`.
  - `comp_op` → `{:comp_op, meta(), op}`.
  - `rel_op` → `{:rel_op, meta(), op}`.
  - `and_op` → `{:and_op, meta(), op}`.
  - `or_op` → `{:or_op, meta(), op}`.
  - `xor_op` → `{:xor_op, meta(), op}`.
  - `concat_op` → `{:concat_op, meta(), op}`.
  - `arrow_op` → `{:arrow_op, meta(), op}`.
  - `power_op` → `{:power_op, meta(), op}`.
  - `range_op` → `{:range_op, meta(), op}`.
  - `in_match_op` → `{:in_match_op, meta(), op}`.
  - `type_op` → `{:type_op, meta(), op}`.
  - `stab_op` → `{:stab_op, meta(), op}`.
  - `match_op` → `{:match_op, meta(), op}`.
  - `pipe_op` → `{:pipe_op, meta(), op}`.
  - `ellipsis_op` → `{:ellipsis_op, meta(), :...}`.
  - `ternary_op` → `{:ternary_op, meta(), op}`.
  - `assoc_op` → `{:assoc_op, meta(), :"=>"}`.
  - `at_op` → `{:at_op, meta(), :@}`.
  - `capture_op` → `{:capture_op, meta(), :&}`.
  - `capture_int` → `{:capture_int, meta(), :&}` followed by an `:int`.
  - `when_op` → `{:when_op, meta(), :when}`.
  - `in_op` → either `{:in_op, meta(), :in}` or
    `{:in_op, meta_span, :"not in", in_meta}`.

- Punctuation & delimiters:
  - `'.'` → `{:., meta()}`.
  - `','` → `{:",", meta()}`.
  - `';'` → `{:";", meta()}`.
  - `'('` → `{:"(", meta()}`; `')'` → `{:")", meta()}`.
  - `'['` / `']'` → `{:"[", meta()}` / `{:"]", meta()}`.
  - `'{'` / `'}'` → `{:"{", meta()}` / `{:"}", meta()}`.
  - `'<<'` / `'>>'` → `{:"<<", meta()}` / `{:">>", meta()}`.
  - `'%{}'` → `{:%{}, meta()}`.
  - `'%'` → `{:%, meta()}`.

- Control & reserved words:
  - `'true'` / `'false'` / `'nil'` → `{true, meta()}` / `{false, meta()}` /
    `{nil, meta()}`.
  - `'do'` / `'end'` / `'fn'` → `{:do, meta()}` / `{:end, meta()}` /
    `{:fn, meta()}`.
  - `block_identifier` → `{:block_identifier, meta(), atom}`.

- Structural: `eol` → `{:eol, meta()}`.

### 2.3. Excluding `:error_token`

`ALL_TOKENS.md` includes `{:error_token, meta, %Toxic.Error{}}` which by
construction represents **invalid** code and is only emitted in tolerant mode.
Since this property is about generating **valid programs**, we will **not**
include `:error_token` in the *positive* token grammar generator.

To still cover this token kind, we can add a **separate negative property** that
intentionally builds malformed token sequences (e.g. missing delimiters,
invalid escapes) and asserts that Toxic emits an error token and still
recovers; that property is out of scope for the initial phase of this design
but should be tracked as follow-up work.

---

## 3. Generator Infrastructure and Budgets

### 3.1. Nonterminal-based API

We introduce a new module, tentatively:

```elixir
# lib/spitfire/property/token_grammar_generators.ex

defmodule Spitfire.Property.TokenGrammarGenerators do
  alias StreamData, as: SD

  @type token :: term()  # Toxic collapsed token shape
  @type tokens :: [token]

  @type phase :: 1..5

  @doc """
  Generate a list of tokens forming a full `grammar` nonterminal.

  Options:
    * :phase       – grammar subset (default: highest implemented phase)
    * :max_tokens  – soft upper bound on total tokens
    * :max_depth   – soft upper bound on recursive depth
  """
  @spec grammar(opts :: keyword()) :: SD.t(tokens)
  def grammar(opts \\ []), do: ...
end
```

Internally, this module defines **one function per nonterminal** (or per group
of closely related nonterminals) from `elixir_parser.yrl` that we care about.
Each such function will be a **recursive generator** that takes `depth`/
`budget` as arguments, implemented as helper functions wrapped in
`StreamData.gen/1` combinators.

### 3.2. Depth and token budget handling

We must prevent runaway recursion and gigantic token lists.

We define the core recursive helper type:

```elixir
@type budget :: %{depth: non_neg_integer(), tokens_left: non_neg_integer()}

@spec gen_nonterminal(nonterminal, budget, phase) :: SD.gen({tokens, budget})
```

Rules:

- Each time we emit a terminal token, we decrement `tokens_left` by 1.
- Each recursive descent to another nonterminal decrements `depth`.
- When `tokens_left == 0` or `depth == 0`, generators must:
  - Prefer **leaf productions** (e.g. literals, identifiers) that do not recurse.
  - Or, if no leaf production is available for that nonterminal, fall back to a
    smaller nonterminal (e.g. `access_expr` → literal) or shrink by returning a
    minimal valid form (e.g. `grammar` with an empty `__block__`).

We encode this with `StreamData.sized/1` when convenient, but we keep an
explicit `budget` struct to be able to track **length** vs **structural depth**
separately.

### 3.3. Production choice and shrinking

For each nonterminal `N` we gather its production alternatives from
`elixir_parser.yrl` and encode them as weighted generators:

- Each production is a **branch** with an associated cost:
  - Number of terminals emitted (approximate).
  - Amount of recursion (number of sub-nonterminals).
  - Phase in which it becomes available.
- When sampling, we **filter** productions by:
  - `phase` – only productions allowed in the active phase.
  - `budget` – disallow branches whose estimated cost exceeds
    `tokens_left`/`depth`.

We can use `StreamData.frequency/1` with dynamically filtered branch lists.
Shrinking is provided by StreamData automatically, but we should:

- Prefer **simpler productions** (fewer tokens, less recursion) earlier in the
  frequency list, so shrinks naturally gravitate towards them.
- Keep the token constructors pure and deterministic to make shrinking stable.

---

## 4. Phase Design (Grammar Subsets)

We design the phases to **layer** complexity and to align with the explanation
in `elixir_parser.yrl` (matched / unmatched / no-parens, then containers, then
strings/sigils, etc.). Each phase builds on the previous one.

### 4.1. Phase 1 – Core matched expressions without parens-ambiguity

Focus: **`matched_expr`** and its `sub_matched_expr` and `access_expr`
substructure; no `unmatched_expr` or `no_parens_expr`, no blocks, no containers.

#### Included nonterminals

From the grammar:

- `grammar`, `expr_list`, `expr` restricted to:
  - `expr -> matched_expr`.
- `matched_expr` limited to:
  - `matched_expr -> matched_expr matched_op_expr`.
  - `matched_expr -> unary_op_eol matched_expr`.
  - `matched_expr -> at_op_eol matched_expr`.
  - `matched_expr -> capture_op_eol matched_expr`.
  - `matched_expr -> ellipsis_op matched_expr`.
  - `matched_expr -> sub_matched_expr`.
- `matched_op_expr` with all binary operators already present in the grammar
  (this is where we first exercise most operator tokens).
- `sub_matched_expr` limited to:
  - `sub_matched_expr -> access_expr`.
  - `sub_matched_expr -> range_op` (nullary range).
  - `sub_matched_expr -> ellipsis_op` (nullary ellipsis).
- `access_expr` limited to **scalar literals & simple identifiers**:
  - integer/float/char/literals: `int`, `flt`, `char`, `'true'`, `'false'`, `'nil'`,
    `atom`, `atom_quoted`, `atom_safe`, `atom_unsafe`.
  - names/aliases: `dot_alias` (built from `alias`), `dot_identifier` with
    simple `identifier` (no calls yet).

#### Token coverage in Phase 1

We cover:

- All numeric and char literals: `:int`, `:flt`, `:char`.
- Atom tokens: `:atom`, `:atom_quoted`, `:atom_safe`, `:atom_unsafe`.
- Reserved literals: `{true, ...}`, `{false, ...}`, `{nil, ...}`.
- Identifiers & aliases: `:identifier`, `:alias`, dot operators `{:., ...}`
  via `dot_identifier`/`dot_alias`.
- Unary operators: `:unary_op`, `:dual_op`, `:ternary_op` via `unary_op_eol`.
- All binary operator families via `matched_op_expr`:
  `:match_op`, `:dual_op`, `:mult_op`, `:power_op`, `:concat_op`, `:range_op`,
  `:ternary_op`, `:xor_op`, `:and_op`, `:or_op`, `:in_op`, `:in_match_op`,
  `:type_op`, `:when_op`, `:pipe_op`, `:comp_op`, `:rel_op`, `:arrow_op`.
- Structural `:eol` via `eoe` (end-of-expression) rules.

This already exercises a **large portion** of `ALL_TOKENS.md` while keeping the
syntax surface small.

### 4.2. Phase 2 – Unmatched expressions and do-blocks

Focus: introduce `unmatched_expr` and minimal `do_block`-based constructs while
still avoiding no-parens ambiguity.

#### Included nonterminals (in addition to Phase 1)

- `expr -> unmatched_expr`.
- `unmatched_expr` productions:
  - `unmatched_expr -> matched_expr unmatched_op_expr`.
  - `unmatched_expr -> unmatched_expr matched_op_expr`.
  - `unmatched_expr -> unmatched_expr unmatched_op_expr`.
  - `unmatched_expr -> unary_op_eol expr`.
  - `unmatched_expr -> at_op_eol expr`.
  - `unmatched_expr -> capture_op_eol expr`.
  - `unmatched_expr -> ellipsis_op expr`.
  - `unmatched_expr -> block_expr`.
- `block_expr` limited to **paren calls with do-blocks** (no no-parens yet):
  - `block_expr -> dot_call_identifier call_args_parens do_block`.
  - `block_expr -> dot_call_identifier call_args_parens call_args_parens do_block`.
- Minimal `do_block` / `stab` / `stab_expr` subset that yields valid `fn`-like
  blocks, but we can initially restrict to the simplest forms:
  - `do_block -> do_eoe 'end'` (empty block).
  - `do_block -> do_eoe stab_eoe 'end'` with simple `stab_expr` → `expr`.
  - `stab -> [stab_expr]` and `stab_expr -> expr`.

We do **not** yet enable:

- `dot_do_identifier` forms (no bare `if ... do` yet).
- `call_args_no_parens_*` (no no-parens calls).

#### Additional token coverage

- `:fn` / `:do` / `:end` via `fn_eoe`, `do_eoe`, `do_block`.
- `:stab_op` via `stab_op_eol` and `stab_expr` when we enable more complex
  clause forms.
- `:block_identifier` via `block_eoe` and `block_item` once we enable full
  blocks.

### 4.3. Phase 3 – No-parens expressions (one, many, ambig)

Focus: enable `no_parens_expr` and its subtypes, including nested calls and
selected ambiguous cases, but still **without containers** or keyword lists.

#### Included nonterminals (new)

- `expr -> no_parens_expr`.
- `no_parens_expr` productions:
  - `no_parens_expr -> matched_expr no_parens_op_expr`.
  - `no_parens_expr -> unary_op_eol no_parens_expr`.
  - `no_parens_expr -> at_op_eol no_parens_expr`.
  - `no_parens_expr -> capture_op_eol no_parens_expr`.
  - `no_parens_expr -> ellipsis_op no_parens_expr`.
  - `no_parens_expr -> no_parens_one_ambig_expr`.
  - `no_parens_expr -> no_parens_many_expr`.
- No-parens call heads:
  - `no_parens_one_expr`, `no_parens_zero_expr`, `no_parens_one_ambig_expr`,
    `no_parens_many_expr` with `dot_op_identifier` / `dot_identifier`.
- No-parens args subset:
  - `call_args_no_parens_expr`, `call_args_no_parens_comma_expr`,
    `call_args_no_parens_one`, `call_args_no_parens_ambig`,
    `call_args_no_parens_many`, `call_args_no_parens_many_strict`.
- For Phase 3 we can **initially disable** keyword-related variants
  (`call_args_no_parens_kw*`) to delay keyword complexity to Phase 4.

We also enable more `block_expr` forms that combine no-parens calls with
`do_block` in a **controlled** way; we must honor the grammar’s constraints to
avoid invalid nested do-block calls.

#### Additional token coverage

- `:do_identifier` via `dot_do_identifier` as we start to generate constructs
  like `if expr do ... end` and `case expr do ... end`.
- `:op_identifier` via `dot_op_identifier` in no-parens call heads.

We must be careful to **respect the grammar’s restrictions* on nested no-parens
calls and do-blocks (see the comments in `elixir_parser.yrl`). The generator
should:

- Avoid constructing invalid compositions like `foo a, bar b, c` unless wrapped
  in parentheses.
- Avoid nested `do` blocks without parentheses around inner ones.

We can encode these constraints by:

- Tracking the **context** (e.g. within a do-block argument) in the budget
  struct.
- Having dedicated variants of nonterminal generators for “do-safe” contexts.

### 4.4. Phase 4 – Containers, keyword lists and access

Focus: add **containers** (lists, tuples, maps, bitstrings), **keyword lists**,
**access syntax** (`value[...]`), and full `block_list` constructs.

#### Included nonterminals (new)

- Containers:
  - `list`, `list_args`, `container_expr`, `container_args_base`,
    `container_args`.
  - `tuple`.
  - `bitstring` and `open_bit`/`close_bit`.
  - `map`, `map_op`, `map_args`, `map_base_expr`, `map_close`, `map_args`,
    `assoc`, `assoc_base`, `assoc_expr`, `assoc_update`, `assoc_update_kw`.
- Keyword lists:
  - `kw_eol`, `kw_base`, `kw_call`, `kw_data`.
  - `call_args_no_parens_kw_expr`, `call_args_no_parens_kw`.
- Access and bracket forms:
  - `bracket_arg`, `bracket_expr`, `bracket_at_expr`.
- Full `container_expr` usage inside containers and lists.

#### Additional token coverage

- `:kw_identifier`, `:kw_identifier_safe`, `:kw_identifier_unsafe`.
- `%{` map opener `%{}` (`:%{}`) and `%` struct prefix (`:%, meta`).
- Bitstring delimiters `:<<`, `:>>`.
- `:assoc_op` (`=>`).
- `:pipe_op` in map update (`|>` in `%{struct | key: value}`).

We will also start exercising many of the **grammar error paths** indirectly
(through keywords and ambiguous container expressions), but since we only keep
programs accepted by the oracle, we restrict productions to those that produce
valid code (i.e. we avoid the explicit error/warning productions like
`error_no_parens_container_strict/1`).

### 4.5. Phase 5 – Strings, heredocs, sigils, interpolation and quoted identifiers

Focus: exercise all remaining token categories from `ALL_TOKENS.md`, primarily
string-like and interpolation-related tokens.

#### New generator layer for interpolation

We treat interpolation as a **secondary grammar**:

- For any interpolated part (e.g. in `bin_string`, `list_string`, heredocs,
  sigils, quoted atoms/keywords/identifiers) we need to generate **nested
  token lists** which themselves form valid `grammar` or `expr` sequences.
- `ALL_TOKENS.md` describes interpolation parts as `interpol_part` structures:
  `{start_meta, end_meta, [token]}`.
- For the property we can simplify metadata and focus on the **inner token list
  being valid** according to a reduced grammar (e.g. allow only `expr` sequences
  with a small `depth` and `max_tokens` budget).

We implement a helper:

```elixir
@spec interpolated_tokens(budget, phase) :: SD.gen(interpol_part)
```

which reuses the same nonterminal generators with a much smaller depth/budget.

#### Included constructs

- Collapsed strings:
  - `bin_string`, `list_string` with `parts :: [binary | interpol_part]`.
- Heredocs:
  - `bin_heredoc`, `list_heredoc`.
- Sigils:
  - `sigil` with full range of `sigil_atom`, `parts`, `modifiers`, `indent`.
- Quoted atoms and keywords:
  - `atom_quoted`, `atom_safe`, `atom_unsafe`, `kw_identifier_safe`,
    `kw_identifier_unsafe`.
- Quoted identifiers:
  - Collapsed `identifier`/`paren_identifier`/`bracket_identifier`/
    `do_identifier`/`op_identifier` that came from quoted forms (metadata only
    differs).

#### Remaining token coverage from `ALL_TOKENS.md`

- Linear-only tokens like `:bin_string_start`, `:begin_interpolation`, etc. are
  **implicitly covered** by virtue of `Toxic.to_string/1` being able to render
  and re-tokenize our collapsed tokens. We do not generate these directly.
- We exercise the sigil modifiers, heredoc delimiters, and the various
  interpolation kinds (`:string`, `:charlist`, `:atom_safe`, etc.).

At the end of Phase 5 every non-error token shape in `ALL_TOKENS.md` is
reachable in some production.

---

## 5. Properties to Check

### 5.1. Core positive property: oracle vs Spitfire on token-generated programs

We add a new property (initially `@tag :skip`) to `test/spitfire_property_test.exs`:

```elixir
@tag :skip
@property_timeout 120_000
property "parses oracle-accepted programs from token grammar" do
  oracle_opts = [columns: true, token_metadata: true, emit_warnings: false, existing_atoms_only: true]
  parser_opts = [tokenizer: :toxic, columns: true, token_metadata: true, existing_atoms_only: true]

  check all tokens <- TokenGrammarGenerators.grammar(phase: phase(), max_tokens: 80, max_depth: 10),
            max_runs: 1500,
            max_size: 5 do
    code = Toxic.to_string(tokens)

    case Code.string_to_quoted(code, oracle_opts) do
      {:ok, oracle_ast} ->
        assert {:ok, spitfire_ast} = Spitfire.parse(code, parser_opts)
        assert normalize_ast(spitfire_ast) == normalize_ast(oracle_ast)
        assert_no_toxic_errors(code)
        assert_no_synthetic_tokens(code)

      {:error, _reason} ->
        # If the oracle rejects the code, we ignore the example.
        :ok
    end
  end
end
```

Notes:

- `phase()` can come from an environment variable or an ExUnit tag
  (`@tag token_phase: 3`) to allow running different subsets.
- We reuse `assert_no_toxic_errors/1` and `assert_no_synthetic_tokens/1` from
  the existing test.

### 5.2. Optional property: token round-trip via Toxic

Once the core property is stable, we can strengthen it with a token
round-trip check:

```elixir
property "token grammar round-trips through Toxic" do
  check all tokens <- TokenGrammarGenerators.grammar(phase: phase(), max_tokens: 80, max_depth: 10) do
    code = Toxic.to_string(tokens)

    tokens2 =
      code
      |> Toxic.new(1, 1,
        error_mode: :tolerant,
        insert_structural_closers: true,
        existing_atoms_only: true
      )
      |> TokenIntrospection.collect_tokens()
      |> Toxic.Legacy.collapse_linear_ranges()
      |> Toxic.Legacy.ranges_to_legacy()

    # Compare sequences of token kinds and essential payloads
    assert normalize_tokens(tokens2) == normalize_tokens(tokens)
  end
end
```

`normalize_tokens/1` should intentionally drop metadata differences and accept
inescapable variations, for example:

- `:eol` counts may differ as long as the layout-equivalent program is
  produced.
- Some operator tokens may be represented with combined forms (e.g. `not in`).

### 5.3. Future property: negative tests with `:error_token`

As mentioned earlier, we plan a separate property to explicitly generate
**malformed** token sequences that should trigger `{:error_token, ...}` in
Toxic and verify that:

- The error domain, code and spans are reasonable.
- Synthetic structural closers (e.g. `end_interpolation`, heredoc ends) are
  injected as expected.

This property will use a **different generator** that violates the grammar,
not the one described in this document.

---

## 6. Implementation Plan

### 6.1. Modules and structure

1. **New generators module**:
   - `lib/spitfire/property/token_grammar_generators.ex` – implements
     `grammar/1` and per-nonterminal generators.
   - Optionally, small helper modules for token construction and metadata.
2. **Test integration**:
   - Extend `test/spitfire_property_test.exs` with the new token-based
     properties, initially tagged with `@tag :skip`.
   - Allow selecting `phase` via `@tag token_phase: N` and/or
     `MIX_ENV`/env vars (e.g. `TOKEN_PHASE=1 mix test --only token_phase:1`).

### 6.2. Incremental implementation by phase

1. **Phase 1**:
   - Implement scalar and identifier token generators.
   - Implement `matched_expr`, `sub_matched_expr`, `access_expr` subset.
   - Wire top-level `grammar` generator producing one or more expressions.
   - Add core property and run locally with low `max_tokens` and `max_runs`.
2. **Phase 2**:
   - Implement `unmatched_expr`, `block_expr`, minimal `do_block` and `stab`.
   - Ensure that do-block constructs produce code accepted by the oracle.
3. **Phase 3**:
   - Implement no-parens calls (`no_parens_expr`, `call_args_no_parens_*`).
   - Add context tracking for do-block safety to avoid invalid nested calls.
4. **Phase 4**:
   - Implement containers (lists, tuples, bitstrings, maps, assoc/assoc_update).
   - Implement keyword list grammar and integrate into both parens and
     no-parens call args.
5. **Phase 5**:
   - Implement string/heredoc/sigil/quoted atom/keyword/identifier generators
     with interpolation support.
   - Add optional round-trip property once stable.

We can gate each phase behind an ExUnit tag and gradually unskip them in CI as
stability and performance allow.

### 6.3. Performance and flakiness considerations

- Keep `max_tokens` relatively small (e.g. 40–80) in CI, with larger budgets for
  local fuzzing.
- Prefer expressions and containers with **few children** in generator weights.
- Avoid generating deeply nested interpolation inside already nested
  expressions, except under dedicated stress runs.
- Carefully design `normalize_tokens/1` so that cosmetic layout differences do
  not cause spurious failures.

---

## 7. Open Questions / Decisions

1. **Exact token shapes for `Toxic.to_string/1`**: confirm whether it expects
   legacy metas (`{line, col, extra}`) or ranged metas; the design assumes we
   can use simplified metas (e.g. zeros) without affecting the rendered source.
2. **Phase exposure**: expose phases only via tags/env vars, or also as runtime
   options inside `TokenGrammarGenerators.grammar/1` and CLI flags?
3. **AST normalization differences**: some sigils or quoted atoms may be
   processed differently by `Code.string_to_quoted/2` vs Spitfire; we may need
   dedicated normalization for those before comparing ASTs.
4. **Coverage measurement**: consider adding a small utility (in tests only)
   that records which Toxic token kinds were actually seen across runs, to
   validate that all intended tokens are being exercised by the generators.

This design provides a phased, grammar-driven token generator that can be used
for robust property tests, gradually extending from simple matched expressions
through no-parens and containers all the way to complex string and sigil
constructs while remaining controllable via depth/length budgets and phase
selection.