# AST Range Metadata with Toxic — V3 Plan (Exact Ranges, No Approximation)

This V3 plan refines `RANGES_PLAN_V2.md` based on
`RANGES_PLAN_V2_REVIEW_CLAUDE.md` and the additional requirement:

> **No place for approximation.** Even in error‑tolerant mode Toxic emits
> missing tokens (though they may be 0‑range).

Goals are unchanged:
- Use **Toxic’s ranged token metadata** to attach precise, non‑overlapping
  ranges to Spitfire’s AST nodes in **Toxic mode**.
- Preserve AST shape and meta in **legacy mode** (no `:range` there).
- Guarantee:
  - Parent ranges contain all children.
  - Sibling ranges do not overlap.
  - The root node spans the whole document.
  - Literals rendered via `literal_encoder` see range‑aware meta.
- These guarantees hold **even for syntactically invalid code**, because Toxic
  always emits structural tokens (including missing closers) with valid
  ranges; some may be zero‑width (start == end) but are still exact positions.

---

## 1. Range Model & Invariants

### 1.1 Representation

In Toxic mode, many AST nodes will carry a `:range` entry in their `meta`:

```elixir
{:range, {{start_line, start_col}, {end_line, end_col}}}
```

Semantics:
- Coordinates are **1‑based** (Toxic semantics).
- We interpret `:range` as a half‑open interval `[start, end)` in conceptual
  terms. In practice we only compare `{line, col}` pairs.
- A “0‑range” token (e.g., for a missing closer) has `start == end` but still
  represents a precise position in the document.

We **do not** remove or change existing meta keys:
- `:line`, `:column` remain the canonical *start* position.
- `:closing`, `:newlines`, `:do`, `:end`, `:end_of_expression`, etc., stay
  exactly as they are.

In **legacy mode**, no `:range` metadata is created.

### 1.2 Tree Invariants (All Inputs)

For AST produced in Toxic mode, **for any input (valid or invalid)**:

- **Parent containment**

  For node `N` with range `R(N)` and children `Ci`:

  - Let `S(x)` = start of `x`, `E(x)` = end of `x`.
  - Then:
    - `S(R(N)) <= S(R(Ci))` for all `i`.
    - `E(R(Ci)) <= E(R(N))` for all `i`.

  Equality at boundaries is allowed (child may start at parent start, or end at
  parent end).

- **Sibling non‑overlap**

  For siblings `Ci`, `Cj` with `i < j`:

  - `E(R(Ci)) <= S(R(Cj))`.

  Adjacent siblings may “touch” at a boundary; they must not overlap.

- **Root coverage**

  Let `root` be the top AST node returned by `Spitfire.parse/2`:

  - `S(R(root)) = {start_line, start_column}` from parser opts (defaults `{1,1}`).
  - `E(R(root))` equals the logical EOF position:
    - Derived from the last real token span as tracked by the parser; that
      includes structural closers (inserted by Toxic if necessary).

Since Toxic:
- emits ranged metadata for all tokens, and
- in tolerant mode uses **structural token synthesis** (e.g., missing closers)
  with valid coordinates (possibly zero‑width),

we can guarantee these invariants **for all inputs** without approximations.

---

## 2. Low‑Level Helpers

Helpers live in `lib/spitfire.ex` near `current_meta/1` /
`current_eoe/1`. They do **not** change existing behavior.

### 2.1 `current_meta/1` vs `token_range/1`

`current_meta/1` already:
- Accepts both legacy `{line, col, extra}` and Toxic `{{sl, sc}, {el, ec}, extra}` metas.
- Returns **start‑only** metadata `[line: ..., column: ...]` (plus extras).

We keep this behavior. It is the canonical way to ask “where did this
token/node start?”.

Add a separate helper to extract full spans from **raw tokens**:

