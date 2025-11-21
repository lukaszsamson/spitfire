# AST Range Metadata with Toxic

This plan describes how to leverage **Toxic’s ranged token metadata** to attach **non‑overlapping, tree‑consistent ranges** to Spitfire’s AST nodes, with special attention to literals rendered via `literal_encoder/2`.

The end state:
- Every AST 3‑tuple `{form, meta, args}` produced in **Toxic mode** carries a **range meta** spanning all tokens for that node.
- A parent node’s range strictly **contains or touches** all of its children (no gaps inside the subtree).
- **Sibling ranges do not overlap** (they form a left‑to‑right tiling of the document segment covered by the parent).
- The **root node**’s range spans the whole input document.
- `literal_encoder` receives range‑aware meta (including for list/tuple/map literals).

All of this must be implemented without breaking existing “AST parity with `Code.string_to_quoted/2`” tests.

---

## 1. Data Model & Invariants

### 1.1 Range Representation

- Introduce a new meta entry on AST nodes:

  ```elixir
  {:range, {{start_line, start_col}, {end_line, end_col}}}
  ```

  where coordinates are **1‑based** and use Toxic’s semantics:
  - `start` is the position of the **first character** of the node.
  - `end` is the position **just after** the last character (half‑open interval `[start, end)`).

- Keep existing `:line` / `:column` entries as the **start position** so existing tools keep working.
- Do **not** change or remove existing meta entries such as `:closing`, `:newlines`, `:end_of_expression`, `:do`, `:end`, etc.; `:range` is additive.

### 1.2 Tree Invariants

For all AST nodes built in Toxic mode:

- **Parent containment**
  - For every node `N` with children `C1..Cn`:
    - `range(N).start <= range(Ci).start` for all `i`.
    - `range(Ci).end <= range(N).end` for all `i`.
  - Equality at boundaries is allowed (children may start/end exactly at parent edges).

- **Sibling non‑overlap**
  - For siblings `Ci`, `Cj` where `i < j`:
    - `range(Ci).end <= range(Cj).start`.
  - Equality is allowed (siblings may “touch” but not overlap).

- **Root coverage**
  - For the root AST returned by `Spitfire.parse/2`:
    - `range(root).start` = `{start_line, start_column}` from parser opts (default `{1, 1}`).
    - `range(root).end` = **logical end of file**:
      - Either computed from Toxic’s last token span if available, or
      - Derived from the source string length (see §5.3).

- **Error nodes**
  - Error sentinel nodes like `{:__block__, [error: true | meta], []}` still get a `:range`, but containment / sibling rules may be **best‑effort** when synthetic tokens are injected.

---

## 2. Low‑Level Span Helpers

All of these live in `lib/spitfire.ex` near `current_meta/1` / `current_eoe/1`.

### 2.1 Token Span Extraction

Implement helper(s) that **do not change existing behavior** but expose Toxic spans:

```elixir
defp token_span({_, {{sl, sc}, {el, ec}, _extra}}), do: {{sl, sc}, {el, ec}}
defp token_span({_, {{sl, sc}, {el, ec}, _extra}, _}), do: {{sl, sc}, {el, ec}}

# Legacy meta fallback – approximate single-column width so code keeps working,
# but we will *not* rely on this for precise invariants in legacy mode.
defp token_span({_, {line, col, _extra}}), do: {{line, col}, {line, col + 1}}
defp token_span({_, {line, col, _extra}, _}), do: {{line, col}, {line, col + 1}}

defp token_span(_), do: nil
```

Also add a simple position comparison API:

```elixir
defp pos_min({l1, c1}, {l2, c2}), do: if l1 < l2 or (l1 == l2 and c1 <= c2), do: {l1, c1}, else: {l2, c2}
defp pos_max({l1, c1}, {l2, c2}), do: if l1 > l2 or (l1 == c2 and c1 >= c2), do: {l1, c1}, else: {l2, c2}
```

### 2.2 AST Range Utilities

Helpers for reading and writing ranges on AST meta:

