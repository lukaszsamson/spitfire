# Spitfire Property Tests with Toxic — V3 Plan

This document revises `PROPERTY_TEST_V2.md` based on
`PROPERTY_TEST_V2_OPUS45.md` and earlier reviews.

- `PROPERTY_TEST_CODEX.md`
- `PROPERTY_TEST_GEMINI3.md`
- `PROPERTY_TEST_OPUS.md`
- `PROPERTY_TEST_SONNET.md`

The core strategy is unchanged:

- Generate **valid or almost‑valid** Elixir source strings from a constrained,
  grammar‑biased generator.
- Use `Code.string_to_quoted/2` as the **oracle**.
- Tokenize with **Toxic** and parse with **Spitfire** via `Spitfire.TokenStream`
  in `tokenizer: :toxic` mode.
- Compare **ASTs and metadata** (after normalization) and track **Toxic token
  coverage**, especially around linearized interpolation, heredocs, sigils, and
  quoted identifiers/atoms.

Progress trackers
-----------------

- **Phase 1 (done)**: Property scaffolding landed in tests with initial Toxic-mode generators, AST parity helper, and token coverage list. Core parity/coverage/acceptance properties exist (some tagged `:skip` for runtime tuning).
- **Phase 2 (in progress)**: Generators expanded to cover quoted atoms/identifiers, sigil modifiers, bitstrings, captures, fn blocks, map updates, and a phase-2 target token set added. Coverage seeds widened. Parity/coverage/acceptance properties present but currently skipped pending performance tuning.

---

## 1. Goals, Non‑Goals, and Scope

### 1.1 Primary Goals

- For generated programs `code` that `Code.string_to_quoted/2` accepts:
  - `Spitfire.parse(code, tokenizer: :toxic, ...)` succeeds (no crashes, no
    `Spitfire.NoFuelRemaining`).
  - After metadata normalization, Spitfire’s AST **matches** the oracle AST.
- Exercise **Toxic’s linearized token stream** as consumed by Spitfire:
  - Linearized strings, charlists, heredocs, sigils.
  - Quoted atoms and quoted identifiers (including keyword identifiers).
  - Block constructs, comprehensions, bitstrings, captures, quote/unquote.
- Keep property tests:
  - **Atom‑safe** (`existing_atoms_only: true`, finite atom pools).
  - **Fuel‑safe** (no fuel depletion on oracle‑accepted programs).
  - **Performant** for CI (tunable depth/run counts, tags).

### 1.2 Non‑Goals

- We do **not**:
  - Re‑implement the full Elixir grammar.
  - Assert internal details of Toxic’s recovery beyond its public tokens and
    documented invariants.
  - Force coverage of every possible token kind in the first iteration; instead
    we track a **curated target set** that we grow over time.

### 1.3 Scope and Test Modules

- Mode under test:
  - `Spitfire.TokenStream` with `backend: Toxic` (`tokenizer: :toxic`).
  - Spitfire’s linearized parsing entry points:
    - `parse_linearized_string/2`
    - `parse_linearized_heredoc/2`
    - `parse_linearized_sigil/1`
    - `parse_linearized_atom/2`
    - `scan_linearized/5` and `scan_linearized_identifier/1`
    - Quoted identifier handling in `parse_dot_expression/2`.

- Properties live in:
  - `test/spitfire/property_generators.exs` — generators.
  - `test/spitfire_property_test.exs` — core parity properties.
  - `test/spitfire_property_coverage_test.exs` — token coverage + acceptance.
  - `test/spitfire_property_error_test.exs` — optional error‑tolerance props.

---

## 2. Spitfire ↔ Toxic Integration Boundary

We treat the Toxic stream + Spitfire.TokenStream adapter as part of the SUT and
test against `Code.string_to_quoted/2`.

### 2.1 Token Shapes and Linearization (Summary)

Toxic uses ranged metadata:

```elixir
meta :: {{start_line, start_column}, {end_line, end_column}, extra}
```

and emits tokens such as:

- **Literals and identifiers**
  - `{:int, meta, chars}`
  - `{:flt, meta, chars}`
  - `{:char, meta, chars}`
  - `{:atom, meta, atom}`
  - `{:alias, meta, atom}`
  - `{:identifier, meta, atom}`
  - `{:paren_identifier, meta, atom}`
  - `{:bracket_identifier, meta, atom}`
  - `{:do_identifier, meta, atom}`
  - `{:op_identifier, meta, atom}`
  - `{:block_identifier, meta, atom}`
  - `{:kw_identifier, meta, atom}`