```elixir
# Toxic ranged tokens (2‑tuple and 3‑tuple metas)
defp token_range({_, {{sl, sc}, {el, ec}, _extra}}),
  do: {{sl, sc}, {el, ec}}

defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _value}),
  do: {{sl, sc}, {el, ec}}

# Some operators (e.g., :in_op) use 4‑tuple shapes – mirror existing patterns:
defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _, _}),
  do: {{sl, sc}, {el, ec}}

# Legacy tokens: no ranges, preserve legacy behavior
defp token_range({_, {_, _, _}}), do: nil
defp token_range({_, {_, _, _}, _}), do: nil
defp token_range({_, {_, _, _}, _, _}), do: nil

defp token_range(_), do: nil
```

Thus:
- In Toxic mode, structural tokens (including synthesized closers) have
  legitimate ranges (possibly zero‑width) and `token_range/1` always returns a
  position pair.
- In legacy mode, `token_range/1` returns `nil`, so no `:range` meta is ever
  attached.

### 2.2 Position and Range Helpers

Basic comparisons:

```elixir
defp pos_leq?({l1, c1}, {l2, c2}),
  do: l1 < l2 or (l1 == l2 and c1 <= c2)

defp pos_geq?({l1, c1}, {l2, c2}),
  do: l1 > l2 or (l1 == l2 and c1 >= c2)

defp pos_min(p1, p2), do: if(pos_leq?(p1, p2), do: p1, else: p2)
defp pos_max(p1, p2), do: if(pos_geq?(p1, p2), do: p1, else: p2)
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
  # Overwrite any existing :range; no effect in legacy mode.
  Keyword.put(meta, :range, range)
end

defp merge_ranges(ranges) do
  ranges
  |> Enum.filter(& &1)
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

AST accessor:

```elixir
defp ast_range({_, meta, _}) when is_list(meta), do: meta_range(meta)
defp ast_range(_), do: nil
```

---

## 3. Literal & Leaf Ranges

This phase gives literal nodes and leaf nodes precise ranges, especially when
`literal_encoder` is used.

### 3.1 `current_meta/1` Stays Start‑Only

We do **not** modify `current_meta/1`. It continues to:
- Extract only start position (`line`, `column`).
- Ignore end positions in Toxic metas.

Full spans come exclusively from `token_range/1`.

### 3.2 Refactor `encode_literal` to Use Parser

Unify `encode_literal` to derive metadata from the parser:

```elixir
defp encode_literal(%{literal_encoder: encoder} = parser, literal)
     when is_function(encoder) do
  base_meta = current_meta(parser)

  base_meta =
    case token_range(parser.current_token) do
      {{_sl, _sc}, {_el, _ec}} = r -> put_meta_range(base_meta, r)
      _ -> base_meta
    end

  meta = additional_meta(literal, parser) ++ base_meta

  case encoder.(literal, meta) do
    {:ok, ast}   -> ast
    {:error, r}  -> Logger.error(r); literal
  end
end

defp encode_literal(_parser, literal) do
  literal
end
```

Call sites are updated to call `encode_literal(parser, literal)` instead of
passing an explicit meta argument. For example:

```elixir
defp parse_int(%{current_token: {:int, _meta, value}} = parser) do
  int = encode_literal(parser, value)
  {int, parser}
end
```

This centralizes range logic and ensures all literals get consistent meta.

### 3.3 List / Tuple / Map Literal Ranges with `literal_encoder`

Many literals are both:
- Parsed by a container parser (`parse_list_literal/1`, `parse_tuple_literal/1`,
  `parse_map_literal/1`, struct/bitstring parsers), and
- Rendered through `literal_encoder`.

We want the *literal AST* returned from `literal_encoder` to have:
- Correct `:line` / `:column`, and
- A `:range` covering from opening delimiter through closing delimiter.

**Important design choice**:
- We do **not** extend `additional_meta/2` nor parser state to carry
  `close_range`.
- Instead, each container parser:
  1. Captures the opening range and closing range from Toxic tokens.
  2. Calls `encode_literal/2` to let the literal encoder construct the literal
     AST (with element ranges already attached).
  3. **Post‑attaches** the container `:range` on the returned literal AST using
     those boundary spans.

Concrete example: `parse_list_literal/1` for `[1, 23]`:

```elixir
defp parse_list_literal(%{current_token: {:"[", _}} = parser) do
  open_range = token_range(parser.current_token)

  # parse elements, eventually current_token is :"]"
  # ...
  close_range = token_range(parser.current_token)

  # Now we have elements as Elixir list `elems`
  list_value = elems

  # Use encode_literal to build literal AST
  list_ast = encode_literal(parser, list_value)

  # Post-attach container range on returned literal AST
  container_range = merge_ranges([open_range, close_range])

  list_ast =
    case list_ast do
      {form, meta, args} ->
        {form, put_meta_range(meta, container_range), args}

      other ->
        other
    end

  {list_ast, parser}