```elixir
defp meta_range(meta) do
  case Keyword.get(meta, :range) do
    {{_sl, _sc}, {_el, _ec}} = r -> r
    _ -> nil
  end
end

defp put_meta_range(meta, {{sl, sc}, {el, ec}}) do
  meta
  |> Keyword.delete(:range)
  |> List.insert_at(0, {:range, {{sl, sc}, {el, ec}}})
end
```

And a primitive for building ranges from existing spans:

```elixir
defp merge_ranges(ranges) do
  ranges
  |> Enum.filter(& &1)
  |> case do
    [] -> nil
    [single] -> single
    [first | rest] ->
      Enum.reduce(rest, first, fn {sl2, sc2} = s2, {{sl1, sc1}, {el1, ec1}} = acc ->
        {{pos_min({sl1, sc1}, s2 |> elem(0)), pos_max({el1, ec1}, s2 |> elem(1))}}
      end)
  end
end
```

> Implementation note: the exact `Enum.reduce/3` shape can be refined later; the key point is to define a canonical way to compute a parent’s range from children and/or boundary tokens.

---

## 3. Leaf & Literal Ranges

This phase gives **all literal and leaf nodes** (numbers, atoms, variables, list/tuple/map literals via `literal_encoder`) proper ranges derived from Toxic tokens.

### 3.1 `current_meta/1` (minimal change)

Keep `current_meta/1`’s current contract (returns only `[line: ..., column: ...]` plus existing extras), but **do not** add `:range` there. Doing so would embed only the first‑token span, which is insufficient for composite nodes and would be misleading.

`current_meta/1` remains the “start‑position + extras” constructor.

### 3.2 `encode_literal/3`

Today, `encode_literal/3` normalizes meta and passes `line`/`column` plus `additional_meta/2` into `literal_encoder/2`. For Toxic’s ranged meta, we currently drop the end position entirely.

Change `encode_literal/3` so that when given a Toxic range:

```elixir
defp encode_literal(%{literal_encoder: encoder} = parser, literal,
                    {{sl, sc}, {el, ec}, _extra} = raw_meta)
     when is_function(encoder) do
  base_meta = [line: sl, column: sc]
  meta = additional_meta(literal, parser) ++ [range: {{sl, sc}, {el, ec}} | base_meta]

  case encoder.(literal, meta) do
    {:ok, ast} -> ast
    {:error, reason} -> Logger.error(reason); literal
  end
end
```

Keep the legacy `{line, col, extra}` clause as‑is (no `:range`), so **range metadata is only guaranteed in Toxic mode**.

### 3.3 List / Tuple / Map Literals via `literal_encoder`

`parse_list_literal/1`, `parse_tuple_literal/1`, `parse_map_literal/1`, and struct/bitstring literals already rely on `encode_literal/3` with:
- An **opening meta** (`orig_meta`) from the opening token (`[`, `{`, `%{`, `<<`).
- A **closing meta** fetched by `additional_meta/2` via `current_meta/1` once the closing token is reached.

Implementation steps:

1. Extend `additional_meta/2` for `is_list/1` and `is_tuple/1` literals:

   - Compute `open_span` from the **opening token** (available via `orig_meta` or `parser.start_line/start_column` and `token_span/1`).
   - Compute `close_span` from the **closing token** using `token_span(parser.current_token)` after advancing.
   - Set the container’s `:range` to `{{open_sl, open_sc}, {close_el, close_ec}}`.
   - Continue to store `closing: [line: ..., column: ...]` inside meta for compatibility.

2. Ensure `literal_encoder` sees **both**:
   - `line` / `column` (start),
   - `range` (full literal span).

This satisfies the requirement that “Even AST literals like lists or tuples should have meta with range when rendered with literal_encoder”.

### 3.4 Non‑literal Leaf Nodes

For leaf AST forms not going through `encode_literal/3` (identifiers, aliases, booleans without literal_encoder, etc.), attach `:range` directly from the current token:

- `parse_lone_identifier/1`:
  - After computing `meta = current_meta(parser) |> push_delimiter(token_meta)`, compute `span = token_span(parser.current_token)` and add `:range` via `put_meta_range/2`.
