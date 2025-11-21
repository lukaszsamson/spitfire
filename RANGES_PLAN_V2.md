# AST Range Metadata with Toxic — V2 Plan

This document revises `RANGES_PLAN.md` based on feedback from
`RANGES_PLAN_REVIEW_CLAUDE.md` and `RANGES_PLAN_REVIEW_G3.md`.

Goals are unchanged:
- Use **Toxic’s ranged token metadata** to attach precise, non‑overlapping ranges
  to Spitfire’s AST nodes in **Toxic mode**.
- Preserve **AST shape and meta** in **legacy mode** (no `:range` there).
- Ensure:
  - Parent ranges contain all children.
  - Sibling ranges do not overlap.
  - Root range spans the whole document.
  - Literals rendered via `literal_encoder` see range‑aware meta.

This V2 plan tightens the design around:
- Raw token span extraction vs. `current_meta/1`.
- Closing token range capture.
- Operator and interpolation ranges.
- Parser `last_span` tracking.
- Legacy‑vs‑Toxic separation.
- Phased rollout and performance.

---

## 1. Range Model & Invariants

### 1.1 Representation

- Attach a `:range` key to AST metadata in **Toxic mode only**:

  ```elixir
  {:range, {{start_line, start_col}, {end_line, end_col}}}
  ```

  where:
  - Coordinates are **1‑based** and follow Toxic.
  - We treat `range` as a **half‑open interval** `[start, end)`.
    - This is mostly conceptual; we only compare line/col pairs.

- Keep existing `:line` / `:column` entries as **start position only**.
- Do not remove or alter existing keys (`:closing`, `:newlines`, `:do`, `:end`,
  `:end_of_expression`, etc.). `:range` is **additive**.

### 1.2 Tree Invariants

With Toxic enabled (and for well‑formed code):

- **Parent containment**

  For node `N` with range `R(N)` and children `Ci`:

  - `start(R(N)) <= start(R(Ci))` for all `i`.
  - `end(R(Ci)) <= end(R(N))` for all `i`.

  Equality at boundaries is allowed (children may start or end exactly at parent edges).

- **Sibling non‑overlap**

  For siblings `Ci`, `Cj` with `i < j`:

  - `end(R(Ci)) <= start(R(Cj))`.

  Adjacent siblings may “touch” at boundaries; they must not overlap.

- **Root coverage**

  For the root AST returned by `Spitfire.parse/2`:

  - `start(R(root)) = {start_line, start_column}` (from opts, defaults `{1, 1}`).
  - `end(R(root))` equals the logical end‑of‑file position:
    - Prefer from the parser’s `last_span` (last real token), else
    - For empty inputs, equal to `{start_line, start_column}`.

- **Error code / recovery**

  - For malformed code, ranges are **best‑effort**:
    - We keep invariants where practical.
    - Synthetic tokens (e.g. `:fake_closing_bracket`) never directly determine ranges.

---

## 2. Low‑Level Helpers

All helpers live in `lib/spitfire.ex` near `current_meta/1` / `current_eoe/1`.
They **do not** alter existing behavior.

### 2.1 Token Range Extraction (`token_range/1`)

`current_meta/1` is intentionally lossy: it only returns `{line, column, ...}`
and already supports both legacy and Toxic metas. We must not overload it with
full‑span logic.

Add a new helper that inspects raw tokens:

```elixir
# Toxic ranged tokens, 2‑ and 3‑tuple variants:
defp token_range({_, {{sl, sc}, {el, ec}, _extra}}),
  do: {{sl, sc}, {el, ec}}

defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _value}),
  do: {{sl, sc}, {el, ec}}

# Some operators (e.g., :in_op) use 4‑tuple forms; mirror existing patterns if needed:
defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _, _}),
  do: {{sl, sc}, {el, ec}}

# Legacy tokens: do NOT emit a range — keep legacy mode free of :range.
defp token_range({_, {_, _, _}}), do: nil
defp token_range({_, {_, _, _}, _}), do: nil
defp token_range({_, {_, _, _}, _, _}), do: nil

defp token_range(_), do: nil
```

