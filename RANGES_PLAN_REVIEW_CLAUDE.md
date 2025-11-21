# Review of RANGES_PLAN.md

## Overall Assessment

The plan is **well-structured and technically sound**. It demonstrates a deep understanding of both the Toxic tokenizer's ranged metadata and Spitfire's AST construction patterns. The phased approach (low-level helpers → leaves → composites → root) is logical and minimizes risk.

## Strengths

1. **Clear invariants**: The tree containment and sibling non-overlap rules are precisely defined with concrete examples.

2. **Backward compatibility focus**: The plan correctly prioritizes not breaking existing tests by making ranges Toxic-only and adjusting the literal encoder test cleverly.

3. **Comprehensive token handling**: The plan accounts for legacy vs. Toxic meta formats, synthetic tokens, error recovery, and interpolation.

4. **Testability**: The testing strategy is excellent, especially the structural invariant walker and the separation of parity tests from range tests.

## Issues & Gaps

### Critical Issues

#### 1. **Meta Format Inconsistency in `current_meta/1`** (§3.1)

**Problem**: The plan states `current_meta/1` should remain unchanged and "return only `[line: ..., column: ...]`". However, looking at the actual implementation (lines 3651-3726 in spitfire.ex), `current_meta/1` already handles both legacy `{line, col, extra}` and Toxic ranged `{{line, col}, {end_line, end_col}, extra}` formats. It extracts only the **start position**, discarding the end position from Toxic tokens.

**Issue**: The plan doesn't acknowledge that `current_meta/1` is already "lossy" for Toxic ranges. This is correct for its current purpose (providing start position), but means we need a **parallel helper** to extract full ranges.

**Recommendation**: Add a new section (2.1a) introducing:

```elixir
defp token_range(token) do
  case token do
    {_, {{sl, sc}, {el, ec}, _}} -> {{sl, sc}, {el, ec}}
    {_, {{sl, sc}, {el, ec}, _}, _} -> {{sl, sc}, {el, ec}}
    {_, {line, col, _}} -> {{line, col}, {line, col + 1}}  # legacy fallback
    {_, {line, col, _}, _} -> {{line, col}, {line, col + 1}}
    _ -> nil
  end
end
```

This helper extracts ranges **directly from tokens** without relying on `current_meta/1`.

#### 2. **Ambiguity in `encode_literal/3` Signature** (§3.2)

**Problem**: The plan shows:

```elixir
defp encode_literal(%{literal_encoder: encoder} = parser, literal,
                    {{sl, sc}, {el, ec}, _extra} = raw_meta)
```

But looking at the current implementation (line 3847-3856), `encode_literal/3` takes a **meta tuple** as its third argument, **not** `parser.current_token`. The function is called like:

```elixir
encode_literal(parser, literal, meta)
```

where `meta` comes from `current_meta(parser)` which is already a keyword list `[line: ..., column: ...]`.

**Current Issue**: The third parameter is **already processed metadata** (keyword list), not the raw token. To access the full range, we need to pass `parser.current_token` separately or change the signature.

**Recommendation**: Revise §3.2 to:

1. **Option A (minimal change)**: Add a helper that constructs range-aware meta:

   ```elixir
   defp meta_with_range(parser) do
     base = current_meta(parser)  # [line: sl, column: sc]
     case token_range(parser.current_token) do
       {{sl, sc}, {el, ec}} -> Keyword.put(base, :range, {{sl, sc}, {el, ec}})
       _ -> base
     end
   end
   ```

   Then update call sites to use `encode_literal(parser, literal, meta_with_range(parser))`.

2. **Option B (cleaner)**: Change `encode_literal/3` to take the parser only:

   ```elixir
   defp encode_literal(parser, literal) do
     meta = meta_with_range(parser)
     meta = additional_meta(literal, parser) ++ meta
     # ... rest of function
   end
   ```

   This centralizes range logic.

**I recommend Option B** for consistency.

#### 3. **Closing Token Range Capture** (§3.3, §4.2.2)

**Problem**: The plan says to "compute `close_span` from the closing token using `token_span(parser.current_token)` after advancing." However, in many parsing functions, **the closing token is consumed before the AST is constructed**, and its meta is stored in `:closing` as a keyword list `[line: ..., column: ...]` (see line 2672, 2692, etc.).

**Issue**: By the time we build the AST, we've already **lost** the closing token's full range because `current_meta/1` only extracted the start position.

**Recommendation**: Add to §3.3:

- **Before** calling `next_token()` on a closing delimiter, capture its full range:

  ```elixir
  closing_range = token_range(parser.current_token)
  parser = next_token(parser)
  ```

- Store this in `additional_meta/2` or pass it explicitly to `encode_literal/3`.

- Update `additional_meta/2` for lists/tuples to return `[closing: closing_meta, closing_range: closing_range]`.

