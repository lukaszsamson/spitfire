# Review of RANGES_PLAN.md

The plan is comprehensive and well-structured. It correctly identifies the key requirements for integrating Toxic's range metadata into Spitfire's AST while maintaining backward compatibility.

Here are a few suggestions and clarifications to ensure a smooth implementation:

## 1. Parser State Updates

The plan mentions tracking `parser.last_span` to determine the end of the root node. Since `Spitfire` uses a simple Map for its state (in `defp new`), you will need to:

- **Initialize `last_span`**: Add `last_span: nil` to the map returned by `defp new/2` (around line 3373).
- **Update `last_span`**: In `defp next_token/1`, before overwriting `current_token`, extract its span and update `last_span`.
  ```elixir
  defp next_token(%{stream: stream} = parser) do
    # Capture span of the token we are about to move past
    span = token_span(parser.current_token)
    last_span = if span, do: span, else: parser[:last_span]
    
    current = parser.peek_token
    {tok, stream1} = Spitfire.TokenStream.next(stream)
    
    %{parser | stream: stream1, current_token: current, peek_token: tok, fuel: 150, last_span: last_span}
  end
  ```
  *Note: Handle the initial case where `current_token` is nil.*

## 2. Interpolated Strings and Sigils

The plan covers "Containers" and "Composite Nodes", but interpolated strings (and sigils/heredocs) are a special case of composite nodes that often don't go through the standard `parse_call` or `parse_block` paths.

- Ensure that `parse_string/1`, `parse_heredoc/1`, and `parse_sigil/1` (and their linearized counterparts) attach ranges that cover the **entire** construct, including delimiters (`"`...`"`, `"""`...`"""`, `~s|`...`|`).
- For interpolated segments, the range should span from the start delimiter to the end delimiter.

## 3. `merge_ranges` Signature

In section 2.2, the `merge_ranges` reducer signature in the pseudo-code seems to mix types:
```elixir
Enum.reduce(rest, first, fn {sl2, sc2} = s2, {{sl1, sc1}, {el1, ec1}} = acc -> ...
```
It should likely match the range tuple structure:
```elixir
Enum.reduce(rest, first, fn {{sl2, sc2}, {el2, ec2}}, {{sl1, sc1}, {el1, ec1}} -> ...
```

## 4. Legacy Mode Safety

The plan correctly emphasizes not changing legacy mode. However, the proposed `token_span` fallback for legacy tokens:
```elixir
defp token_span({_, {line, col, _extra}}), do: {{line, col}, {line, col + 1}}
```
**Risk**: If `token_span` returns a value for legacy tokens, and you use it in `attach_op_range` or similar helpers, you will inadvertently add `:range` metadata to the AST in legacy mode, breaking the "no AST change" requirement.

**Recommendation**: 
- Make `token_span` return `nil` for legacy tokens (match on 3-tuple meta vs Toxic's nested tuple).
- Or, ensure `put_meta_range` checks if the range came from a Toxic token before attaching it.
- Simplest fix: `defp token_span({_, {_, _, _}}), do: nil` (or just let it fall through to `nil` catch-all).

## 5. `end` Token for Blocks

For `do`...`end` blocks, ensure you capture the `end` token's span before it is consumed. `parse_do_block` typically consumes `end`. You might need to peek at it or capture it from the return of `expect(parser, :end)`.

## Summary

The plan is **correct** and ready for implementation with the minor additions above.