This guarantees:
- **Toxic mode**: we can derive ranges directly from tokens.
- **Legacy mode**: `token_range/1` returns `nil`, so we never attach `:range`.

### 2.2 Position and Range Utilities

Basic helpers on positions and ranges:

```elixir
defp pos_leq?({l1, c1}, {l2, c2}),
  do: l1 < l2 or (l1 == l2 and c1 <= c2)

defp pos_geq?({l1, c1}, {l2, c2}),
  do: l1 > l2 or (l1 == l2 and c1 >= c2)

defp pos_min({l1, c1} = p1, {l2, c2} = p2),
  do: if pos_leq?(p1, p2), do: p1, else: p2

defp pos_max({l1, c1} = p1, {l2, c2} = p2),
  do: if pos_geq?(p1, p2), do: p1, else: p2
```

Range helpers:

```elixir
defp meta_range(meta) do
  case Keyword.get(meta, :range) do
    {{_sl, _sc}, {_el, _ec}} = r -> r
    _ -> nil
  end
end

defp put_meta_range(meta, nil), do: meta

defp put_meta_range(meta, {{sl, sc}, {el, ec}} = range) do
  # Overwrite any existing :range; use Keyword.put for clarity.
  Keyword.put(meta, :range, range)
end

defp merge_ranges(ranges) do
  ranges
  |> Enum.filter(& &1)       # drop nils
  |> case do
    [] ->
      nil

    [single] ->
      single

    [first | rest] ->
      Enum.reduce(rest, first, fn {{sl2, sc2}, {el2, ec2}},
                                   {{sl1, sc1}, {el1, ec1}} ->
        {
          pos_min({sl1, sc1}, {sl2, sc2}),
          pos_max({el1, ec1}, {el2, ec2})
        }
      end)
  end
end
```

### 2.3 AST Range Accessor

Canonically read a node’s range:

```elixir
defp ast_range({_, meta, _}) when is_list(meta), do: meta_range(meta)
defp ast_range(_), do: nil
```

---

## 3. Literal & Leaf Ranges

This phase gives **literals and leaf nodes** ranges, especially for
`literal_encoder` usage.

### 3.1 `current_meta/1` Stays Start‑Only

`current_meta/1` already supports both legacy and Toxic meta shapes but always
returns only `[line: ..., column: ...]` (plus some extras). This is desirable:
- It is simple and stable.
- It matches the expectations of existing code.

We **do not** add `:range` to `current_meta/1`.

### 3.2 `encode_literal/2` Refactor

Current implementation uses:

```elixir
encode_literal(parser, literal, meta_from_call_site)
```

where `meta_from_call_site` is often a raw token meta (`{line, col, extra}`) or
a keyword list with `:line` and `:column`.

To incorporate ranges consistently, refactor to a single entry point that
derives meta from the parser:

```elixir
defp encode_literal(%{literal_encoder: encoder} = parser, literal)
     when is_function(encoder) do
  # Start with start-only meta from current_meta/1
  base_meta = current_meta(parser)

  # Add range if Toxic (token_range/1 returns nil in legacy mode)
  base_meta =
    case token_range(parser.current_token) do
      {{_sl, _sc}, {_el, _ec}} = r -> put_meta_range(base_meta, r)
      _ -> base_meta
    end

  meta = additional_meta(literal, parser) ++ base_meta

  case encoder.(literal, meta) do
    {:ok, ast} ->
      ast

    {:error, reason} ->
      Logger.error(reason)
      literal
  end
end

defp encode_literal(_parser, literal) do
  literal
end
```

Call sites that currently pass a `meta` argument will be updated to:
- Set `parser.current_token` appropriately (already true for literals), then
- Call `encode_literal(parser, literal)` with **no third argument**.

This centralizes the range logic and makes it easy to evolve later.

### 3.3 List / Tuple / Map Literal Ranges with `literal_encoder`

Functions like:
- `parse_list_literal/1`
- `parse_tuple_literal/1`
- `parse_map_literal/1`
- Struct / bitstring literal parsers

currently:
- Capture opening meta (`orig_meta`) from the opening token.
- Eventually see the closing token, and `additional_meta/2` collects `closing: closing_meta`.