end
```

Notes:
- `open_range` and `close_range` are derived from Toxic tokens. If the closer
  is missing in the source, Toxic still synthesizes a closing token with a
  range (possibly 0‑width), so the container range remains exact.
- Element nodes already carry their own `:range` via `encode_literal/2` or
  leaf attachment, so parent containment and non‑overlap hold for the list.

The same pattern is applied to tuples, maps, structs, and bitstrings.

### 3.4 Non‑literal Leaf Nodes

Leaf nodes that do not go through `literal_encoder` such as:
- Lone identifiers (`parse_lone_identifier/1`),
- Aliases,
- Booleans without `literal_encoder`,
- Certain operator identifiers,

are updated as follows:

1. Build `meta` using existing logic (`current_meta/1`, `push_delimiter/2`, etc.).
2. Attach a token‑based range:

   ```elixir
   range = token_range(parser.current_token)
   meta  = put_meta_range(meta, range)
   ```

3. Construct the AST node with this enriched meta.

Because these are 1‑token nodes, using the token span directly is exact.

---

## 4. Composite Nodes & Families

Composite nodes derive their ranges from child ranges and structural token
ranges (delimiters, operators, etc.).

### 4.1 Generic Attachment Helper

For simple 3‑tuple AST nodes `{form, meta, args}`:

```elixir
defp attach_range({form, meta, args}) do
  child_ranges = Enum.map(args, &ast_range/1)
  range = merge_ranges(child_ranges)
  {form, put_meta_range(meta, range), args}