- **Linearized strings and charlists**
  - `{:bin_string_start, meta, ?\"}` / `{:bin_string_end, meta, ?\"}`
  - `{:list_string_start, meta, ?'}` / `{:list_string_end, meta, ?'}`
  - `{:string_fragment, meta, binary}`
  - `{:begin_interpolation, meta, kind}` / `{:end_interpolation, meta, kind}`

- **Linearized heredocs**
  - `{:bin_heredoc_start, meta, ~c\"\"\", nil}`
  - `{:bin_heredoc_end, meta, ~c\"\"\", indentation}`
  - `{:list_heredoc_start, meta, ~c''' , nil}`
  - `{:list_heredoc_end, meta, ~c''' , indentation}`

- **Sigils**
  - `{:sigil_start, meta, sigil_atom, delimiter}`
  - `{:sigil_end, meta, delimiter, indentation}`
  - `{:sigil_modifiers, meta, modifiers, nil}`

- **Quoted atoms**
  - `{:atom_safe_start, meta, delimiter}` / `{:atom_safe_end, meta, delimiter}`
  - `{:atom_unsafe_start, meta, delimiter}` / `{:atom_unsafe_end, meta, delimiter}`

- **Quoted identifiers**
  - `{:quoted_identifier_start, meta, delimiter}`
  - Ends:
    - `{:quoted_identifier_end, meta, delimiter}`
    - `{:quoted_paren_identifier_end, meta, delimiter}`
    - `{:quoted_bracket_identifier_end, meta, delimiter}`
    - `{:quoted_do_identifier_end, meta, delimiter}`
    - `{:quoted_op_identifier_end, meta, delimiter}`

- **Keyword identifier ends (linearized from strings)**
  - `{:kw_identifier_safe_end, meta, delimiter}`
  - `{:kw_identifier_unsafe_end, meta, delimiter}`

- **Operators**
  - `{:dual_op, meta, op}`, `{:mult_op, meta, op}`, `{:power_op, meta, op}`, …
  - `{:range_op, meta, op}`, `{:pipe_op, meta, op}`, `{:stab_op, meta, op}`,
    `{:when_op, meta, op}`, `{:in_op, meta, op}`, `{:in_match_op, meta, op}`,
    `{:type_op, meta, op}`, `{:assoc_op, meta, op}`, `{:capture_op, meta, op}`,
    `{:capture_int, meta, int}`, `{:ellipsis_op, meta, :...}`,
    `{:dot_call_op, meta, :.}`, etc.
  - Special “not in” shape:

    ```elixir
    {:in_op, meta, :"not in", in_meta}
    ```

- **Delimiters and structure**
  - Delimiters: `:"("`, `:")"`, `:"["`, `:"]"`, `:"{"`, `:"}"`, `:"<<", :">>"`.
  - `%`, `%{}`, `:fn`, `:do`, `:end`, `:eol`, `:",", :";", :".", :%{}, :%`.
  - Booleans/nil: `true`, `false`, `nil` as operators/atoms.

- **Errors and EOF**
  - `{:error_token, meta, %Toxic.Error{}}`
  - `:eof` (via `Toxic.next/1` / `Toxic.to_stream/1`).

Spitfire’s linearized helpers (`scan_linearized/5`, `parse_linearized_*`) only
depend on the **kinds** and ranged metas, not on the full internal `extra`.

### 2.2 TokenStream Adapter Behavior

`Spitfire.TokenStream.new/4` chooses backend based on `:tokenizer`:

- `:legacy` / `:elixir` → `Spitfire.LegacyTokenizer`.
- `:toxic` → `Toxic`, using (simplified):

  ```elixir
  Toxic.new(code, line, column,
    error_mode: :tolerant,
    insert_structural_closers: true,
    existing_atoms_only: opts[:existing_atoms_only] || false
  )
  ```

`Spitfire.TokenStream.next/1`:

- Delegates to `backend.next/1`.
- For Toxic, yields `{:ok, token, stream}`, `{:eof, stream}`, or
  `{:error, reason, stream}` which `Toxic.to_stream/1` turns into an enumerable
  that halts on error.

### 2.3 Integration Invariants for Oracle‑Accepted Programs

For generated `code` where the oracle returns `{:ok, _}`:

- **No `:error_token`**:
  - `Toxic.errors/1` must return `[]`.
  - A property test will assert that no `{:error_token, _, _}` is present in
    the token stream.

- **No synthetic structural tokens**:
  - Toxic’s tolerant mode may synthesize closers/openers on mismatches; these
    have **zero‑length spans** (`{sl, sc} == {el, ec}`).
  - For oracle‑accepted programs we expect **no** synthetic tokens.
  - A property test (see §8.3) asserts there are no non‑EOF tokens with
    zero‑length metas.

- **Balanced interpolation and containers**:
  - For valid code, the terminator stack is balanced and no synthetic closers
    are needed.

These checks live in `spitfire_property_coverage_test.exs` so failures clearly
distinguish “Toxic/TokenStream issue” from “Spitfire AST mismatch”.

### 2.4 Target Token Kind Set

We maintain a **curated** set of token kinds that generators should exercise at
least occasionally. This set is derived from:

- `lib/toxic/normal_tokenizer/*.ex` (core tokens).
- `lib/toxic/driver/*.ex` (linearization and heredocs/sigils).
- Spitfire’s parser case distinctions and Pratt precedence table.

Example `Spitfire.Property.TargetTokens` sketch:

```elixir
@target_token_kinds MapSet.new([
  # Literals
  :int, :flt, :char, :atom,

  # Identifiers
  :identifier, :paren_identifier, :bracket_identifier,
  :do_identifier, :op_identifier, :alias, :block_identifier,
  :kw_identifier,

  # Linearized strings/heredocs
  :bin_string_start, :bin_string_end,
  :list_string_start, :list_string_end,
  :string_fragment,
  :bin_heredoc_start, :bin_heredoc_end,
  :list_heredoc_start, :list_heredoc_end,

  # Interpolation
  :begin_interpolation, :end_interpolation,

  # Sigils
  :sigil_start, :sigil_end, :sigil_modifiers,

  # Quoted atoms
  :atom_safe_start, :atom_safe_end,
  :atom_unsafe_start, :atom_unsafe_end,

  # Quoted identifiers
  :quoted_identifier_start, :quoted_identifier_end,
  :quoted_paren_identifier_end, :quoted_bracket_identifier_end,
  :quoted_do_identifier_end, :quoted_op_identifier_end,

  # Keyword identifier ends
  :kw_identifier_safe_end, :kw_identifier_unsafe_end,

  # Operators
  :dual_op, :mult_op, :power_op, :concat_op, :range_op,
  :xor_op, :ternary_op, :and_op, :or_op, :comp_op, :rel_op,
  :arrow_op, :in_op, :in_match_op, :type_op, :pipe_op,
  :stab_op, :when_op, :match_op, :assoc_op, :capture_op,
  :capture_int, :at_op, :unary_op, :ellipsis_op, :dot_call_op,

  # Delimiters and structural
  :"(", :")", :"[", :"]", :"{", :"}", :"<<", :">>",
  :%{}, :%,
  :fn, :do, :end, :eol, :";", :",", :".",

  # EOF and special
  :eof
])
```

This is not the full Toxic token universe; it is the *subset* Spitfire cares
about for Toxic mode. We adjust this list over time as we add generator
coverage or parser branches.

### 2.5 Spitfire Linearized Parsing Entry Points

For Toxic mode, Spitfire dispatches on these token types in `parse_expression/6`:

```elixir
:bin_string_start      -> parse_linearized_string(parser, :binary)
:list_string_start     -> parse_linearized_string(parser, :charlist)
:bin_heredoc_start     -> parse_linearized_heredoc(parser, :binary)
:list_heredoc_start    -> parse_linearized_heredoc(parser, :charlist)
:sigil_start           -> parse_linearized_sigil(parser)
:atom_safe_start       -> parse_linearized_atom(parser, :safe)
:atom_unsafe_start     -> parse_linearized_atom(parser, :unsafe)
```

Additionally:

- `scan_linearized/5` consumes:
  - `:string_fragment`, `:begin_interpolation`, `:end_interpolation`, and the
    various end tokens (`:bin_string_end`, `:list_string_end`,
    `:bin_heredoc_end`, `:list_heredoc_end`, `:sigil_end`,
    `:kw_identifier_safe_end`, `:kw_identifier_unsafe_end`).
- `scan_linearized_identifier/1` consumes:
  - `:string_fragment`, `:begin_interpolation`, `:end_interpolation`,
    `:quoted_*_identifier_end` variants.