- `parse_alias/1` and any similar leaf `parse_*` that produce `{form, meta, []}` or `{form, meta, nil}` where the node corresponds exactly to the current token.

For these nodes, `range` is simply the token’s span.

---

## 4. Composite Nodes & Parent Ranges

Once leaves and literal containers carry ranges, we can build parent ranges **purely from AST**, without needing to track token spans globally.

### 4.1 General Pattern

For any AST node `{form, meta, args}` built in the parser:

1. Determine candidate ranges:
   - `child_ranges = Enum.map(args, &ast_range/1)` where `ast_range/1` reads `:range` from child meta or returns `nil` for non‑3‑tuples.
   - `boundary_ranges` from opening/closing tokens when available:
     - Opening tokens: `token_span(parser.current_token)` captured at function entry.
     - Closing tokens: `token_span` of the token whose `current_meta/1` is stored in a `:closing` meta entry.
2. Compute `node_range = merge_ranges(child_ranges ++ boundary_ranges)`.
3. If `node_range` is not `nil`, update `meta = put_meta_range(meta, node_range)`.
4. Return `{form, meta, args}`.

### 4.2 Places to Apply

We don’t need to touch every clause individually; instead, identify **families of constructors** and wrap them with a small helper.

#### 4.2.1 Binary and Unary Operators

Functions:
- `parse_infix_expression/2`
- `parse_prefix_expression/1`
- `parse_range_expression/1` and `/2`
- `parse_pipe_op/2`
- Other specific operator parsers (`parse_assoc_op/2`, etc.).

Plan:
- After each operator AST is built (`{op, meta, [lhs, rhs]}` or `{op, meta, [rhs]}`), call a helper:

  ```elixir
  defp attach_op_range({op, meta, args} = ast) do
    child_ranges = Enum.map(args, &ast_range/1)
    # Optional: include operator token span via token_span of the operator token.
    range = merge_ranges(child_ranges)
    {op, put_meta_range(meta, range), args}
  end
  ```

  Then replace the final return with `{attach_op_range(ast), parser}`.

#### 4.2.2 Calls and Dots

Functions:
- `parse_call_expression/2`
- `parse_dot_expression/2`
- `parse_dot_call_expression/2`
- `parse_identifier/1` when it constructs a call `{callee, meta, args}`.

Plan:
- For each call node `{callee, meta, args}` (with potential `:closing` meta):
  - `callee_range = ast_range(callee)` or from token span if `callee` is a bare atom/tuple.
  - `arg_ranges = Enum.map(args, &ast_range/1)`.
  - `closing_range` from the closing `")"` token via `token_span` (using the `closing` meta’s line/column to re‑locate if needed; in Toxic, we can often capture it directly in the parsing function).
  - `meta = put_meta_range(meta, merge_ranges([callee_range | arg_ranges] ++ [closing_range]))`.

This ensures calls cover everything from callee through the closing paren (or last argument for no‑parens calls).

#### 4.2.3 Containers: Lists, Tuples, Maps, Structs, Bitstrings

Most container literals go through:
- `parse_list_literal/1` → `encode_literal/3` (handled in §3.3).
- `parse_tuple_literal/1` and `parse_map_literal/1` → similar pattern.
- Bitstrings: `parse_bitstring/1`.

For containers **not using `literal_encoder`** (e.g., bitstring segments, maybe some struct forms), follow the same pattern as for calls:
- Use opening token span + last element span + closing token span to derive `:range`.

#### 4.2.4 Blocks and Special Forms

Key places:
- `parse_grouped_expression/1` for `( ... )` groupings.
- `parse_do_block/2` (and `parse_do_block/1` if present).
- `parse_anon_function/1` (`fn -> ... end`).
- `build_block_nr/2` when it returns `{:__block__, meta, exprs}`.

Plan:
- For `{:__block__, meta, exprs}`:
  - If `exprs` non‑empty: `range = merge_ranges(Enum.map(exprs, &ast_range/1))`.
  - If empty (e.g., whole file is empty): use a degenerate range of `{start_pos, start_pos}` (or file start to file start).
  - Attach via `put_meta_range/2`.