We want containers rendered via `literal_encoder` to get a **container‑level
range** covering the whole literal, from opening delimiter to closing delimiter.

Plan:

1. When entering a container parser, capture the opening token span:

   ```elixir
   open_range = token_range(parser.current_token)
   open_meta  = current_meta(parser)  # for line/column & existing semantics
   ```

2. Keep passing `parser` into the inner parsing logic as today.

3. When we successfully detect the closing token (the real closing delimiter,
   not a fake one):
   - Before consuming it, capture its range:

     ```elixir
     close_range = token_range(parser.current_token)
     closing_meta = current_meta(parser)
     parser = next_token(parser)
     ```

   - Ensure `additional_meta/2` can see both:
     - `closing_meta` for `closing: ...`.
     - `close_range` if we decide to use it later.

4. When we finally call `encode_literal/2` for the container literal (e.g.,
   `encode_literal(parser, list_value)`):
   - `parser.current_token` will be positioned at or just after the closing
     token, so `token_range/1` may no longer point at the closing
     delimiter.
   - To avoid this coupling, the container parser should instead:
     - Compute the container’s range itself from `open_range` and
       the last child’s range or `close_range`.
     - Add `:range` to the container literal’s meta after the `literal_encoder`
       returns the AST.

Example for lists (`[1, 23]`):
- Literal encoder sees:
  - For `1` and `23`: ranges from their individual tokens.
  - For `[1, 23]`: we post‑attach `:range` on the outer list node to
    `{{1, 1}, {1, 8}}`, where `1,8` is the end of `]`.

### 3.4 Leaf Nodes Not Using `literal_encoder`

For leaf nodes like identifiers, aliases, atoms (when not encoded via
`literal_encoder`), booleans, etc.:

- After building their meta with `current_meta/1` and `push_delimiter/2`:
  - Compute `range = token_range(parser.current_token)`.
  - Attach it via `put_meta_range/2`.

Examples:
- `parse_lone_identifier/1`
- `parse_alias/1`
- `parse_boolean/1` etc.

These nodes then behave like literals from a range perspective.

---

## 4. Composite Nodes & Family‑Specific Rules

Once leaves/literals have ranges, composite nodes can derive their ranges from
children and boundary tokens.

### 4.1 Generic Attachment Helpers

For a generic AST `{form, meta, args}`:

```elixir
defp attach_range({form, meta, args}) do
  child_ranges = Enum.map(args, &ast_range/1)
  range = merge_ranges(child_ranges)
  {form, put_meta_range(meta, range), args}
end
```

For many cases (e.g. simple unary expressions), this is enough: we only need
child ranges.

When we must include delimiters or operator tokens, we pass additional ranges
explicitly.

### 4.2 Operators (Binary/Unary, Range, Pipe, etc.)

Functions:
- `parse_infix_expression/2`
- `parse_prefix_expression/1`
- `parse_range_expression/1` and `/2`
- `parse_pipe_op/2`
- Specialized operators (`parse_assoc_op/2`, etc.)

Pattern:

1. When we first see the operator token (current token is the operator):
   - Capture its span before advancing:

     ```elixir
     op_range = token_range(parser.current_token)
     op_meta  = current_meta(parser)
     ```

2. After computing `lhs` and `rhs` and building the AST:

   ```elixir
   ast = {op, op_meta, [lhs, rhs]}

   defp attach_op_range({op, meta, [lhs, rhs]} = ast, op_range) do
     child_ranges = [ast_range(lhs), op_range, ast_range(rhs)]
     range = merge_ranges(child_ranges)
     {op, put_meta_range(meta, range), [lhs, rhs]}
   end
   ```

3. For unary operators, omit `lhs` or `rhs` accordingly.

This ensures operators are included in the overall expression range:
e.g. `1 + 23` spans from `1` through `23`, including the `+`.

### 4.3 Calls and Dots

Functions:
- `parse_call_expression/2` (paren calls)
- `parse_identifier/1` when used as a call head (no‑parens calls)
- `parse_dot_expression/2` (remote calls)
- `parse_dot_call_expression/2` (dot‑call syntax)