V3 explicitly targets all of these entry points in the generator design and
coverage tests.

---

## 3. Atom Table Safety and Identifier Pools

Same design as V2, but we call out that the pools must be **disjoint** where
syntax would otherwise mix roles (e.g. variable vs keyword name).

### 3.1 Identifier and Atom Pools

```elixir
@identifiers ~w(foo bar baz qux spam eggs alpha beta gamma delta)a
@aliases     ~w(Foo Bar Baz Qux Remote Mod State Schema Context Config Default)a
@atoms       ~w(ok error foo bar baz one two three alice bob)a
@kw_keys     ~w(label count opts config metadata)a

@operator_atoms ~w(+ - * / == != < > <= >= and or not when in |> <<< >>> &&& ||| ^^^)a
```

Guidelines:

- `@identifiers` and `@kw_keys` are intentionally disjoint.
- All pools use `~w(... )a` so atoms are created at compile time.
- Operator atoms are only used where syntax requires them as atoms (`[+: 1]`,
  `:"+"`, etc.).

### 3.2 `existing_atoms_only: true`

- Both oracle and Toxic/Spitfire paths use `existing_atoms_only: true`. See V2
  for details; unchanged here.
- In test `setup`, we can defensively touch all pool atoms to guarantee
  existence.

### 3.3 Atom Safety Invariant

Unchanged from V2: any attempt to create new atoms causes the oracle to reject
the program under `existing_atoms_only: true`, which we treat as a generator
bug or flag wiring bug.

---

## 4. Generator Design

Generators live in `Spitfire.Property.Generators` and are organized as:

- Base literals/identifiers.
- Context‑aware expression generators (`expr/3`, `pattern/3`, `guard/3`).
- Specialized generators for strings/heredocs/sigils/quoted
  atoms/identifiers/keyword identifiers.
- Quote/unquote generators.
- Edge‑case generators for ambiguous operator and interpolation patterns.
- Program/top‑level generators.

### 4.1 Depth Budgets and Distribution

We distinguish **three** depth dimensions:

- `expr_depth` — how deep expression trees can nest.
- `interp_depth` — maximum nesting of `#{...}` within strings/sigils/heredocs.
- `block_depth` — maximum nesting of `do ... end` / `fn ... end` / `try ... end`
  blocks.

Example defaults:

```elixir
@max_expr_depth 4
@max_interp_depth 2
@max_block_depth 3
```

Entry points:

```elixir
def expr(context, expr_depth, interp_depth \\ @max_interp_depth, block_depth \\ @max_block_depth)

def expr(_context, 0, _interp_depth, _block_depth),
  do: one_of([literal(), variable()])
```

- When we generate a **nested expression** (e.g. binary operator RHS), we
  decrement `expr_depth`.
- When we open a **do/end block** (`fn`, `case`, `with`, `try`, etc.), we
  decrement `block_depth` and disallow further blocks at 0.
- When we enter an **interpolation** (`"#{expr}"`), we decrement `interp_depth`
  and disallow further interpolation at 0 (but still allow non‑interpolating
  strings).

Distribution uses `StreamData.frequency/1` as in V2, but now takes all three
depths into account when choosing between simple and complex forms.

### 4.2 Base Generators

Unchanged in spirit from V2, but with clarified bounds and edge cases:

- Identifiers, aliases, ints, floats, chars, basic strings/charlists, atoms,
  with:
  - Bounded sizes.
  - Explicit escape and Unicode coverage.
  - Quoted operator atoms for map/keyword contexts.

### 4.3 Comments and Whitespace

Same as V2: `whitespace_or_comment/0` is injected between many syntactic items,
ensuring comment and whitespace handling does not disturb AST parity but does
exercise line/column tracking.

### 4.4 Context‑Aware Expressions

Same categories as V2:

- `expr(:expr, ...)` — general expressions.
- `expr(:pattern, ...)` — patterns (left sides of `=` and `<-`).
- `expr(:guard, ...)` — guard context (subset of expressions).

All the constructs from V2 remain:

- Binary operators with full precedence table (including `..//`).
- Control‑flow (`case`, `with`, `cond`, `if/unless`).
- `try/rescue/catch/after/else`, `receive ... after`.
- Comprehensions (`for`, `with` comprehension) with `<-`, `<<-`, filters, and
  options (`into`, `reduce`).
