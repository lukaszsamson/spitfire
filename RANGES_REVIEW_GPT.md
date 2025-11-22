# Spitfire Ranges Review (GPT)

This review covers the `RANGES_PLAN_V3.md` design, the implementation in
`lib/spitfire.ex`, and the tests in `test/spitfire_ranges_test.exs`. It focuses
on coverage of the plan, correctness of the implementation, test adequacy, and
follow‑up work for correctness, code quality, and maintainability.

---

## 1. High‑Level Assessment

- The implementation generally follows `RANGES_PLAN_V3.md` very closely:
  - `token_range/1`, position helpers, `meta_range/1`, `put_meta_range/2`,
    `merge_ranges/1`, `ast_range/1`, and `arg_range/1` are present and used.
  - Parser state is extended with `last_span`, and root ranges are attached in
    `attach_root_range/2` only in Toxic mode.
  - Literals, containers, operators, calls, blocks, and interpolations
    consistently derive ranges from Toxic tokens.
  - Legacy (`tokenizer: :elixir`) behavior is preserved: no `:range` is
    attached in that mode.
- Tests in `SpitfireRangesTest` are extensive and do real work:
  - They verify literal encoder ranges at the token and container level.
  - They cover a wide variety of operators, containers, calls, blocks, and
    interpolations, including malformed inputs.
  - They introduce a structural invariant checker that enforces parent
    containment and sibling non‑overlap for all nodes that have ranges.
- The main correctness risks are in less‑used constructs and special cases
  rather than in the core architecture. Some forms are not explicitly tested,
  and a few implementation details diverge from the “no approximation” spirit
  of the V3 plan.

Overall: the ranges feature is in good shape and looks usable for editor
tooling, but there are some worthwhile follow‑ups to tighten guarantees and
improve clarity.

---

## 2. Implementation vs. V3 Plan

### 2.1 Helpers and Range Model

**What’s implemented**

- `token_range/1`:
  - Handles Toxic ranged metas for 2‑, 3‑, and 4‑tuple shapes:
    - `defp token_range({_, {{sl, sc}, {el, ec}, _extra}}), do: {{sl, sc}, {el, ec}}`
    - `defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _value}), do: {{sl, sc}, {el, ec}}`
    - `defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _, _}), do: {{sl, sc}, {el, ec}}`
  - Returns `nil` for legacy tokens (`{_, {line, col, extra}}`…) and for
    synthetic/fake tokens (`{:fake_closing_* , _}`).
- Position helpers `pos_leq?/2`, `pos_geq?/2`, `pos_min/2`, `pos_max/2` are
  implemented exactly as described.
- `meta_range/1` and `ast_range/1`:
  - `meta_range/1` extracts `{:range, {{sl, sc}, {el, ec}}}` from meta.
  - `ast_range/1` reads `meta_range/1` from `{_, meta, _}` nodes (and `nil`
    otherwise).
- `merge_ranges/1`:
  - Filters out `nil` entries and then reduces by `pos_min/2` and `pos_max/2`,
    exactly matching “union of spans”.
- `arg_range/1`:
  - Recursively handles lists, 2‑tuples (e.g., map key/value pairs), and
    generic ASTs via `ast_range/1`. This is a useful generalization that wasn’t
    spelled out in the plan but supports containers, maps, and structs cleanly.
- `put_meta_range/2`:
  - No‑ops on `nil`.
  - When `Application.get_env(:spitfire, :strip_ranges, false)` is `true`, it
    suppresses the `:range` key entirely; otherwise it adds/replaces `:range`.

**Comments**

- The representation matches the plan: `{:range, {{line, col}, {line, col}}}`.
- The app env guard in `put_meta_range/2`, combined with the `strip_ranges`
  behavior in tests, is a practical extension to the plan:
  - In production, `strip_ranges` defaults to `false`, so Toxic mode exposes
    ranges by default.
  - In tests, `test_helper.exs` sets `strip_ranges: true`, and
    `SpitfireRangesTest` opt‑in disables it per test module, isolating range
    behavior from older parity tests.
- The plan’s “no `:range` in legacy mode” is enforced by `token_range/1`
  returning `nil` for non‑Toxic metas and by `attach_root_range/2` being gated
  on `backend: Toxic`. Even if `strip_ranges` is `false`, non‑Toxic ASTs never
  get a range.

**Potential issues**

- Relying on app env for `put_meta_range/2` and also calling
  `strip_ranges_if_needed/2` at the end is slightly redundant:
  - When `strip_ranges` is `true`, you never attach ranges inside the parser,
    and then you also walk the AST to strip a key that doesn’t exist.
  - This is harmless but worth documenting to avoid confusion.

