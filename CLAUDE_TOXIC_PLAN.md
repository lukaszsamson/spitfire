# Spitfire + Toxic Integration Implementation Plan

## Overview
Replace Spitfire's batch tokenizer (`:spitfire_tokenizer.erl`) with Toxic's streaming tokenizer to achieve:
- True streaming tokenization (one token at a time)
- Better error recovery and tolerant parsing
- Support for incremental parsing
- Improved IDE integration capabilities

## Phase 0: Baseline Understanding ✓
- Review PARSER.md and HIGH_LEVEL_TOKENIZER_PLAN.md
- Understand current parser token API in lib/spitfire.ex
- Study Toxic streaming API and token formats
- Identify token shape differences and conversion needs

## Phase 1: Compatibility Adapter (Parser Unchanged)

### 1.1 Replace Token List with Token Stream
**File**: `lib/spitfire.ex`

- Replace `tokens: tokenize(code, opts)` with `stream: Toxic.TokenStream.new(code, line, column, opts)`
- Remove `current_token` and `peek_token` fields (stream handles this)
- Keep `fuel`, `nesting`, `literal_encoder`, `errors`

### 1.2 Refactor Token Operations
**File**: `lib/spitfire.ex`

Replace all token manipulation functions:
- `next_token/1` � Use `Toxic.TokenStream.next/1`
- `current_token/1` � Track in parser state after consuming
- `peek_token/1` � Use `Toxic.TokenStream.peek/1`
- `peek_token_type/1` � Adapt to Toxic's token format

## Phase 2: Token Format Adaptation

### 2.1 Create Token Adapter Module
**New File**: `lib/spitfire/toxic_adapter.ex`

Convert between Toxic's ranged metadata format and Spitfire's expected format:
- Toxic: `{{start_line, start_col}, {end_line, end_col}, extra}`
- Spitfire: `{line, column, end_column}` or similar

### 2.2 Handle Linearized Interpolation
Toxic emits flat streams with `:begin_interpolation`/`:end_interpolation` markers instead of nested lists. Update:
- `parse_interpolation/2` to handle linear token stream
- Remove nested list processing logic

## Phase 3: Error Recovery Integration

### 3.1 Leverage Toxic's Error Tokens
- Configure Toxic with `error_mode: :tolerant`
- Handle `{:error, pos, reason}` tokens in parser
- Remove synthetic token injection logic

### 3.2 Use Terminator Stack
Replace Spitfire's hardcoded `:fake_closing_bracket` with:
- `Toxic.TokenStream.peek_missing_terminator/1`
- `Toxic.TokenStream.current_terminators/1`

## Phase 4: Fuel System Integration

### 4.1 Unify Fuel Consumption
Modify `consume_fuel/1` to also charge for tokenization:
```elixir
defp consume_and_next(parser) do
  parser
  |> consume_fuel()
  |> advance_token()
end
```

### 4.2 Handle Fuel Exhaustion
When fuel depletes, gracefully terminate with partial AST rather than crashing.

## Phase 5: Incremental Parsing Support

### 5.1 Add Range-Based Parsing
- Accept `{start_offset, end_offset}` parameters
- Use Toxic's producer function API for streaming input
- Support checkpointing for backtracking

### 5.2 AST Node Spans
Update all AST builders to use Toxic's precise spans:
- Read both `start_pos` and `end_pos` from tokens
- Store in node metadata for accurate source mapping

## Phase 6: Configuration & Options

### 6.1 Map Spitfire Options to Toxic
```elixir
toxic_opts = [
  eol_mode: if(opts[:preserve_comments], do: :emit, else: :embed),
  error_mode: :tolerant,
  error_sync: [:semicolon, :newline, :closer],
  max_batch: 256
]
```

### 6.2 Remove Erlang Tokenizer Dependency
- Remove calls to `:spitfire_tokenizer.tokenize/4`
- Remove `src/spitfire_tokenizer.erl` (optionally keep for reference)

## Implementation Steps

1. **Create feature branch**: `toxic-integration`

2. **Add Toxic dependency**: Update `mix.exs` to use Toxic from path

3. **Implement adapter module**: Create `lib/spitfire/toxic_adapter.ex`

4. **Refactor parser state**: Update `new/2` to use `Toxic.TokenStream`

5. **Update token operations**: Replace `next_token/1`, `current_token/1`, `peek_token/1`

6. **Handle linearized tokens**: Update interpolation parsing

7. **Test incrementally**: Run existing tests after each major change

8. **Add streaming tests**: Create tests for streaming scenarios

9. **Benchmark performance**: Compare memory usage and latency

10. **Document changes**: Update README and API docs

## Key Files to Modify

1. `lib/spitfire.ex` - Main parser module (~2800 lines)
   - Token management functions (lines 2235-2513)
   - Parser initialization (lines 131-152)
   - Expression parsing logic