Strategy:

1. Identify the **callee range**:
   - For a bare identifier/alias: `ast_range(callee)` or `token_range` from its
     defining token.
   - For `lhs.foo` style: combine `lhs` and dot token, etc., as needed.

2. For paren calls:
   - Capture `open_paren_range` when seeing `(` (via `token_range/1`).
   - Capture `close_paren_range` before consuming `)` (again via `token_range/1`).
   - Derive call range from:
     - `callee_range`
     - `arg_ranges`
     - `open_paren_range`, `close_paren_range`

3. For no‑parens calls (`foo 1, 2`):
   - Call range is from `callee_range.start` to `last_arg_range.end`.

4. After building call nodes `{callee, meta, args}` or `{{:., meta, [lhs]}, meta2, args}`:
   - Call a helper that merges all relevant ranges and attaches `:range`.

### 4.4 Containers (Lists, Tuples, Maps, Structs, Bitstrings)

For containers **not** handled by `literal_encoder` (e.g. when not using a
literal encoder, or for some struct/bitstring structures), apply the same
boundary‑based approach:

1. Capture opening token span at entry.
2. Capture closing token span just before consumption.
3. Compute range from:
   - Opening span,
   - All element ranges,
   - Closing span.

When a container is passed to `literal_encoder`, we prefer to:
- Let `literal_encoder` produce the literal AST node first, then
- Post‑attach container `:range` by walking the returned AST and merging child
  ranges with stored opening/closing spans.

### 4.5 Blocks and Special Forms

Key functions:
- `parse_grouped_expression/1` (parenthesized `( ... )`).
- `parse_do_block/2` (and any arity‑1 variant, if present).
- `parse_anon_function/1` (`fn -> ... end`).
- `build_block_nr/2` (blocks `{:__block__, meta, exprs}`).

#### 4.5.1 `{:__block__, meta, exprs}` (`build_block_nr/2`)

Callers: e.g. `parse_program/1` and do‑block/anon‑fn bodies.

Plan:

- When `build_block_nr/2` constructs a `{:__block__, meta, exprs}`:
  - If `exprs` is non‑empty:
    - `range = merge_ranges(Enum.map(exprs, &ast_range/1))`.
  - If `exprs` is empty:
    - Use a degenerate range from parser start (or leave nil and expect the
      root attach logic to fill it).
  - Update `meta` via `put_meta_range/2`.

For the top‑level program block, we will **override or refine** its `:range` in
`parse/2` after we compute root coverage (§5).

#### 4.5.2 Grouped Expressions `( ... )`

`parse_grouped_expression/1`:
- Already tracks `opening_paren_meta` and various closing cases.
- Extend it to:
  - Capture `open_paren_range` when we see `"("`.
  - Capture `close_paren_range` before consuming `")"`.
  - For the grouped AST:
    - If it is a simple expression, its `:range` spans from the `(` to `)` or
      at least from inner expression start to `)`.
    - For multi‑line / multi‑expression groups, use child ranges plus paren
      ranges.

#### 4.5.3 `do` Blocks

`parse_do_block/2` builds call AST with `do`/`end` meta.

Enhancements:

1. Capture `do_range` when we see `:do` (or `do` keyword token).
2. Capture `end_range` just before consuming `:end`.
3. Each clause (often encoded as `{type, exprs}` or `{:->, meta, [pattern, body]}`):
   - Clause range: merge pattern ranges, arrow token range (if present), and body range.
4. The overall call AST (with `do` keyword meta) gets range from:
   - `callee_range`,
   - Outer args,
   - All clause ranges,
   - `do` and `end` ranges.

This ensures `foo do ... end` spans from `f` through `end`.

#### 4.5.4 Anonymous Functions `fn ... end`

`parse_anon_function/1`:
- Capture `fn_range` when we see the `:fn` token.
- Capture `end_range` just before consuming `:end`.

For each clause `{:->, meta, [pattern, body]}`:
- Clause range = merge of:
  - pattern ranges,
  - arrow token range,
  - body range.