**Follow‑ups**

- Document `:strip_ranges` semantics in `PARSER.md` or README:
  - Explain that it is a testing / compatibility knob, not a tokenizer mode.
- Optionally simplify `strip_ranges_if_needed/2` to rely solely on
  `put_meta_range/2` + env, or vice‑versa. Right now both exist; choosing one
  canonical mechanism will reduce mental overhead.

### 2.2 Parser State and Root Range

**What’s implemented**

- `new/2` initializes:

  ```elixir
  %{
    stream: Spitfire.TokenStream.new(code, line, column, opts),
    start_line: line,
    start_column: column,
    fuel: 150,
    current_token: nil,
    peek_token: nil,
    nesting: 0,
    literal_encoder: Keyword.get(opts, :literal_encoder),
    interpolation_depth: 0,
    saved_nesting_stack: [],
    errors: [],
    last_span: nil
  }
  ```

- `next_token/1`:
  - On the first call (no current/peek), it fills `peek_token` but does not set
    `current_token` or `last_span` (as desired).
  - On subsequent calls, it:

    ```elixir
    last_span =
      case token_range(parser.current_token) do
        {{_, _}, {_, _}} = span -> span
        _ -> parser.last_span
      end

    current = parser.peek_token
    {tok, stream1} = Spitfire.TokenStream.next(stream)

    %{parser | current_token: current, peek_token: tok, last_span: last_span, ...}
    ```

  - Since `token_range/1` is `nil` for fake tokens, they do not affect
    `last_span`. For Toxic tokens (including synthesised closers), we always
    record a real span.

- `attach_root_range/2` (Toxic only):

  ```elixir
  root_start = {parser.start_line, parser.start_column}

  root_end =
    case parser.last_span do
      {{_, _}, {el, ec}} -> {el, ec}
      _ -> root_start
    end

  case ast do
    {form, meta, args} ->
      range = merge_ranges([ast_range(ast), {root_start, root_end}])
      {form, put_meta_range(meta, range), args}
    other ->
      other
  end
  ```

**Comments**

- This matches the plan’s root coverage guarantee: root starts at the parser
  start position (opts `:line`/`:column` or `{1,1}`) and ends at the end of the
  last real token seen by Toxic (`last_span`).
- The root range is merged with the AST’s existing range from children, so the
  root never shrinks relative to its contents.
- `attach_root_range/2` is explicitly ignored for non‑Toxic backends, which is
  correct for the “legacy mode” promise.

**Potential issues**

- For empty programs in Toxic mode:
  - `parse_program/1` builds `{:__block__, meta, []}` with meta based on
    `start_line`/`start_column` but no range.
  - `last_span` remains `nil`.
  - `attach_root_range/2` merges `[nil, {root_start, root_start}]` and thus
    root range is `{root_start, root_start}`.
  - This is consistent with the plan; however, there is no explicit test for
    this case. It’s probably fine, but consider adding one simple test:
    `" "`, `""`, or comments‑only input in Toxic mode.

**Follow‑ups**

- Add an explicit test that parsing an entirely empty or comments‑only source
  in Toxic mode yields a root `:range` of `{start, start}` and still passes the
  invariants checker.

### 2.3 Literals and Leaf Nodes

**What’s implemented**

- `encode_literal/3` is centralized and matches the plan’s design:

  ```elixir
  defp encode_literal(parser, literal, range_override \\ nil)

  defp encode_literal(%{literal_encoder: encoder} = parser, literal, range_override)
       when is_function(encoder) do
    base_meta = current_meta(parser)
    range = range_override || token_range(parser.current_token)
    base_meta = put_meta_range(base_meta, range)
    meta = additional_meta(literal, parser) ++ base_meta
    ...
  end
  ```

  - `current_meta/1` remains start‑only (line/column), in line with the plan.
  - Ranges come exclusively from `token_range/1` or explicit overrides.
  - `additional_meta/2` provides delimiters, indentation, closing meta, etc.

- Literal parsers (int, float, atom, string, char, boolean, nil):
  - All call `encode_literal(parser, value)` or `encode_literal(parser, value, range_override)` so
    every literal that passes through the encoder gets a range in Toxic mode.
  - `parse_nil_literal/1` was updated to call `encode_literal(parser, nil)`, so
    `nil` matches the other primitives.