2. `lib/spitfire/toxic_adapter.ex` - New adapter module

3. `mix.exs` - Update dependencies

4. `test/spitfire_test.exs` - Update/add tests

## Testing Strategy

1. **Preserve existing tests**: Ensure all current tests pass
2. **Add streaming tests**: Test one-token-at-a-time consumption
3. **Error recovery tests**: Test malformed input handling
4. **Performance tests**: Memory usage and first-token latency
5. **Incremental parsing tests**: Test partial re-parsing

## Risks & Mitigations

1. **Token format differences**: Use adapter layer to minimize changes
2. **Missing error tokens in Toxic**: Currently not implemented - may need workaround
3. **Performance regression**: Benchmark early and often
4. **Breaking changes**: Keep old tokenizer as fallback initially

## Success Criteria

- All existing tests pass
- Streaming tokenization works correctly
- Memory usage reduced for large files
- First-token latency improved
- Error recovery works without synthetic tokens
- Ready for incremental parsing extensions

## Detailed Integration Points

### Current Spitfire Token Flow
1. `tokenize/2` calls `:spitfire_tokenizer.tokenize/4` 
2. Returns complete token list upfront
3. Parser maintains `current_token` and `peek_token` pointers
4. `next_token/1` advances through list

### New Toxic Token Flow
1. Create `Toxic.TokenStream` with source code
2. Stream maintains internal buffer and state
3. Parser calls `TokenStream.next/1` for each token
4. Lookahead via `TokenStream.peek/1` without consuming

### Token Format Mapping

#### Spitfire Token Formats
```elixir
# Simple tokens
{:identifier, {line, column, nil}, name}
{:int, {line, column, end_column}, chars}

# Operators
{:dual_op, {line, column, nil}, :+}
{:comp_op, {line, column, nil}, :==}

# Complex tokens
{:sigil, meta, sigil_char, content, modifiers, indent, delimiter}
{:bin_heredoc, meta, indent, tokens}
```

#### Toxic Token Formats
```elixir
# All tokens have ranged metadata
{:identifier, {{line, col}, {end_line, end_col}, extra}, name}
{:int, {{line, col}, {end_line, end_col}, extra}, chars}

# Linearized interpolation
{:bin_string_start, meta, delimiter}
{:string_fragment, meta, text}
{:begin_interpolation, meta, :string}
# ... interpolated tokens ...
{:end_interpolation, meta, :string}
{:bin_string_end, meta, delimiter}
```

### Adapter Functions Needed

```elixir
defmodule Spitfire.ToxicAdapter do
  # Convert Toxic token to Spitfire format
  def adapt_token({type, {{line, col}, {_, end_col}, _}, value}) do
    {type, {line, col, end_col}, value}
  end

  # Extract token type for pattern matching
  def token_type({type, _, _}), do: type
  def token_type({type, _}), do: type
  
  # Extract metadata
  def token_meta({_, meta, _}), do: adapt_meta(meta)
  def token_meta({_, meta}), do: adapt_meta(meta)
  
  defp adapt_meta({{line, col}, {_, end_col}, extra}) do
    [line: line, column: col, end_column: end_col] ++ (extra || [])
  end
end
```

### Parser State Structure

#### Current Parser State
```elixir
%{
  tokens: [token1, token2, ...],  # Pre-tokenized list
  fuel: 150,
  current_token: token,
  peek_token: token,
  nesting: 0,
  literal_encoder: encoder,
  errors: []
}
```

#### New Parser State with Toxic
```elixir
%{
  stream: %Toxic.TokenStream{},   # Streaming token source
  fuel: 150,
  current_token: token,           # Cached after next/1
  nesting: 0,
  literal_encoder: encoder,
  errors: []
}
```

### Critical Parser Functions to Update

1. **Parser initialization** (`new/2` at line 2235)
2. **Token advancement** (`next_token/1` at lines 2247-2354)
3. **Token inspection** (`current_token/1` at lines 2455-2513)
4. **Lookahead** (`peek_token/1` at lines 2355-2381)
5. **Token type extraction** (various pattern matches throughout)
6. **Interpolation parsing** (`parse_interpolation/2`)
7. **Error recovery** (synthetic token injection logic)

### Performance Considerations

#### Memory Usage
- **Current**: Entire token list in memory
- **With Toxic**: Configurable buffer (default 256 tokens)
- **Expected**: Lower memory for large files

#### Latency
- **Current**: High initial latency (tokenize everything)
- **With Toxic**: Low first-token latency
- **Trade-off**: Slightly higher per-token overhead

#### Throughput
- **Current**: Fast iteration through pre-built list
- **With Toxic**: Tokenization interleaved with parsing
- **Optimization**: Tune buffer size via `max_batch` option