This is a **significant refactor** but necessary for accurate container ranges.

#### 4. **Root Range Tracking Mechanism** (§5.2)

**Problem**: The plan proposes tracking `parser.last_span` but doesn't specify:
- When/how to update it (after every `next_token()`? Only for real tokens?)
- How to handle empty files
- What about error recovery synthetic tokens

**Recommendation**: Add implementation details to §5.2:

```elixir
defp next_token(parser) do
  parser = %{parser | current_token: parser.peek_token}

  # Update last_span from real (non-synthetic) tokens
  parser = case token_range(parser.current_token) do
    {{_sl, _sc}, {el, ec}} = range when parser.current_token not in [:eof] ->
      %{parser | last_span: range}
    _ ->
      parser
  end

  # ... rest of next_token
end
```

Initialize `last_span: nil` in `new/2`, and in `parse/2` compute root end as:

```elixir
root_end = case parser.last_span do
  {{_, _}, {el, ec}} -> {el, ec}
  _ -> {parser.start_line, parser.start_column}  # empty file
end
```

### Major Gaps

#### 5. **Missing: Operator Token Ranges** (§4.2.1)

**Problem**: The plan says "Optional: include operator token span via token_span of the operator token" but doesn't explain **how** to capture it. In Spitfire's Pratt parser, when we parse an infix expression:

```elixir
defp parse_infix_expression(parser, lhs) do
  operator_meta = current_meta(parser)  # captures operator's START position
  operator = current_token(parser)
  parser = next_token(parser)
  {rhs, parser} = parse_expression(parser, precedence)
  {{operator, operator_meta, [lhs, rhs]}, parser}
end
```

The operator's **full range** is needed to accurately span `lhs <op> rhs`.

**Recommendation**: Add to §4.2.1:

- Capture operator range before advancing:

  ```elixir
  operator_range = token_range(parser.current_token)
  operator_meta = current_meta(parser)
  ```

- When computing parent range:

  ```elixir
  defp attach_op_range({op, meta, [lhs, rhs]} = ast, op_range) do
    child_ranges = [ast_range(lhs), op_range, ast_range(rhs)]
    range = merge_ranges(child_ranges)
    {op, put_meta_range(meta, range), [lhs, rhs]}
  end
  ```

This ensures operators are included in the parent span.

#### 6. **Missing: Interpolation Handling** (§2, §4)

**Problem**: String interpolation (e.g., `"foo#{bar}"`) creates nested ASTs (lines 2756-2762). The plan doesn't address:
- How to compute ranges for `begin_interpolation`/`end_interpolation` tokens
- Whether interpolated expressions should contribute to the string's range
- How `:from_interpolation` meta interacts with `:range`

**Recommendation**: Add a new §4.2.5 "Interpolation":

- The outer string's range should span its delimiters (already covered by §3.2).
- Interpolated expressions inside get their own ranges via recursive `parse_expression/1`.
- The `{:"::", meta, [to_string_call, binary]}` wrapper should have a range covering the `#{...}` span.
- **Do not merge** interpolation ranges into the literal's `:range`; the literal's range is its delimiters, period.

#### 7. **Missing: Anonymous Function Clauses** (§4.2.4)

**Problem**: Anonymous functions have multiple clauses separated by `;` or newlines:

```elixir
fn
  :ok -> 1
  :error -> 2
end
```

The plan mentions `parse_anon_function/1` should use `fn` and `end` token spans, but doesn't specify:
- How to compute ranges for individual clauses `{:->, meta, [pattern, body]}`
- Whether the function's range includes all clauses

**Recommendation**: Add to §4.2.4:

- Each clause's range: `merge_ranges([pattern_ranges, arrow_range, body_range])`
- The `{:fn, meta, clauses}` range: `merge_ranges([fn_token_range] ++ clause_ranges ++ [end_token_range])`

#### 8. **Incomplete: Error Recovery Details** (§6)

**Problem**: The plan says "use opening token span and last real child's range" but many error cases have **no children** (e.g., `[` followed by `]` with a syntax error in between).

**Recommendation**: Expand §6:

- **No children case**: Use opening token range only:

  ```elixir
  range = merge_ranges([open_span])  # degenerate but valid
  ```

- **Synthetic tokens**: Document that error nodes `{:__block__, [error: true | meta], []}` may have `:range` set to the error location (from the token that triggered the error).

- **Best-effort guarantee**: State explicitly that range invariants (containment, non-overlap) are **guaranteed** for well-formed code, but **best-effort** when errors are present.

### Minor Issues

#### 9. **Typo in `pos_max/2`** (§2.1)

Line 84 has:

```elixir
defp pos_max({l1, c1}, {l2, c2}), do: if l1 > l2 or (l1 == c2 and c1 >= c2), do: ...
```

Should be `(l1 == l2 and c1 >= c2)` (comparing `l1` to `l2`, not `l1` to `c2`).