end
```

This covers cases where the node’s extent is fully defined by its children.
When delimiters/operators must be included, we pass their ranges explicitly.

### 4.2 Operators (Binary/Unary, Range, Pipe, etc.)

Functions:
- `parse_infix_expression/2`
- `parse_prefix_expression/1`
- `parse_range_expression/1` and `/2`
- `parse_pipe_op/2`
- Specialized operators (assoc, match, type, etc.)

Pattern:

1. When `parser.current_token` is the operator:

   ```elixir
   op_range = token_range(parser.current_token)
   op_meta  = current_meta(parser)
   ```

2. Advance past operator as today (preserving existing semantics).

3. After computing `lhs` and `rhs` and building AST:

   ```elixir
   ast = {op, op_meta, [lhs, rhs]}

   defp attach_op_range({op, meta, [lhs, rhs]}, op_range) do
     child_ranges = [ast_range(lhs), op_range, ast_range(rhs)]
     range = merge_ranges(child_ranges)
     {op, put_meta_range(meta, range), [lhs, rhs]}
   end
   ```

4. Unary operators follow the same pattern with just one operand.

This ensures an expression like `1 + 23` spans **from the start of `1` to the
end of `23`**, including the `+` operator, and respects sibling non‑overlap
in any surrounding context.

### 4.3 Calls and Dots

Functions:
- `parse_call_expression/2` (paren calls)
- `parse_identifier/1` in call context (no‑parens calls)
- `parse_dot_expression/2`, `parse_dot_call_expression/2`

Each call node provides:
- A **callee** node (identifier, alias, dot expression, etc.) with its range.
- Zero or more argument nodes with ranges.
- For paren calls, opening and closing `(` / `)` tokens with ranges.

Strategy:

1. Identify:
   - `callee_range = ast_range(callee)` (or token_range if leaf).
   - `arg_ranges = Enum.map(args, &ast_range/1)`.
   - For paren calls:
     - `open_paren_range = token_range(open_paren_token)`.
     - `close_paren_range = token_range(close_paren_token)` captured before
       it is consumed.

2. Compute call range:

   - Paren calls: `merge_ranges([callee_range, open_paren_range,
     close_paren_range | arg_ranges])`.
   - No‑parens calls: `merge_ranges([callee_range | arg_ranges])`.

3. Attach via `put_meta_range/2` on the call node meta.

This ensures `foo(1, 23)` spans from `f` through `)`, and `foo 1, 23` spans
from `f` through `23`.

### 4.4 Containers (Lists, Tuples, Maps, Structs, Bitstrings)

For containers **not** going through `literal_encoder` (e.g. when there is no
literal encoder, or for structural inner nodes), we apply the same boundaries
logic:

1. Capture `open_range = token_range(opening_token)` on entry.
2. Parse elements, each with its own `:range`.
3. Capture `close_range = token_range(closing_token)` just before consuming it.
4. Compute container range:

   ```elixir
   container_range =
     merge_ranges([open_range, close_range | Enum.map(children, &ast_range/1)])
   ```

5. Attach via `put_meta_range/2`.

Even in error cases:
- If the closer is missing in the source, Toxic’s structural recovery inserts a
  closing token at the best location (possibly with `start == end`); this is
  still exact and allows invariants to hold.

Spitfire’s own synthetic tokens (`:fake_closing_bracket`, etc.) are **ignored**
for range purposes (`token_range/1` returns `nil` for them).

### 4.5 Blocks & Special Forms

Key functions:
- `parse_grouped_expression/1` (`( ... )`).
- `parse_do_block/2` (`do ... end`).
- `parse_anon_function/1` (`fn ... end`).
- `build_block_nr/2` (wraps expression lists into `{:__block__, meta, exprs}`).

#### 4.5.1 `{:__block__, meta, exprs}` from `build_block_nr/2`

Whenever `build_block_nr/2` returns a `{:__block__, meta, exprs}`:

- If `exprs` is non‑empty:
  - Range is `merge_ranges(Enum.map(exprs, &ast_range/1))`.
- If `exprs` is empty:
  - We can leave `:range` as `nil` here, because the top‑level root range
    will be attached later using parser start and `last_span` (§5).

Attach via `put_meta_range/2`. For the top‑level program block, `parse/2` will
further adjust its range using root coverage.

#### 4.5.2 Grouped Expressions `( ... )`

`parse_grouped_expression/1` already tracks:
- `opening_paren_meta`,
- multiple closing cases,
- expression(s) inside the group.

Extend it to:

1. Capture `open_range = token_range(open_paren_token)` on entry.
2. Capture `close_range = token_range(close_paren_token)` just before
   consuming the closing `")"`.
3. For the resulting AST:
   - If a single expression: merge `[open_range, close_range, ast_range(expr)]`.
   - If multiple expressions (e.g. unwrapped `{:__block__}`): merge
     `[open_range, close_range | child_ranges]`.

Attach via `put_meta_range/2`.

#### 4.5.3 `do` Blocks

`parse_do_block/2` builds AST of the form:
- `{{callee, meta, args}, updated_meta, [do_clauses]}` or similar, with
  `:do` and `:end` metas.

Enhancements:

1. Capture `do_range = token_range(do_token)` when `:do` is first seen.
2. Capture `end_range = token_range(end_token)` just before consuming `:end`.
3. Each clause:
   - Typically encoded as `{label, exprs}` or `{:->, meta, [pattern, body]}`.
   - Range is `merge_ranges([label_range, pattern_ranges, arrow_range,
     body_ranges])`, depending on exact clause AST.
4. Full block/call range:

   ```elixir
   range =
     merge_ranges(
       [callee_range, do_range, end_range] ++ clause_ranges ++ arg_ranges
     )
   ```

Attach on the call AST meta.

#### 4.5.4 Anonymous Functions `fn ... end`

`parse_anon_function/1`:

1. Capture `fn_range = token_range(fn_token)` on entry.
2. For each clause `{:->, meta, [pattern, body]}`:
   - Capture `arrow_range` when `:->` is seen.
   - Clause range = `merge_ranges([pattern_ranges, arrow_range, body_ranges])`.
3. Capture `end_range = token_range(end_token)` before consuming `:end`.
4. Full `{:fn, meta, clauses}` range = `merge_ranges([fn_range, end_range |
   clause_ranges])`.

Attach via `put_meta_range/2` on the `:fn` meta.

### 4.6 Interpolation

Interpolation is handled by `scan_loop/5` and `build_interpolation_ast/4`.

Toxic emits:
- `:begin_interpolation` and `:end_interpolation` tokens with ranged metas,
  including for missing interpolations (zero‑width tokens).

Plan:

1. When `scan_loop/5` sees `:begin_interpolation`, record:

   ```elixir
   open_range = token_range(begin_token)
   open_meta  = current_meta(parser)
   ```

2. After parsing the interpolated `expr` and seeing `:end_interpolation`:

   ```elixir
   end_range = token_range(end_token)
   end_meta  = current_meta(parser)
   ```

3. Build interpolation AST via `build_interpolation_ast(expr, open_meta, end_meta, kind)`
   as today, but:
   - Attach an interpolation range:

     ```elixir
     interp_range = merge_ranges([open_range, end_range, ast_range(expr)])
     ast = put_meta_range_on_interp(ast, interp_range)
     ```

     where `put_meta_range_on_interp/2` updates the meta of the wrapper node
     (e.g. `:"::"` node for binary interpolations).

4. The outer literal (string/heredoc/sigil) gets its `:range` from delimiters
   and child fragments (including interpolation nodes), so interpolation ranges
   lie strictly within the literal’s range.

No approximations are needed: Toxic provides ranges for both interpolation
markers even in error‑recovery scenarios.

---

## 5. Root Range & Parser State

### 5.1 Extend Parser State with `last_span`

In `new/2`:

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

### 5.2 Update `last_span` in `next_token/1`

On each `next_token/1` (except the very first fill of `peek_token`), update
`last_span` from `current_token` **before** shifting it:

```elixir
defp next_token(%{stream: stream, current_token: nil, peek_token: nil} = parser) do
  {tok, stream1} = Spitfire.TokenStream.next(stream)
  %{parser | stream: stream1, peek_token: tok, fuel: 150}