- Container literals and `literal_encoder` interplay:
  - `parse_list_literal/1`:
    - Captures `open_range` and, for each closing path, `close_range`.
    - Defines an `encode_list/4` closure that:
      - Computes container range via
        `merge_ranges([open_range, close_range, arg_range(values)])`.
      - Re‑binds `parser.current_token` to the original `open_token` before
        calling `encode_literal/3` so the encoder sees the correct start meta.
      - Attaches the container range via both `encode_literal` and a final
        `attach_range/2` for consistency.
  - `parse_tuple_literal/1`:
    - For 2‑tuples, it uses `encode_literal(pairs |> List.to_tuple(), container_range)`
      and `put_closing_meta/2`, aligning with the plan’s “2‑tuple literal path”.
    - For other tuple arities, it uses structural `:{}` AST with container
      ranges derived from open/close tokens and child ranges.
  - `parse_map_literal/1`, `parse_struct_literal/1`,
    `parse_bitstring/1`:
    - Similar pattern: compute `container_range` from open/close ranges and
      child ranges, attach via `put_meta_range/2` directly.

- Non‑literal leaf nodes:
  - `parse_lone_identifier/1`:

    ```elixir
    range = token_range(parser.current_token)
    meta =
      parser
      |> current_meta()
      |> push_delimiter(token_meta)
      |> put_meta_range(range)
    ```

  - `parse_alias/1`:
    - Attaches a range to each alias segment as it is consumed and stores
      `:last` meta for later.
    - The resulting `{:__aliases__, meta, parts}` node carries a range that
      spans the entire alias chain.
  - `parse_do_identifier/1`, `parse_lone_module_attr/1`, and
    `parse_ellipsis_op/1` all attach ranges in a similar leaf style.

**Notable omissions / divergence**

- `parse_atom/1` for `:atom_unsafe` (interpolated atoms) builds a
  `binary_to_atom` call with `meta = current_meta(parser)` but **never adds a
  `:range`**:

  ```elixir
  {{{:., meta, [:erlang, :binary_to_atom]}, [{:delimiter, ~S'"'} | meta],
    [{:<<>>, meta, args}, :utf8]}, parser}
  ```

  - This means the call node and inner binary literal lack ranges even in Toxic
    mode.
  - It does not break the invariants because the `assert_range_invariants/2`
    helper explicitly skips nodes without ranges, but it is inconsistent:
    - Non‑interpolated atoms have ranges via `encode_literal/3`.
    - Interpolated atom sugar uses a different structure with no ranges.

- For bracketless keyword lists (`parse_bracketless_kw_list/1`), keyword keys
  are parsed with `encode_literal(parser, token)` **without** the colon‑trimmed
  `range_override` that is used in `parse_kw_identifier/1`. As a result:
  - In `%{a: 1}`, the `:a` key gets a colon‑trimmed range (just `a`).
  - In `a: 1` (bracketless), the `:a` key range likely includes the colon.
  - This is a subtle inconsistency; invariants still hold, but tooling that
    cares about “identifier only” ranges may find this surprising.

**Follow‑ups**

1. **Add ranges for `:atom_unsafe` paths**
   - Update `parse_atom/1` for `:atom_unsafe` to use `put_meta_range/2` on
     `meta` with `token_range(parser.current_token)` (before advancing to
     interpolation tokens) and to propagate that range to the outermost node
     (`binary_to_atom` call or the final AST).
   - Add one or two tests under “Interpolation Ranges” that assert precise
     ranges for interpolated atoms, similar to string and sigil tests.

2. **Unify keyword key ranges**
   - For `parse_bracketless_kw_list/1`, mirror the colon‑trimming logic in
     `parse_kw_identifier/1` by:
     - Computing `range = token_range(parser.current_token)` and, when the
       start and end line match, shrinking the end column by one to exclude
       the colon.
     - Passing `range` as `range_override` to `encode_literal/3`.
   - Add a test case like:

     ```elixir
     code = "a: 1"
     {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())
     assert_received {:lit_meta, :a, meta}
     assert meta[:range] == {{1, 1}, {1, 2}}
     ```

   - This keeps keyword key semantics consistent across bracketed and
     bracketless contexts.

3. **Consider adding ranges to more internal leaves**
   - Some internal nodes (e.g. `Kernel.to_string/1` wrappers in interpolation,
     `binary_to_atom/2` machinery) intentionally lack ranges, which is allowed
     per the test helper’s comments.
   - If tooling would benefit from “everything has a range”, you could
     eventually attach ranges at those sites as well, but this is an optional
     enhancement, not a correctness bug.

### 2.4 Operators and Expressions

**What’s implemented**

- Prefix operators (`parse_prefix_expression/1`, `parse_prefix_lone_identifer/1`,
  `parse_capture_int/1`):
  - Capture `op_range = token_range(parser.current_token)` before consuming the
    operator.
  - Build AST `{token, meta, [rhs]}` and pass through `attach_op_range/2`, which
    merges `op_range` and operand ranges into the operator node range.