- For `fn` / `do` blocks:
  - Use:
    - `fn`/`do` token span as opening boundary,
    - `end` token span as closing boundary,
    - plus child clause ranges for containment.

---

## 5. Root Node Range

### 5.1 Where to Hook

`parse/2` calls:

```elixir
parser = code |> new(opts) |> next_token() |> next_token()
...
case parse_program(parser) do
  {ast, %{errors: []}} -> {:ok, ast}
  ...
end
```

`parse_program/1` returns `{ast, parser}` where `ast` is either a single expression or a `{:__block__, meta, exprs}` built by `build_block_nr/2`.

### 5.2 Strategy

1. After `parse_program/1` returns, compute the **root range**:
   - `start = {parser.start_line, parser.start_column}`.
   - `end`:
     - Preferred: track `parser.last_span` (updated whenever we *consume* a real token in Toxic mode via `token_span/1`), then use its end position.
     - Fallback: if `last_span` is `nil` (empty file), use `{start_line, start_column}`.
2. Attach `:range` to the root node’s meta via `put_meta_range/2`.

This can be done in `parse/2` before returning `{:ok, ast}` / `{:error, ast, errors}`.

### 5.3 Alternative: Compute End from Source

If `parser.last_span` is tricky to maintain, we can instead:

- Store `source` (or at least its length and last line offsets) in the parser struct.
- Compute `(end_line, end_col)` by scanning the string once at `new/2` time.

For now the plan is:
- **Prefer `last_span` tracking**, as we already pay the cost of walking tokens.
- Fall back to string‑based computation only if needed.

---

## 6. Error Recovery & Synthetic Tokens

Spitfire injects synthetic closers like `:fake_closing_bracket` in several places (e.g. `parse_list_literal/1` error branches).

Plan:

- **Never derive ranges directly from synthetic tokens** (their positions are fake).
- For a container missing a closer:
  - Use opening token span and **last real child’s range** to define the container range:

    ```elixir
    # pseudo
    open_span = token_span(open_token)
    last_child = List.last(children_with_ranges)
    range = merge_ranges([open_span, ast_range(last_child)])
    ```

  - Keep error messages intact (no changes to `put_error/2` calls).

- This guarantees:
  - Parent range still contains children.
  - Siblings remain non‑overlapping (even if some containers are synthetically “cut short”).

We can document that range fidelity is **best‑effort** in the presence of recovery, but structurally consistent.

---

## 7. Testing Strategy

All range tests run with **Toxic enabled**:

```elixir
setup do
  original = Application.get_env(:spitfire, :tokenizer, :legacy)
  Application.put_env(:spitfire, :tokenizer, :toxic)
  on_exit(fn -> Application.put_env(:spitfire, :tokenizer, original) end)
end
```

### 7.1 Keep Existing Parity Tests Intact

Current tests in:
- `test/spitfire_legacy_test.exs`
- `test/spitfire_toxic_test.exs`

assert:

```elixir
assert Spitfire.parse(code) == s2q(code)
```

and have a “literal encoder” test that uses:

```elixir
encoder = fn l, m -> {:ok, {:__literal__, m, [l]}} end
```

Adding `:range` would break these equalities.

Plan:

1. **Do not change AST shape or meta keys in legacy mode.**
2. For the **literal encoder parity test only**, change the encoder to drop `:range`:

   ```elixir
   encoder = fn literal, meta ->
     meta = Keyword.delete(meta, :range)
     {:ok, {:__literal__, meta, [literal]}}
   end
   ```

   - On the `Code.string_to_quoted/2` side this is a no‑op (no `:range` key).
   - On the Spitfire side it removes `:range` from the returned AST, preserving equality.

3. Keep all other parity tests unchanged; they compare ASTs **without a literal_encoder**, which will still match core (we only add `:range` in Toxic mode and only on nodes we construct; for the Code side, there is no `:range`).

### 7.2 New Range‑Focused Tests

Add a new `describe "ranges"` section, preferably in `test/spitfire_toxic_test.exs` (or a new `test/spitfire_ranges_test.exs`), with targeted unit tests.