end

defp next_token(%{stream: stream} = parser) do
  last_span =
    case token_range(parser.current_token) do
      {{_sl, _sc}, {_el, _ec}} = span -> span
      _ -> parser.last_span
    end

  cur = parser.peek_token
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

- For Toxic tokens (including inserted closers), `token_range/1` returns an
  exact span.
- For Spitfire synthetic tokens (`:fake_closing_bracket` etc.), `token_range/1`
  returns `nil`, so they never update `last_span`.

### 5.3 Attach Root Range in `parse/2`

After:

```elixir
{ast, parser} = parse_program(parser)
```

compute and attach root range:

```elixir
root_start = {parser.start_line, parser.start_column}

root_end =
  case parser.last_span do
    {{_sl, _sc}, {el, ec}} -> {el, ec}
    _ -> root_start
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

Because `last_span` comes from the last real Toxic token consumed, root coverage
exactly spans from parser start to EOF, even if the final tokens were inserted
for error recovery.

---

## 6. Error Recovery & Synthetic Tokens (Exact, Not Best‑Effort)

Key facts:
- Toxic’s tolerant mode synthesizes structural tokens (e.g., missing closers)
  with **real ranged metadata** (possibly 0‑width).
- We always process the full Toxic stream via `Spitfire.TokenStream`, so all
  such tokens are visible to the parser.

Therefore:

1. **Container ranges always use actual open/close tokens from Toxic**:
   - `open_range = token_range(open_token)`.
   - `close_range = token_range(close_token)` (inserted by Toxic if the source
     omitted it).
   - Element ranges come from child nodes.
   - Container range is `merge_ranges([open_range, close_range | elem_ranges])`.

2. **No fallback to “open + last child”**:
   - We never approximate closing positions from children; we always rely on
     structural tokens (even if 0‑width).

3. **Spitfire’s fake tokens are excluded from ranges**:
   - `token_range/1` returns `nil` for tokens like `:fake_closing_bracket`.
   - They never contribute to container or root ranges or to `last_span`.
   - They exist only for legacy error‑recovery semantics, not for range
     computation.

4. **Invariants hold even for invalid code**:
   - Parent containment and sibling non‑overlap are computed from properly
     ordered Toxic tokens.
   - Structural synthesis by Toxic ensures we always have a consistent open/close
     sequence to derive ranges from.

The only “best‑effort” aspect is error **diagnostics**; ranges themselves are
deterministic and exact given Toxic’s stream.

---

## 7. Testing Strategy (Toxic Mode)

Existing tests:
- Must not change AST shape or meta in **legacy** mode.
- For Toxic mode, AST shape remains the same; only `:range` keys are new.

### 7.1 Literal Encoder Parity Test Adjustment

Existing parity tests use:

```elixir
encoder = fn l, m -> {:ok, {:__literal__, m, [l]}} end
```

Toxic mode now adds `:range` to `meta`, which would break equality with
`Code.string_to_quoted`.

Introduce a helper (e.g. in `test/support/test_helpers.ex`):

```elixir
def parity_encoder do
  fn literal, meta ->
    meta = Keyword.delete(meta, :range)
    {:ok, {:__literal__, meta, [literal]}}
  end