- Infix operators (`parse_infix_expression/2`):
  - Capture `op_range` and `meta` for the operator token.
  - Build AST `{token, meta, [lhs, rhs]}` and run it through
    `attach_op_range/2`.
  - Includes normalization for error cases on the RHS (replacing bad `rhs`
    blocks with synthetic identifiers or similar) before applying ranges.

- Range operators (`parse_range_expression/1` and `/2`):
  - `parse_range_expression/1` (prefix form) builds `{token, meta, []}` and
    attaches `op_range`.
  - `parse_range_expression/2` (binary and stepped ranges) handles:
    - `1..2` producing `{:.., meta, [lhs, rhs]}`.
    - `1..2//3` producing `{:..//, meta, [lhs, mid, rhs]}`.
  - Ranges are computed from `op_range` plus child ranges via
    `attach_op_range/2`.
  - Tests cover both simple `..` and stepped `..//` with explicit coordinates.

- Pipe operator (`parse_pipe_op/2`):
  - Uses `op_range` plus ranges of `lhs` and the argument list (wrapped
    structure) via `attach_op_range/2`.
  - Tests verify both contiguous and multi‑line pipes.

- Assoc operator (`parse_assoc_op/2`):
  - Builds a synthetic `{:assoc, assoc_meta, [key, value]}` node, attaches
    `op_range` there, and then inserts the resulting meta into the key node
    meta under `{:assoc, assoc_meta}`.
  - Tests explicitly assert the assoc meta range spans `key` through `value`
    (`%{1 => 2}` case).

- Comma expressions (`parse_comma/2`):
  - Wrap expression lists into `{:comma, [], [lhs | exprs]}` and attach
    `op_range`. This ensures comma expressions get ranges like other operators.

**Potential issues**

- `parse_range_expression/2` currently calls `attach_op_range/2` **twice**:

  ```elixir
  {ast, parser} =
    if peek_token(parser) == :ternary_op do
      ...
      {{:..//, meta, [lhs, rhs, rrhs]}, eat_eol(parser)}
      |> then(fn {ast, p} -> {attach_op_range(ast, op_range), p} end)
    else
      {{token, meta, [lhs, rhs]}, eat_eol(parser)}
      |> then(fn {ast, p} -> {attach_op_range(ast, op_range), p} end)
    end

  ast =
    ast
    |> attach_op_range(op_range)
  ```

  - Because `attach_op_range/2` overwrites `:range` each time with the union
    of the same operands, this appears to be benign (idempotent).
  - However, it is confusing and potentially fragile if `attach_op_range/2`
    logic changes later.

**Follow‑ups**

- Clean up `parse_range_expression/2` to call `attach_op_range/2` exactly once:

  ```elixir
  {ast, parser} =
    if peek_token(parser) == :ternary_op do
      ...
      {{:..//, meta, [lhs, rhs, rrhs]}, eat_eol(parser)}
    else
      {{token, meta, [lhs, rhs]}, eat_eol(parser)}
    end

  ast = attach_op_range(ast, op_range)
  ```

- Add a small regression test that ensures the range for a stepped range
  (`1..2//3`) is still computed correctly after this simplification.

### 2.5 Calls, Dots, Access, and Containers

**What’s implemented**

- Paren calls:
  - `parse_paren_identifier/1` and `parse_call_expression/2`:
    - Capture `callee_range` from the identifier or lhs.
    - Capture `open_range` and `close_range` for parentheses.
    - Use `attach_range/2` with `[callee_range, open_range, close_range | arg_ranges]`.
  - Tests check:
    - Simple calls (`foo(1, 2)`, `foo()`, `Mod.fun(1)`).
    - Calls with keyword arguments and nested containers.
    - Remote calls and nested calls (`foo(bar(baz()))`).

- No‑parens calls:
  - `parse_identifier/1` with `identifier` or `op_identifier`:
    - Uses `callee_range = token_range(parser.current_token)`.
    - Parses argument list, including trailing keyword list folding.
    - Attaches range via `attach_range/2` using callee and argument ranges.
  - Tests verify ranges for:
    - `foo 1`, `foo 1, 2, 3`.
    - No‑parens followed by do‑blocks (`if true do ... end`) via call + do block.