Anon‑fn range: merge of `fn_range`, all clause ranges, and `end_range`.

### 4.6 Interpolation

Interpolation is handled in the scanning helpers (`scan_loop/5`, `build_interpolation_ast/4`).

Plan:

- For string/charlist/atom/sigil interpolations:
  - `scan_loop` already:
    - sees `:begin_interpolation` token and `:end_interpolation` token.
    - builds an `expr` AST for the interpolation body and passes
      `open_meta` / `end_meta` to `build_interpolation_ast`.

- Extend `build_interpolation_ast/4` to:
  - Derive a range for the interpolation wrapper node from:
    - `open_range = token_range(begin_token)` or approximated from `open_meta`.
    - `end_range = token_range(end_token)` or approximated from `end_meta`.
    - `expr_range = ast_range(expr)`.
  - Attach `:range` via `put_meta_range/2` on the interpolation AST node.

- For the surrounding literal (string, heredoc, sigil):
  - The literal’s own range spans delimiters and inner content.
  - Interpolation node ranges fall **inside** that literal’s range.

---

## 5. Root Range & Parser State

### 5.1 Parser State: `last_span`

Extend `new/2` (parser initialization) in `lib/spitfire.ex`:

```elixir
defp new(code, opts) do
  %{
    stream: Spitfire.TokenStream.new(code, opts[:line] || 1, opts[:column] || 1, opts),
    start_line: opts[:line] || 1,
    start_column: opts[:column] || 1,
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
end
```

### 5.2 Updating `last_span` in `next_token/1`

When advancing tokens, we want `last_span` to track the **most recent real
token we moved past**, not `:eof` or synthetic markers.

In `next_token/1`:

```elixir
defp next_token(%{stream: stream, current_token: nil, peek_token: nil} = parser) do
  # First fill peek_token; no current_token to consume yet.
  {tok, stream1} = Spitfire.TokenStream.next(stream)
  %{parser | stream: stream1, peek_token: tok, fuel: 150}
end

defp next_token(%{stream: stream} = parser) do
  # We are about to advance past current_token.
  cur = parser.peek_token

  # Update last_span if current_token is a real token with a range.
  last_span =
    case token_range(parser.current_token) do
      {{_sl, _sc}, {_el, _ec}} = span -> span
      _ -> parser.last_span
    end

  {tok, stream1} = Spitfire.TokenStream.next(stream)

  %{
    parser
    | stream: stream1,
      current_token: cur,
      peek_token: tok,
      fuel: 150,
      last_span: last_span
  }
end
```

Notes:
- Synthetic tokens (like `:fake_closing_bracket`) should not have ranged
  metas in Toxic mode, so `token_range/1` will return `nil` for them.
- `last_span` will then always refer to the last **real** token we consumed.

### 5.3 Root Range Attachment in `parse/2`

After:

```elixir
{ast, parser} = parse_program(parser)
```

we attach the root range:

```elixir
root_start = {parser.start_line, parser.start_column}

root_end =
  case parser.last_span do
    {{_sl, _sc}, {el, ec}} -> {el, ec}
    _ -> root_start  # empty file
  end

ast =
  case ast do
    {form, meta, args} ->
      range = merge_ranges([meta_range(meta), {root_start, root_end}])
      {form, put_meta_range(meta, range), args}

    other ->
      other
  end
```

This ensures:
- Root always has a `:range` in Toxic mode.
- Root coverage spans from file start to EOF.

---

## 6. Error Recovery & Synthetic Tokens

Spitfire injects synthetic closers (e.g. `:fake_closing_bracket`) in error
branches, and we must not derive ranges directly from them.

Guidelines:

1. **Do not emit ranges from synthetic tokens**.
   - They either have no Toxic ranged meta or `token_range/1` must return `nil`
     for them.

2. **Container with children but missing closer**:
   - Container range is derived from:
     - Opening token range, and
     - Last child’s range.

   Example:

   ```elixir
   open_range = token_range(open_token)
   last_child_range = ast_range(List.last(children)) || open_range
   container_range = merge_ranges([open_range, last_child_range])
   ```