#### 7.2.1 Literal Encoder Range Tests

Use a **range‑aware encoder** that captures and asserts on meta:

```elixir
encoder = fn literal, meta ->
  send(self(), {:lit_meta, literal, meta})
  {:ok, {:__literal__, meta, [literal]}}
end
```

Example tests:

- **List literal**

  ```elixir
  code = "[1, 23]"
  {:ok, ast} = Spitfire.parse(code, literal_encoder: encoder)

  assert_received {:lit_meta, 1, meta1}
  assert meta1[:range] == {{1, 2}, {1, 3}}

  assert_received {:lit_meta, 23, meta2}
  assert meta2[:range] == {{1, 5}, {1, 7}}

  assert_received {:lit_meta, [_, _], list_meta}
  assert list_meta[:range] == {{1, 1}, {1, 8}}
  ```

- **Tuple literal**, **map**, **bitstring**, multi‑line heredocs/sigils, verifying that container ranges span open → close.

#### 7.2.2 Composite Node Range Tests

Use ordinary parsing (no literal_encoder) and pattern‑match AST:

- **Binary expression**

  ```elixir
  code = "1 + 23"
  {:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse(code)

  assert meta[:range] == {{1, 1}, {1, 7}}
  assert ast_range(lhs) == {{1, 1}, {1, 2}}
  assert ast_range(rhs) == {{1, 5}, {1, 7}}
  ```

- **Call with parens**: `"foo(1, 23)"` → call range spans from `f` through `)`.
- **`fn` and `do` blocks**: confirm ranges include the `fn/do` keyword through `end`.

#### 7.2.3 Structural Invariant Tests

Implement a helper:

```elixir
defp assert_range_tree(ast) do
  walk(ast, nil)
end

defp walk({_, meta, args} = node, parent_range) do
  range = meta_range(meta)
  assert range != nil

  if parent_range do
    assert range_start(range) >= range_start(parent_range)
    assert range_end(range) <= range_end(parent_range)
  end

  child_ranges =
    args
    |> Enum.map(&walk(&1, range))
    |> Enum.filter(& &1)

  # sibling non-overlap
  child_ranges
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.each(fn [r1, r2] ->
    assert range_end(r1) <= range_start(r2)
  end)

  range
end

defp walk(list, parent_range) when is_list(list) do
  Enum.each(list, &walk(&1, parent_range))
  nil
end

defp walk(_other, _parent), do: nil
```

Tests:
- Run `assert_range_tree(ast)` on a variety of short programs:
  - Single expression.
  - Multiple top‑level expressions (so root is `{:__block__, ...}`).
  - Nested containers and calls.
  - A few malformed examples (missing closers) to ensure traversal doesn’t crash and invariants still hold as much as possible.

#### 7.2.4 Root Range Tests

Explicit tests that the root range spans the entire document:

- Simple single‑line code:

  ```elixir
  code = "1 + 23\n"
  {:ok, {_, meta, _} = ast} = Spitfire.parse(code)
  assert meta[:range] == {{1, 1}, {2, 1}}  # assuming end is at start of line 2
  ```

- Multi‑line with trailing blank lines or comments: confirm `end` matches the logical end (line/column) of the string.

---

## 8. Rollout & Compatibility Notes

- **Scope**: range metadata is **only guaranteed in Toxic mode**. Legacy mode keeps existing behavior and meta shape; legacy tests remain unchanged except for the literal_encoder parity encoder tweak (which is backward‑compatible).
- **API contract**:
  - New key: `:range` on AST meta is **stable and documented** once implemented.
  - Existing users that ignore unknown meta keys are unaffected.
- **Documentation**:
  - Extend `PARSER.md` §8 (“Comment & metadata preservation”) with a short subsection “Range metadata in Toxic mode” describing:
    - `:range` shape and semantics.
    - Parent/child and sibling invariants.
    - Root coverage guarantee.

Once these steps are implemented and tested, Spitfire will expose precise, non‑overlapping AST ranges aligned with Toxic’s token spans, suitable for IDE tooling, selection mapping, and incremental parsing features.