- Containers: lists, tuples, maps, structs, bitstrings with segment options.

### 4.5 Captures and Operator Identifiers

Same intent as V2, now explicitly tied to target tokens:

- Captures:
  - `&foo/1`, `&Mod.foo/2`.
  - `&+/2`, `&Kernel.++/2`, `&(&1 + 1)`.
  - Hit `:capture_op`, `:capture_int`, `:op_identifier`, `:.`, `:dot_call_op`.

- Quoted identifiers:
  - `D."foo"`, `D.'bar'`.
  - With calls/indices/blocks:
    - `D."foo"(1)`, `D."foo"[1]`, `D."foo" do ... end`.
  - Operator identifiers:
    - `D."+"(1, 2)`, `D."foo bar"(arg)`.
  - Drive all `:quoted_*_identifier_end` variants and the dot expression logic
    in Spitfire.

### 4.6 Interpolation, Heredocs, Sigils, Quoted Atoms/Keyword Identifiers

Same as V2 but with clearer separation of interpolation depth and new subsection
for keyword identifier linearization.

#### 4.6.1 Strings and Charlists

- `"foo"`, `"foo#{expr}bar"`, `"#{expr}"`, `"#{e1}foo#{e2}"`, etc.
- `'foo'`, `'foo#{expr}bar'`, etc.
- Interpolation respects `interp_depth`; when it hits 0 we only generate
  non‑interpolating strings.

#### 4.6.2 Heredocs

- Triple‑quoted strings and charlists, with and without interpolation, and with
  varying indentation to match Toxic’s heredoc rules.

#### 4.6.3 Sigils

- Lowercase (interpolating) and uppercase (non‑interpolating) sigils.
- Delimiter matrix and heredoc sigils.
- Modifiers and indentation.

#### 4.6.4 Quoted Atoms

- Safe and unsafe forms, with and without interpolation, as in V2.

#### 4.6.5 Keyword Identifier Linearization

V3/V4 make the keyword identifier flow explicit, since Spitfire relies on it in
`parse_linearized_string/2`:

- Example:

  ```elixir
  ["foo": 1]
  ```

  Token stream (simplified):

  ```elixir
  :"["
  {:bin_string_start, meta1, ?"}
  {:string_fragment, meta2, "foo"}
  {:kw_identifier_safe_end, meta3, ?"}
  # ... tokens for value 1 ...
  :"]"
  ```

- Interpolated key:

  ```elixir
  ["foo#{x}": 1]
  ```

  uses the same linearization machinery (start + fragments + `:kw_identifier_*_end`),
  but the **specific** `_end` token depends on `existing_atoms_only` rather than
  on the presence of interpolation.

- Charlist‑quoted key:

  ```elixir
  ['foo': 1]
  ```

  uses `:list_string_start`/`end` and a corresponding `:kw_identifier_*_end`
  marker.

**Note on token type selection:** The choice between `:kw_identifier_safe_end`
and `:kw_identifier_unsafe_end` is controlled by Toxic’s `existing_atoms_only`
option:

- With `existing_atoms_only: true` (the setting used in the core property
  tests), quoted keyword identifiers (`"foo":`, `'foo':`) end with
  `:kw_identifier_safe_end`.
- Without `existing_atoms_only: true`, the same syntax ends with
  `:kw_identifier_unsafe_end`.

Interpolation vs. non‑interpolation affects the **AST** (literal atom vs.
`binary_to_atom/2` call), but not which `_end` variant Toxic emits under a
given `existing_atoms_only` setting. The core properties therefore mainly
exercise `:kw_identifier_safe_end`; separate tests without
`existing_atoms_only: true` can be added if we want explicit coverage of
`:kw_identifier_unsafe_end`.

Generators ensure we hit:

- Plain keywords: `[foo: 1]`.
- Quoted safe: `["foo": 1]`, `['foo': 1]`.
- Quoted unsafe: `["foo#{x}": 1]`.
- All the same shapes in lists, maps, call arg lists, bitstring segments, etc.

Spitfire’s `parse_linearized_string/2` uses `:kw_identifier_safe_end` and
`:kw_identifier_unsafe_end` as alternative end tokens and builds the AST for
the keyword key accordingly (either literal atom or interpolated
`binary_to_atom/2` call).

### 4.7 Quote/Unquote Forms

V3 adds explicit generators for `quote` and `unquote` forms:

- Simple:

  ```elixir
  quote do: expr
  quote do
    expr1
    expr2
  end
  ```

- With options:

  ```elixir
  quote bind_quoted: [a: expr], location: :keep do
    body
  end
  ```

- Unquote:

  ```elixir
  unquote(expr)
  unquote_splicing(expr)
  ```

These hit:

- `:block_identifier` (`do` inside quote blocks).
- Keyword identifiers (`bind_quoted:`, `location:`).
- Special AST forms `{:quote, _, _}`, `{:unquote, _, _}`,
  `{:unquote_splicing, _, _}`.

### 4.8 Edge‑Case Generators

We introduce small, focused generators for known parser edge cases:

- **Operator spacing:**

  ```elixir
  foo +bar      # unary +bar
  foo+ bar      # binary +
  foo+bar       # binary +
  ```

- **Escaped interpolation and non‑interpolating sigils:**

  ```elixir
  "foo\#{bar}"   # literal '#{bar}'
  ~S"foo#{bar}"  # uppercase sigil, no interpolation
  ```

- **Operator atoms in containers:**

  ```elixir
  [+: 1]
  %{+: 1}
  ```

- **Nested stabs and anonymous functions:**

  ```elixir
  fn -> -> -> :ok end end end
  ```

- **Ranges with negative bounds and steps:**

  ```elixir
  -10..-1//2
  1..10//-1
  ```

These enrich coverage without significantly increasing generator complexity.

---

## 5. Program Generator and Top‑Level Forms

Same structure as V2, plus the new quote/unquote forms in the mix:

- Sequences of:
  - Expressions, defs (`def/defp`), modules, typespecs, structs, protocols,
    impls, `use/alias/import/require`, quotes.
- Joined by newlines and semicolons to exercise `:eol` and `:";"`.

---

## 6. Token Coverage and Acceptance Rate

### 6.1 Token Introspection Helpers

In V3 we avoid any confusion about APIs by using a helper that works with both
`Toxic.to_stream/1` and `Toxic.next/1`. One simple version:

```elixir
defmodule Spitfire.Property.TokenIntrospection do
  def collect_tokens(stream) do
    stream
    |> Toxic.to_stream()
    |> Enum.to_list()
  end

  def collect_types_and_ranges(code, opts \\ []) do
    stream = Toxic.new(code, 1, 1, opts)
    tokens = collect_tokens(stream)

    Enum.map(tokens, fn
      {kind, {{sl, sc}, {el, ec}, _extra}, _} -> {kind, {{sl, sc}, {el, ec}}}
      {kind, {{sl, sc}, {el, ec}, _extra}} -> {kind, {{sl, sc}, {el, ec}}}
      {kind, {{sl, sc}, {el, ec}, _extra}, _, _} -> {kind, {{sl, sc}, {el, ec}}}
      other -> {elem(other, 0), nil}
    end)
  end
end
```

If we ever want finer‑grained control, we can replace `collect_tokens/1` with
an explicit loop over `Toxic.next/1`.

### 6.2 Target Token Set

V3 keeps the explicit `@target_token_kinds` (see §2.4) in a dedicated module
and uses it directly in the coverage test.

### 6.3 Coverage Test and Frequency Check

Coverage property (from V2), plus an optional distribution sanity check:

```elixir
@tag :property_coverage
test "generators hit target Toxic tokens" do
  samples = 1..n_samples()

  covered =
    samples
    |> Enum.flat_map(fn _ ->
      code = Gen.program(max_depth: 3, max_forms: 5)
      Spitfire.Property.TokenIntrospection.collect_types_and_ranges(code)
    end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()

  missing = MapSet.difference(Spitfire.Property.TargetTokens.target(), covered)

  assert MapSet.size(missing) == 0,
         "Missing token kinds: #{inspect(MapSet.to_list(missing))}"
end
```

Optional frequency check:

```elixir
@min_token_frequency 3

test "target tokens appear with reasonable frequency" do
  samples = Enum.map(1..n_samples(), fn _ ->
    Gen.program(max_depth: 3, max_forms: 5)
  end)

  freqs =
    samples
    |> Enum.flat_map(&Spitfire.Property.TokenIntrospection.collect_types_and_ranges/1)
    |> Enum.map(&elem(&1, 0))
    |> Enum.frequencies()

  low =
    freqs
    |> Enum.filter(fn {kind, count} ->
      kind in Spitfire.Property.TargetTokens.target() and count < @min_token_frequency
    end)

  # For now just warn; we can tighten this to an assertion once generators
  # are tuned.
  if low != [] do
    IO.warn("Low-frequency tokens: #{inspect(low)}")
  end
end
```