#### 10. **Precedence of `:range` in Meta** (§1.1)

The plan says "insert at position 0" via `List.insert_at(0, ...)`. This is good for visibility, but `Keyword.put/3` would be simpler and idiomatic. Consider:

```elixir
defp put_meta_range(meta, range) do
  Keyword.put(meta, :range, range)  # overwrites if exists
end
```

Unless order matters for some tool (document if so).

#### 11. **`build_block_nr/2` Handling** (§4.2.4)

The plan mentions this function but doesn't show where it's called or how to attach ranges to the resulting `{:__block__, meta, exprs}`. Need to specify:

- Who calls `build_block_nr/2`? (Answer: `parse_program/1`, line 216)
- Where to attach range? (Answer: in `parse/2` after `parse_program/1` returns, before returning `{:ok, ast}`)

Add this detail to §5.1.

## Missing Sections

### 12. **Phased Rollout Strategy**

The plan says "implement and test" but doesn't specify an incremental rollout:

1. **Phase 0**: Add low-level helpers (§2) + tests
2. **Phase 1**: Leaves and literals (§3) + literal encoder tests
3. **Phase 2**: Binary/unary operators (§4.2.1) + tests
4. **Phase 3**: Calls and containers (§4.2.2, §4.2.3) + tests
5. **Phase 4**: Blocks and special forms (§4.2.4) + tests
6. **Phase 5**: Root range (§5) + root tests
7. **Phase 6**: Structural invariant tests (§7.2.3)

Add this as §9 "Implementation Phases" with explicit dependencies between phases.

### 13. **Performance Considerations**

The plan doesn't mention performance impact:
- Extra `token_range/1` calls per token
- `merge_ranges/1` complexity (linear in child count)
- Memory overhead of `:range` entries

Add a brief §10 "Performance Notes":
- Expected overhead: ~5-10% (one extra pattern match per token)
- Memory: +16 bytes per AST node (two tuples)
- Mitigation: Lazy computation? (No, upfront is simpler)

### 14. **Documentation**

The plan mentions updating `PARSER.md` §8 but doesn't show the actual doc text. Add an Appendix A with:

```markdown
### Range Metadata (Toxic Mode)

When using the Toxic tokenizer, Spitfire attaches a `:range` key to AST node metadata:

- **Format**: `{:range, {{start_line, start_col}, {end_line, end_col}}}`
- **Coordinates**: 1-based, half-open interval `[start, end)`
- **Guarantee**: Parent ranges contain all children; siblings do not overlap
- **Root**: Spans entire document from `{1, 1}` to logical EOF

Example:
```elixir
{:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse("1 + 2", tokenizer: :toxic)
meta[:range]  # => {{1, 1}, {1, 6}}
```
```

## Recommendations Summary

1. **Add `token_range/1` helper** (§2.1a) – extracts ranges from raw tokens
2. **Refactor `encode_literal/3`** (§3.2) – change signature to take parser only
3. **Capture closing ranges explicitly** (§3.3) – before consuming closing tokens
4. **Specify `last_span` update logic** (§5.2) – in `next_token/1`
5. **Add operator range capture** (§4.2.1) – before advancing past operator
6. **Add interpolation section** (§4.2.5) – clarify nested range handling
7. **Add anon function clause detail** (§4.2.4) – per-clause ranges
8. **Expand error recovery** (§6) – handle no-children and synthetic token cases
9. **Fix `pos_max/2` typo** (§2.1)
10. **Clarify `build_block_nr/2` call site** (§5.1)
11. **Add phased rollout plan** (§9)
12. **Add performance notes** (§10)
13. **Add documentation text** (Appendix A)

## Verdict

**The plan is fundamentally correct and ready to execute with the above refinements.** The main risks are:

1. **Closing token metadata loss** – requires careful refactoring of `additional_meta/2` and call sites
2. **Test maintenance** – ensuring parity tests don't break requires discipline

With the recommended additions, this plan will successfully deliver precise, tree-consistent ranges for Spitfire's AST in Toxic mode.

---

## Action Items for Plan Revision

1. Add §2.1a: `token_range/1` helper
2. Revise §3.2: Change `encode_literal/3` to take parser only
3. Expand §3.3: Add closing range capture protocol
4. Add §4.2.1 detail: Operator range capture before `next_token()`
5. Add §4.2.5: Interpolation range handling
6. Expand §4.2.4: Anonymous function clause ranges
7. Expand §6: Error recovery edge cases (no children, synthetic tokens)
8. Fix §2.1: `pos_max/2` typo
9. Clarify §5.1: Where `build_block_nr/2` is called
10. Add §9: Phased implementation plan
11. Add §10: Performance considerations
12. Add Appendix A: Documentation text for PARSER.md

Once these are addressed, the plan will be **production-ready** for implementation.