3. **Container with no children and missing closer**:
   - Container range degenerates to opening token range (if available).

4. **Error blocks** `{:__block__, [error: true | meta], []}`:
   - May have `:range` set to the location where the error was detected (via
     the token that triggered the error).
   - Invariants are **best‑effort** for malformed code: we prioritize not
     crashing or mis‑spanning siblings over strict coverage guarantees.

---

## 7. Testing Strategy (Toxic Mode)

Existing parity tests must remain intact:
- `Spitfire.parse(code)` equals `Code.string_to_quoted(code, ...)` in both
  legacy and Toxic tests.

### 7.1 Literal Encoder Parity Test Adjustment

Current literal encoder parity tests use:

```elixir
encoder = fn l, m -> {:ok, {:__literal__, m, [l]}} end
```

With `:range` added in Toxic mode, we need to block it out so the AST matches
core.

Change these test encoders to discard `:range`:

```elixir
encoder = fn literal, meta ->
  meta = Keyword.delete(meta, :range)
  {:ok, {:__literal__, meta, [literal]}}
end
```

This keeps:
- Core side unchanged (no `:range`).
- Spitfire side now drops `:range` in the encoded AST for those tests only.

### 7.2 New Range‑Focused Tests

Add a dedicated test module, e.g. `test/spitfire_ranges_test.exs`, or a
`describe "ranges"` block inside `test/spitfire_toxic_test.exs`, with:

#### 7.2.1 Literal Encoder Range Tests

Use a test encoder that sends meta to the test process:

```elixir
encoder = fn lit, meta ->
  send(self(), {:lit_meta, lit, meta})
  {:ok, {:__literal__, meta, [lit]}}
end
```

Examples:

- List literal:

  ```elixir
  code = "[1, 23]"
  {:ok, _ast} = Spitfire.parse(code, literal_encoder: encoder)

  assert_received {:lit_meta, 1, meta1}
  assert meta1[:range] == {{1, 2}, {1, 3}}

  assert_received {:lit_meta, 23, meta2}
  assert meta2[:range] == {{1, 5}, {1, 7}}

  assert_received {:lit_meta, [_, _], list_meta}
  assert list_meta[:range] == {{1, 1}, {1, 8}}
  ```

- Tuple, map, bitstring, heredocs, sigils, multi‑line containers.

#### 7.2.2 Composite Node Range Tests

Use normal parsing (no literal encoder) and pattern‑match on AST:

- Binary operator:

  ```elixir
  code = "1 + 23"
  {:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse(code)

  assert meta[:range] == {{1, 1}, {1, 7}}
  assert ast_range(lhs) == {{1, 1}, {1, 2}}
  assert ast_range(rhs) == {{1, 5}, {1, 7}}
  ```

- Paren call, no‑parens call, remote call via dot.
- `do` blocks, anon functions, grouped expressions.

#### 7.2.3 Structural Invariant Tests

Implement a helper to check tree invariants:

```elixir
defp assert_range_tree(ast) do
  walk(ast, nil)
end

defp walk({_, meta, args} = node, parent_range) do
  range = meta_range(meta)
  assert range != nil

  if parent_range do
    assert pos_leq?(elem(range, 0), elem(parent_range, 0))
    assert pos_leq?(elem(range, 1), elem(parent_range, 1))
  end

  child_ranges =
    args
    |> Enum.map(&walk(&1, range))
    |> Enum.filter(& &1)

  child_ranges
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.each(fn [r1, r2] ->
    assert pos_leq?(elem(r1, 1), elem(r2, 0))
  end)

  range
end

defp walk(list, parent_range) when is_list(list) do
  Enum.each(list, &walk(&1, parent_range))
  nil
end

defp walk(_other, _parent), do: nil
```

Run this on:
- Single and multi‑expression inputs.
- Nested containers and blocks.
- A few malformed snippets to ensure it doesn’t crash (and to confirm
  invariants are still reasonable).

#### 7.2.4 Root Range Tests

Verify the root’s range:

- Simple program:

  ```elixir
  code = "1 + 23\n"
  {:ok, {_, meta, _}} = Spitfire.parse(code)
  assert meta[:range] == {{1, 1}, {2, 1}}  # assuming EOF at start of line 2
  ```