### 6.4 Acceptance Rate Test

Same as V2: we assert that a large majority (e.g. ≥ 90%) of generated programs
are accepted by `Code.string_to_quoted/2`.

---

## 7. AST Parity Properties

V3 keeps the same normalization approach as V2, with `normalize_ast/1` dropping
`[:range, :delimiter, :closing, :indentation, :end_of_expression]` from metas.

The core parity property remains:

- Generate `code` with `Gen.program/2`.
- If oracle returns `{:ok, oracle_ast}`:
  - Call `Spitfire.parse/2` in Toxic mode.
  - Assert `normalize_ast(spitfire_ast) == normalize_ast(oracle_ast)`.
- If oracle returns `{:error, _}`, skip (acceptance‑rate test covers this).

Secondary invariants from V2 (no fuel depletion, range invariants, positional
sanity) are unchanged.

---

## 8. Error‑Tolerance and Integration Properties

### 8.1 No Crashes on Arbitrary UTF‑8

Same as V2: property over arbitrary UTF‑8 strings that asserts Spitfire does
not crash in Toxic mode.

### 8.2 Error Propagation from Toxic

Same as V2: property that for syntactically ill‑formed code, Toxic errors are
reflected in Spitfire’s result/error list.

### 8.3 No Synthetic Tokens for Oracle‑Accepted Programs

V3 promotes the synthetic‑token invariant into its own property:

```elixir
@tag :property_integration
property "oracle-accepted programs have no synthetic tokens" do
  opts = [columns: true, token_metadata: true, existing_atoms_only: true]

  check all code <- Gen.program(max_depth: 3, max_forms: 10) do
    case Code.string_to_quoted(code, opts) do
      {:ok, _} ->
        stream = Toxic.new(code, 1, 1, error_mode: :tolerant)
        tokens = Spitfire.Property.TokenIntrospection.collect_tokens(stream)

        synthetic =
          Enum.filter(tokens, fn
            {:eof, _} -> false
            {_kind, {{sl, sc}, {el, ec}, _extra}, _} -> sl == el and sc == ec
            {_kind, {{sl, sc}, {el, ec}, _extra}} -> sl == el and sc == ec
            _ -> false
          end)

        assert synthetic == [], "Synthetic tokens found: #{inspect(synthetic)}"

      {:error, _} ->
        :ok
    end
  end
end
```

This explicitly enforces the “no synthetic closers/openers” invariant for the
main generator in oracle‑accepted cases.

---

## 9. Shrinking, Debugging, and Regression Capture

Same strategy as V2:

- Allow StreamData to shrink `code`, guarded by oracle acceptance.
- On failure, log:
  - Failing code.
  - Oracle vs Spitfire ASTs (normalized).
  - Toxic tokens (types + ranges).
- Optionally write shrunk repros into `test/spitfire/regressions/` as regular
  `SpitfireToxicTest` cases.

---

## 10. Implementation Steps

V2’s step list stands, with one extra pre‑step:

0. **Sanity‑check Toxic API** against the version in `mix.lock`:
   - `Toxic.new/4`, `Toxic.next/1`, `Toxic.to_stream/1`, `Toxic.errors/1`.
   - Confirm token shapes for linearized strings/heredocs/sigils/atoms/quoted
     identifiers/keyword identifiers.

Then:

1. Add `:stream_data` as a test‑only dependency.
2. Implement `Spitfire.Property.Generators` with depth‑aware, context‑aware
   generators, including quote/unquote and edge‑case generators.
3. Implement property helpers (`normalize_ast`, token introspection, target
   token set, logging).
4. Implement core parity properties.
5. Implement coverage and acceptance‑rate tests, including optional frequency
   check.
6. Implement error‑tolerance and integration properties, including “no
   synthetic tokens” for oracle‑accepted programs.
7. Tune depth/run counts and generator distributions based on runtime and
   coverage feedback; convert interesting failures into targeted regressions.

With these adjustments, V3 addresses the remaining gaps from
`PROPERTY_TEST_V2_OPUS45.md` while keeping the design coherent and aligned with
Spitfire’s actual Toxic integration. It is ready to guide implementation of a
robust property‑testing suite for `tokenizer: :toxic` mode.