- Dot expressions:
  - `parse_dot_expression/2`:
    - Handles both normal identifiers and the more complex
      `quoted_identifier_start` path.
    - Computes `lhs_range` from `lhs`, `dot_range` from the dot token, and a
      `callee_range` for the right‑hand identifier (including its delimiters).
    - Builds a `{:., meta, [lhs, rhs]}` AST and attaches range spanning
      `lhs_range`, `dot_range`, and `callee_range`.
    - The subsequent call/no‑call handling reuses these ranges.
  - `parse_dot_call_expression/2`:
    - Handles `lhs.foo()` style calls:
      - Builds a callee AST `{:., meta, [lhs]}` with a range that includes the
        dot and parentheses.
      - Then wraps it in a call AST with its own range.
  - Tests cover:
    - `Foo.bar(1, 2, 3)`, `Foo.bar()`, `a.b.c.d()`.
    - Missing dot RHS (`foo.`) with error recovery while still ensuring ranges
      exist and invariants hold.

- Access expressions (`foo[... ]`):
  - `parse_access_expression/2`:
    - Captures `open_range` and `close_range` for `[` and `]`.
    - Handles both keyword lists and general expressions inside the brackets.
    - Uses `arg_range/1` for the bracket argument and constructs a call AST of
      the shape `{{:., meta, [Access, :get]}, meta, [lhs, rhs]}` with a range
      covering `lhs`, brackets, and argument.
  - Tests verify ranges for:
    - Simple access (`foo[a]`).
    - Chains (`foo[a][b][c]`).
    - Access with keyword lists and error cases (`foo[`, malformed).

- Containers were already covered in §2.3; they are also exercised indirectly
  in many of the call tests.

**Potential issues**

- The Access AST (`{{:., meta, [Access, :get]}, meta, [lhs, rhs]}`) uses the
  same `meta` for both the dot call and the outer call:
  - `attach_range/2` is called on the outer AST with `range`, so the outer
    meta definitely has `:range`.
  - The inner `{:., meta, [Access, :get]}` also receives a range.
  - This slightly duplicates range information but is consistent; tooling can
    use either node.

**Follow‑ups**

- Add one explicit test that inspects both the inner `{:., ...}` node and the
  outer `Access.get/2` call in a bracket access, to document and lock in this
  structure.

### 2.6 Blocks, Special Forms, and `__block__`

**What’s implemented**

- `build_block_nr/2`:
  - For a non‑empty list of expressions (not `:->` clauses), it returns
    `{:__block__, [], exprs}` and attaches a range derived from child ranges.
  - For a single expression, it returns that expression directly (no wrapper).
  - For `[]`:
    - If a `parser` is passed, meta is set to `[line: start_line, column: start_column]`
      but no range; `attach_root_range/2` later adds the root range.
    - If `parser` is `nil`, it returns `{:__block__, [], []}` with no range.
  - This matches the plan’s idea that empty blocks may be range‑less except at
    the root, where root range takes over.

- Grouped expressions (`parse_grouped_expression/1`):
  - Captures `open_range` for `(` and `close_range` for `)` for all the
    relevant branches (empty, single‑expr, and multi‑expr).
  - For the resulting AST:
    - Single expression: merges `[open_range, close_range, arg_range(expr)]`.
    - Block/multiple expressions: merges `[open_range, close_range | child_ranges]`.
  - Tests cover:
    - `(1 + 2)` with explicit operator ranges including parentheses.
    - Nested parens, empty parens, multi‑line grouped expressions.

- Do blocks (`parse_do_block/2`):
  - Captures `do_range` and `end_range` from Toxic tokens.
  - Wraps clause bodies via `build_block_nr/1`.
  - Constructs the final call AST with meta containing `:do` and `:end`
    metas and a `:range` equal to the union of:
    - Callee range.
    - `do_range` and `end_range`.
    - Ranges of clauses and any arguments.
  - Tests cover:
    - Simple `foo do :ok end`.
    - Multi‑line and nested `if` with `else`.
    - `case`, `cond`, `try/rescue`, `with`, `for` with do‑blocks.
    - Missing `end` error cases (still requiring a range).

- Anonymous functions (`parse_anon_function/1`):
  - Captures `fn_range` and `end_range`.
  - Collects clauses (`:->`) and wraps each body with `build_block_nr/1`.
  - Attaches a range to the `:fn` node spanning `fn_range`, `end_range`, and
    clause ranges.
  - Tests verify:
    - Single‑line and multi‑line `fn`.
    - Multiple clauses and nested `fn`s.
    - Error cases missing `end`.

**Potential issues**

- Individual `:->` clause nodes do not currently receive explicit ranges; they
  rely on child ranges only. This is permitted by the plan (ranges are not
  required on every intermediate node) and the invariants only apply when a
  `:range` is present. If tooling needs clause‑level ranges, this would be an
  area for enhancement, not a bug.

**Follow‑ups**

- Consider adding ranges to `:->` clauses:
  - When building/analyzing clauses, you can use `arg_range/1` on pattern and
    body, plus the `:->` token’s `op_range`, to set clause ranges.
  - Add tests that inspect `{:->, meta, [patterns, body]}` ranges in both
    `case` and `fn` contexts.