- Multi‑line, trailing blank lines, comments, etc.

---

## 8. Phased Implementation Plan

To minimize risk:

1. **Phase 0 – Helpers**
   - Add `token_range/1`, position helpers, `meta_range/1`, `put_meta_range/2`,
     `merge_ranges/1`, `ast_range/1`.
   - Add basic unit tests for these helpers where practical.

2. **Phase 1 – Parser State (`last_span`)**
   - Extend `new/2` and `next_token/1` for `last_span`.
   - Add root range attachment in `parse/2`.
   - Tests: root range on simple programs.

3. **Phase 2 – Literal & Leaf Ranges**
   - Refactor `encode_literal/2` as described.
   - Update call sites.
   - Attach ranges for leaf nodes (identifiers, booleans, etc.).
   - Update literal encoder parity test encoder (drop `:range`).
   - Tests: literal encoder meta range tests.

4. **Phase 3 – Operators**
   - Capture operator ranges and add `attach_op_range/2`.
   - Wire it into `parse_infix_expression/2`, `parse_prefix_expression/1`,
     `parse_range_expression/2`, `parse_pipe_op/2`, etc.
   - Tests: operator range cases.

5. **Phase 4 – Calls & Containers**
   - Attach ranges to calls and dots.
   - Attach ranges to containers (lists, tuples, maps, structs, bitstrings).
   - Tests: call and container range cases.

6. **Phase 5 – Blocks & Special Forms**
   - Add ranges to blocks (`__block__`, grouped expressions, do blocks,
     anon functions).
   - Tests: do/anon/paren range cases.

7. **Phase 6 – Interpolation**
   - Attach ranges for interpolation AST nodes and ensure string/sigil/heredoc
     containers span their delimiters.
   - Tests: interpolated strings, atoms, sigils.

8. **Phase 7 – Structural Invariants**
   - Add `assert_range_tree/1` tests across a broad sample of inputs.

Each phase should run the existing test suite in both legacy and Toxic modes,
ensuring no regressions.

---

## 9. Performance Notes

Expected overhead:

- **Per token**:
  - One extra pattern match when calling `token_range/1` in `next_token/1` and
    in a handful of parser functions that care about boundary tokens.
- **Per AST node**:
  - Some `merge_ranges/1` calls, typically linear in the number of children for
    that node (small in practice).
  - One extra `:range` entry (two coordinate tuples) in `meta` for nodes
    built in Toxic mode.

Rough expectations:
- Time: modest overhead, likely single‑digit percent.
- Memory: +one extra tuple per node in Toxic mode; legacy mode unaffected.

If needed, we can:
- Avoid computing `:range` for certain internal nodes (but that complicates
  invariants).
- Focus on correctness first; optimize only if real workloads show issues.

---

## 10. Documentation (PARSER.md)

Add a short subsection to `PARSER.md` §8 (metadata) describing ranges in Toxic
mode:

```markdown
### Range Metadata (Toxic Mode)

When using the Toxic tokenizer, Spitfire attaches a `:range` key to AST node
metadata:

- **Format**: `{:range, {{start_line, start_col}, {end_line, end_col}}}`
- **Coordinates**: 1-based line/column, representing a half-open interval
  `[start, end)`.
- **Invariants**:
  - Parent ranges contain the ranges of all children.
  - Sibling ranges do not overlap (they may touch).
  - The root node’s range spans the entire document (from the parser start
    position to logical EOF).

Example:

```elixir
{:ok, {:+, meta, [lhs, rhs]}} =
  Spitfire.parse("1 + 2", tokenizer: :toxic)

meta[:range]
# => {{1, 1}, {1, 6}}
```

Legacy (non-Toxic) mode does not attach range metadata, preserving the original
AST shape and metadata.
```

---

With these refinements, the range plan is ready for implementation:
- Toxic mode gains precise, tree‑consistent `:range` metadata.
- Legacy mode remains fully backward‑compatible.
- Tests and documentation clearly codify expectations and invariants. 