end
```

Use `parity_encoder()` in parity tests so `:range` is stripped only for those
tests.

### 7.2 New Range‑Focused Tests

Tests live in Toxic mode (e.g. `SpitfireToxicTest` or a dedicated
`SpitfireRangesTest`), using `setup` to set `:tokenizer, :toxic`.

#### 7.2.1 Literal Encoder Range Tests

Use a test encoder:

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

#### 7.2.2 Composite Node Range Tests

Sample tests:

- Binary operator:

  ```elixir
  code = "1 + 23"
  {:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse(code)

  assert meta[:range] == {{1, 1}, {1, 7}}
  assert ast_range(lhs) == {{1, 1}, {1, 2}}
  assert ast_range(rhs) == {{1, 5}, {1, 7}}
  ```

- Paren call, no‑parens call, remote call via dot.
- Containers, `do` blocks, anon functions, grouped expressions, interpolation.

#### 7.2.3 Structural Invariant Tests

Helper:

```elixir
defp assert_range_tree(ast) do
  walk(ast, nil)
end

defp walk({_, meta, args}, parent_range) do
  range = meta_range(meta)
  assert range != nil

  if parent_range do
    {p_start, p_end} = parent_range
    {c_start, c_end} = range
    assert pos_leq?(p_start, c_start)
    assert pos_leq?(c_end, p_end)
  end

  child_ranges =
    args
    |> Enum.map(&walk(&1, range))
    |> Enum.filter(& &1)

  child_ranges
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.each(fn [r1, r2] ->
    {_s1, e1} = r1
    {s2, _e2} = r2
    assert pos_leq?(e1, s2)
  end)

  range
end

defp walk(list, parent_range) when is_list(list) do
  Enum.each(list, &walk(&1, parent_range))
  nil
end

defp walk(_other, _parent), do: nil
```

Run this against:
- Single and multi‑expression programs.
- Nested constructs.
- Invalid code (unclosed containers, malformed blocks) to confirm invariants
  still hold thanks to Toxic’s synthetic structural tokens.

#### 7.2.4 Root Range Tests

Example:

```elixir
code = "1 + 23\n"
{:ok, {_, meta, _}} = Spitfire.parse(code)
assert meta[:range] == {{1, 1}, {2, 1}}
```

Extend to multi‑line, trailing blank lines, and comment‑heavy samples.

---

## 8. Phased Implementation Plan

Implementation is substantial; we follow a phased rollout:

0. **Helpers**
   - Add `token_range/1`, position helpers, `meta_range/1`, `put_meta_range/2`,
     `merge_ranges/1`, `ast_range/1`.
   - Optional: add a macro/helper (Phase 0.5) like:

     ```elixir
     defp with_token_range(parser, fun) do
       range = token_range(parser.current_token)
       fun.(range, parser)
     end
     ```

     to reduce boilerplate for capturing ranges before `next_token/1`.

1. **Parser State**
   - Add `last_span` to parser state.
   - Update `next_token/1`.
   - Attach root range in `parse/2`.

2. **Literal & Leaf Ranges**
   - Refactor `encode_literal/2` as in §3.2 and update call sites.
   - Attach ranges for leaf nodes.
   - Update literal encoder parity tests to use `parity_encoder/0`.

3. **Operators**
   - Capture operator ranges and integrate `attach_op_range/2`.
   - Tests for simple operator expressions.

4. **Calls & Containers**
   - Attach ranges for calls/dot expressions.
   - Attach ranges for non‑encoded containers.

5. **Blocks & Special Forms**
   - Attach ranges for grouped expressions, `do` blocks, anon functions,
     and `__block__` nodes.

6. **Interpolation**
   - Attach ranges for interpolation wrapper nodes and outer literals.

7. **Structural Invariants**
   - Add `assert_range_tree/1` tests across a corpus of examples.

Each phase runs the full test suite in both legacy and Toxic modes.

---

## 9. Performance Notes

Expected overhead in Toxic mode:
- Per token:
  - A few extra pattern matches when calling `token_range/1` in `next_token/1`
    and boundary‑sensitive parsers.
- Per AST node:
  - Some `merge_ranges/1` calls; complexity is linear in child count, which is
    small in practice.
  - One extra meta entry `:range` (two small tuples).

Legacy mode:
- No calls to `token_range/1` are relevant (it returns `nil`).
- No `:range` entries are attached.

We expect single‑digit percentage overhead in Toxic mode with no measurable
impact in legacy mode. We prioritize correctness and invariants; optimize only
if profiling shows issues.

---

## 10. Documentation (PARSER.md)

Extend `PARSER.md` §8 with:

```markdown
### Range Metadata (Toxic Mode)

When using the Toxic tokenizer, Spitfire attaches a `:range` key to AST node
metadata:

- **Format**: `{:range, {{start_line, start_col}, {end_line, end_col}}}`
- **Coordinates**: 1-based (`line`, `column`), representing a half-open
  interval `[start, end)`.
- **Invariants** (guaranteed for all inputs):
  - Parent ranges contain the ranges of all children.
  - Sibling ranges do not overlap (they may touch).
  - The root node’s range spans the entire document (from parser start to
    logical EOF).

Range data is derived from Toxic’s ranged token metadata. Even in
error-tolerant mode, Toxic emits structural tokens for missing delimiters
(`)`, `]`, `}`, `end`, etc.), sometimes with zero-width ranges; Spitfire uses
these tokens to keep ranges consistent.

Example:

```elixir
{:ok, {:+, meta, [lhs, rhs]}} =
  Spitfire.parse("1 + 2", tokenizer: :toxic)

meta[:range]
# => {{1, 1}, {1, 6}}
```

Legacy (non-Toxic) mode does not attach `:range`, preserving the original AST
shape and metadata.
```

---

With these refinements:
- Range computation is **exact**, including in error‑recovery scenarios,
  thanks to Toxic’s structural tokens.
- Legacy behavior remains unchanged.
- The implementation path is phased and test‑driven. 