### 2.7 Interpolation

**What’s implemented**

- `scan_linearized/4` and `scan_loop/5` drive scanning for strings, heredocs,
  sigils, etc.
- When encountering `:begin_interpolation`:
  - Increments `interpolation_depth`.
  - Saves and resets `nesting`.
  - Records `open_meta = current_meta(parser)` and `open_range = token_range(parser.current_token)`.
  - Parses the embedded expression (or creates an empty block).
  - Eats EOLs and then expects `:end_interpolation`, using a `cond`:
    - If `current_token_type(parser) == :end_interpolation`, uses its meta and
      range and advances.
    - Else if `peek_token_type(parser) == :end_interpolation`, advances to it
      and uses its meta and range.
    - Else, records an error and uses `current_meta(parser)` and
      `token_range(parser.current_token)` as a fallback.
  - Restores `nesting` and depth.
  - Calls `build_interpolation_ast/6` with `expr`, `open_meta`, `end_meta`,
    `open_range`, `end_range`, and `kind`.
  - Stores the resulting AST wrapped as `{:interpolation, end_meta || open_meta, interp_ast}`.

- `build_interpolation_ast/6`:
  - Computes `interp_range = merge_ranges([open_range, end_range, ast_range(expr)])`.
  - For binary strings, charlists, atoms, and sigils, it builds a `:"::"`
    wrapper around a `Kernel.to_string/1` call and attaches `interp_range` to
    that outer wrapper.

- Literal AST for the entire string/sigil/heredoc is built with delimiters and
  its own range from the outer parser functions, so interpolations are
  strictly contained inside their literalm.

**Tests**

- Explicit tests assert:
  - Outer literal ranges for strings, charlists, atoms, sigils, and heredocs.
  - Interpolation wrapper ranges:
    - For simple `"\#{1} and \#{2}"`, both interpolations have precise,
      non‑overlapping ranges.
    - Empty interpolation still yields a non‑nil range.
    - Malformed interpolation (`"\#{1"`) still results in an AST with ranges
      and passing invariants.
- Invariants are run on all these ASTs.

**Potential issues**

- The fallback branch in `scan_loop/5` when no `:end_interpolation` is found:

  ```elixir
  true ->
    parser = put_error(parser, {current_meta(parser), "expected end of interpolation"})
    {current_meta(parser), token_range(parser.current_token), parser}
  ```

  - This uses whatever the current token is as the “closing” range, which is
    an approximation contrary to the plan’s “no approximation” principle.
  - However, the expectation is that in Toxic mode, missing `}` will be
    represented by a synthetic `:end_interpolation` token with a real
    (possibly zero‑width) range, so this branch should only be hit in
    unexpected situations (e.g., non‑Toxic or a backend bug).
  - The tests for malformed interpolation do not assert exact boundary
    coordinates, only that invariants hold and ranges exist.

**Follow‑ups**

- Clarify with Toxic’s guarantees:
  - If Toxic guarantees that all malformed interpolations still emit
    `:end_interpolation` tokens, this fallback branch might be unreachable in
    practice in Toxic mode.
  - Consider guarding the approximation with `backend != Toxic` or logging
    when it triggers in Toxic mode.
- Add at least one test that asserts the interpolation range uses Toxic’s
  closing token even for a missing `}` (if Toxic does synthesise it). If
  that’s not the case, decide whether to update Toxic or to relax the “no
  approximation” requirement for this edge case.

---

## 3. Test Suite Assessment

### 3.1 Do the Tests Prove Ranges Are Correct?

The tests in `test/spitfire_ranges_test.exs` are substantial and, in many
places, very precise:

- **Literal encoder tests**:
  - For basic literals, they assert exact ranges for both the literal encoder
    meta and the top‑level AST root (e.g., `123`, `1.5`, `:foo`, `"hello"`,
    `'hello'`, `true`, `false`, `nil`).
  - Container tests validate:
    - Element ranges (e.g., `1` and `23` in `[1, 23]`).
    - Container literal meta ranges (via encoder).
    - Container AST ranges (root).
  - They include multi‑line containers and containers with whitespace to
    confirm that ranges span delimiters and whitespace correctly.

- **Operators**:
  - Check explicit coordinates for:
    - Binary `+`, nested `+` chains.
    - Unary `-`.
    - Range operators `..` and `..//`.
    - Pipe operator `|>`, including multi‑line.
    - `not in` with nested `:in` and explicit start/column for `in`.
    - Boolean operators, comparisons, match operators, module attributes, and
      capture operators, plus line‑spanning tests.

- **Calls, dots, and access**:
  - Tests assert root ranges for:
    - Paren calls, no‑parens calls, dot calls, nested calls, remote calls with
      various arities, and keyword arguments.
    - Access chains and mixed container/call structures.
  - There are also negative tests (incomplete call, missing dot RHS,
    unclosed access bracket) that assert presence of ranges and invariants even
    under error recovery.

- **Blocks and special forms**:
  - `__block__` with multiple lines (explicit ranges for each child and the
    parent).
  - Grouped expressions with and without content, nested and multi‑line.
  - `if`, `case`, `cond`, `try/rescue`, `with`, `for` with `do` block,
    nested do‑blocks, and missing `end` cases.
  - Anonymous functions in various forms (single and multi‑clause, nested,
    multi‑line).

- **Interpolation**:
  - Precisely assert the outer literal ranges and inner interpolation wrapper
    ranges for:
    - Strings, charlists, atoms, sigils, and heredocs.
    - Multiple interpolations with non‑overlap.
    - Empty interpolations.
    - Complex expressions inside `\#{}`.

- **Invariants**:
  - `assert_range_invariants/2` walks the AST and enforces:
    - Parent containment: `parent_start <= child_start` and
      `child_end <= parent_end`.
    - Sibling non‑overlap: adjacent child ranges satisfy `e1 <= s2`.
  - It skips nodes without `:range`, as noted in comments, which is
    consistent with the plan.
  - It is run on:
    - Many “normal” expressions (simple and complex).
    - Vast numbers of nested containers, calls, blocks, and interpolations.
    - Malformed inputs in all of those categories.

Overall, the tests provide strong evidence that:

- Ranges are correctly derived from Toxic token spans for a wide range of
  syntax.
- Parent containment and sibling non‑overlap hold wherever `:range` is
  present.
- Root ranges generally span from the first token to logical EOF.

### 3.2 Gaps and Missing Cases

Even with this breadth, a few areas are either untested or only tested
indirectly:

1. **Ellipsis operator (`...`)**
   - `parse_ellipsis_op/1` adds a range for `{:..., meta, []}`, but there are
     no tests that exercise it.
   - This operator appears mainly in typespecs and anonymous function specs; a
     simple expression like `fn -> ... end` or `@spec foo(... -> term)` (if
     tokenized appropriately) would be a good target.

2. **Empty program / comments‑only inputs**
   - There is a root coverage test for `"1 + 2\n"` and for various non‑empty
     multi‑line code samples, but none for completely empty or comments‑only
     files in Toxic mode.
   - Given the root range logic, these should yield `{start, start}`, but it
     would be better to assert this explicitly.

3. **Clause‑level ranges**
   - As noted, `:->` clauses do not have explicit `:range` tests.
   - The invariants indirectly cover them only if they happen to get ranges in
     the future. At the moment, they mostly lack `:range`, so are skipped by
     the invariant checker.

4. **Unsafe atom paths**
   - There is an “atom interpolation range” test that asserts the overall
     atom range, but it does not inspect the internal `binary_to_atom` call
     tree, which currently lacks ranges on inner nodes.
   - If you decide to attach ranges to these internal nodes, you’ll need tests
     to validate them.

5. **Special forms not explicitly tested**
   - `receive` / `after` blocks, `try/after`, and `catch` clauses may not be
     explicitly covered.
   - They likely reuse the same do‑block machinery, so they’re probably fine,
     but targeted tests would give more confidence, especially around the
     placement of `:do`/`:end` ranges and clause boundaries.

### 3.3 Legacy Mode and Parity

- `test_helper.exs` defines:

  ```elixir
  defmacro lhs == rhs do
    ...
    lhs = Spitfire.TestHelpers.drop_ranges(unquote(lhs))
    rhs = Spitfire.TestHelpers.drop_ranges(unquote(rhs))
    assert lhs == rhs
  end
  ```

  and also a `parity_encoder/0` that strips `:range` from meta.

- `Application.put_env(:spitfire, :strip_ranges, true)` in `test_helper.exs`
  ensures that, by default, tests see no `:range` at all, even in Toxic mode.

- `SpitfireRangesTest` sets `strip_ranges: false` in its `setup`, re‑enabling
  ranges only for these tests.

This strategy achieves:

- Old parity tests (that compare ASTs to `Code.string_to_quoted/2`) do not
  need to be updated; they still see ASTs without `:range`.
- Range tests see full Toxic ranges without needing to special‑case equality.

This is a good design and seems to satisfy the plan’s compatibility goals.

---

## 4. Recommended Follow‑Up Work

Here is a consolidated list of follow‑up actions, roughly ordered by impact.

### 4.1 Correctness and Coverage

1. **Add ranges and tests for unsafe atom paths**
   - Update `parse_atom/1` for `:atom_unsafe` to attach a `:range` (most
     naturally on the outermost node and possibly the inner `{:<<>>}`).
   - Add tests that:
     - Use Toxic tokenizer and inspect both outer atom range and inner nodes.
     - Run `assert_range_invariants/1` to confirm containment and non‑overlap.

2. **Unify keyword key ranges across contexts**
   - Apply the colon‑trimming range override from `parse_kw_identifier/1` to
     `parse_bracketless_kw_list/1` so that `a: 1` and `%{a: 1}` have key
     ranges that cover only `a`.
   - Add tests for both bracketless and map contexts using the test literal
     encoder.

3. **Simplify `parse_range_expression/2` range assignment**
   - Remove the duplicate `attach_op_range/2` call and keep a single call after
     choosing between `{:.., ...}` and `{:..//, ...}`.
   - Add a regression test for `1..2//3` to ensure ranges remain as expected.

4. **Add tests for ellipsis (`...`)**
   - Construct a minimal example where `parse_ellipsis_op/1` is invoked (e.g.,
     function spec or typespec context) and assert that the resulting `{:..., meta, []}`
     has a range corresponding to the token span.

5. **Explicit tests for empty / comments‑only code**
   - In Toxic mode, add tests that:
     - Parse `""`, `" "`, and a comment‑only module, and assert root range is
       `{start, start}` or `{start, eof}` as appropriate.
     - Run `assert_range_invariants/1` to validate nothing breaks even with
       minimal ASTs.

6. **Optional: Add ranges to `:->` clauses and test them**
   - If clause‑level ranges are desirable, modify the clause builders to
     attach ranges via `attach_op_range/2` or a dedicated helper.
   - Add tests that inspect `{:->, meta, [patterns, body]}` ranges for `case`,
     `cond`, `try/rescue`, and `fn`.

### 4.2 Interpolation Edge Cases

7. **Clarify / tighten interpolation error handling**
   - Decide whether the “approximate” closing range in `scan_loop/5` should
     ever be used in Toxic mode.
   - If Toxic always emits `:end_interpolation`, consider:
     - Asserting this in code (or logging when the fallback branch is taken).
     - Adding a test that covers a known Toxic behavior for malformed
       interpolation (e.g., using a 0‑width closing token).
   - If Toxic sometimes cannot emit `:end_interpolation`, document that this is
     the one place where approximations occur and that invariants are still
     enforced.

### 4.3 Maintainability and Documentation

8. **Document `:strip_ranges` configuration**
   - In `PARSER.md` or the main README, explain:
     - How `:range` is attached only in Toxic mode.
     - How `Application.get_env(:spitfire, :strip_ranges, false)` and
       `:strip_ranges` parse options interact.
     - Recommended settings for production vs testing.

9. **Reduce duplication between `put_meta_range/2` and `strip_ranges/1`**
   - Either:
     - Keep `put_meta_range/2` as the sole gatekeeper (recommended), and make
       `strip_ranges/1` a no‑op helper kept only for backwards compatibility
       (or remove it if not needed), or
     - Stop checking the app env in `put_meta_range/2` and rely purely on
       `strip_ranges_if_needed/2` at the end.
   - Having two mechanisms is slightly confusing; choosing one improves
     maintainability.

10. **Small refactors for clarity**
    - In places where both container helpers and `attach_range/2` are used
      (e.g., list/tuple/bitstring/struct literals), consider extracting small
      helpers named along the lines of `container_range(open_range, close_range, values)`
      to reduce repeated `merge_ranges` patterns and make intent clearer.
    - The current code is correct but quite dense; factoring out a couple of
      small helpers would make the range logic easier to audit in future.

---

## 5. Conclusion

- The ranges implementation in `lib/spitfire.ex` largely realizes the goals of
  `RANGES_PLAN_V3.md`:
  - Precise, non‑overlapping ranges derived from Toxic’s ranged tokens.
  - Root coverage and invariants for both valid and invalid code.
  - Legacy (non‑Toxic) behavior preserved.
- The test suite in `test/spitfire_ranges_test.exs` is strong and gives a high
  degree of confidence in correctness across literals, containers, operators,
  calls, blocks, and interpolations, including many malformed inputs.
- Remaining work is mostly about:
  - Closing a few small coverage gaps (unsafe atoms, ellipsis, empty programs,
    some special forms).
  - Cleaning up minor implementation redundancies.
  - Documenting configuration knobs and a couple of edge‑case behaviors.

Addressing the follow‑ups above would make the ranges feature very robust and
easier to reason about for future contributors and tooling authors.

