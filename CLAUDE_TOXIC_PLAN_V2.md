# Spitfire + Toxic Integration Implementation Plan (Revised)

## Goals
- Replace `:spitfire_tokenizer` with Toxic while keeping Spitfire's AST and error behavior stable
- Preserve current token shapes and metas expected by `lib/spitfire.ex`
- Migrate to a streaming, tolerant tokenizer with precise spans and terminator introspection

## Non-Goals
- Changing AST shape or precedence semantics
- Rewriting parser logic beyond token I/O and missing-closer handling (until Phase 2)

## Phase 0: Baseline Understanding ✓
- Review PARSER.md and HIGH_LEVEL_TOKENIZER_PLAN.md
- Understand current parser/tokenizer interfaces in `lib/spitfire.ex`
- Study Toxic API: streaming, token shapes, terminator introspection
- Identify token format differences and conversion needs

## Phase 1: Compatibility Adapter (Keep Parser Unchanged)

**Goal**: Add compatibility layer that converts Toxic streaming tokens into Spitfire's existing token shapes on-the-fly. **Do not change parsing logic**.

### 1.1 New Module: `lib/spitfire/token_stream.ex`

Build streaming wrapper around `Toxic.TokenStream` with:

**Configuration**:
```elixir
toxic_opts = [
  eol_mode: :emit,                    # Spitfire expects explicit :eol
  error_mode: :tolerant,              # Match error-accumulating behavior
  elixir_compatibility: true,         # Shape parity if needed
  max_batch: 256
]
```

**Internal State**:
```elixir
defstruct [
  driver_stream: nil,                 # Toxic.TokenStream.t()
  collapse_stack: [],                 # For linear → nested conversion
  buffer: :queue.new(),              # Ready-to-emit collapsed tokens
  pushback: [],                      # Pushback buffer
  eof_closers: [],                   # Closers to inject after EOF
  position: {1, 1}                   # Current line/column
]
```

**Public API**:
```elixir
@spec new(binary(), integer(), integer(), keyword()) :: t()
@spec next(t()) :: {:ok, token(), t()} | {:eof, t()}
@spec peek(t()) :: {:ok, token(), t()} | {:eof, t()}
@spec pushback(t(), token()) :: t()
@spec position(t()) :: {{integer(), integer()}, t()}
@spec terminators(t()) :: {[terminator()], t()}
```

### 1.2 Token Collapsing (Critical Missing Piece)

Convert Toxic's **linearized tokens** into Spitfire's **nested structures**:

#### String/Heredoc Collapsing
```elixir
# Toxic linearized output:
{:bin_string_start, meta, delimiter}
{:string_fragment, meta, "foo "}
{:begin_interpolation, meta, :string}
{:identifier, meta, :x}
{:end_interpolation, meta, :string}
{:string_fragment, meta, " bar"}
{:bin_string_end, meta, delimiter}

# ↓ Collapse to Spitfire format:
{:bin_string, {line, col, delimiter}, [
  "foo ",
  {{start_line, start_col}, {end_line, end_col}, [identifier: :x]},
  " bar"
]}
```

#### Sigil Collapsing
```elixir
# Toxic: sigil_start → fragments/interpolation → sigil_end
# Spitfire: {:sigil, meta, sigil_atom, parts_or_tokens, modifiers, indent, delimiter}
```

#### Quoted Identifier Collapsing
```elixir
# Toxic: quoted_identifier_start → parts → quoted_identifier_end  
# Spitfire: {:identifier | :paren_identifier | :bracket_identifier, meta, atom}
```

### 1.3 Metadata Conversion

Convert Toxic's ranged metadata to legacy format:
```elixir
# Toxic: {{start_line, start_col}, {end_line, end_col}, extra}
# Spitfire: {line, column, extra}  (use start position)

# Special cases:
# - EOL tokens: preserve newline count in extra
# - Operators: preserve delimiter info
# - Containers: preserve closing position
```

### 1.4 EOF Closer Injection

When Toxic returns `{:eof, stream}` but terminators remain:
```elixir
case Toxic.Driver.current_terminators(driver) do
  [] -> {:eof, stream}
  terminators ->
    closers = Enum.map(terminators, &synthesize_closer/1)
    # Queue closers before returning EOF
end

defp synthesize_closer({:"(", meta, _indent}), do: {:")", legacy_meta(meta)}
defp synthesize_closer({:do, meta, _indent}), do: {:end, legacy_meta(meta)}
# ... etc
```

### 1.5 Wire Adapter into Parser

**Replace `tokenize/2`** (line 2153):
```elixir
defp tokenize(code, opts) do
  case Application.get_env(:spitfire, :tokenizer, :toxic) do
    :toxic ->
      line = opts[:line] || 1
      column = opts[:column] || 1
      stream = Spitfire.TokenStream.new(code, line, column, opts)
      {:stream, stream}
    
    :legacy ->
      # Keep existing Erlang tokenizer logic
  end
end
```

**Update `new/2`** (line 2235):
```elixir
defp new(code, opts) do
  tokens = tokenize(code, opts)
  %{
    tokens: tokens,                    # {:stream, stream} or list
    fuel: 150,
    current_token: nil,
    peek_token: nil,
    # ... rest unchanged
  }
end
```

**Rewrite `next_token/1`** (lines 2247-2354):
```elixir
# Add clause for streaming mode:
defp next_token(%{tokens: {:stream, stream}} = parser) do
  case Spitfire.TokenStream.next(stream) do
    {:ok, token, new_stream} ->
      %{parser | 
        tokens: {:stream, new_stream},
        current_token: parser.peek_token,
        peek_token: token,
        fuel: 150
      }
    
    {:eof, final_stream} ->
      %{parser | 
        tokens: {:stream, final_stream},
        current_token: parser.peek_token,
        peek_token: :eof,
        fuel: 150
      }
  end
end

# Keep existing list-based clauses for fallback
```

### 1.6 Update Token Accessors

Ensure `current_token/1`, `peek_token/1`, etc. work unchanged by only reading from `current_token`/`peek_token` fields, not directly accessing `tokens`.

### 1.7 Update `eat_eol/1` and `eat_at/3`

For streaming mode, implement "conditional advance":
```elixir
defp eat_eol(%{tokens: {:stream, _}} = parser) do
  if peek_token_type(parser) == :eol do
    next_token(parser)
  else
    parser
  end
end
```

## Phase 2: Stream-First and Terminator-Aware Parser

### 2.1 Replace Synthetic Closer Logic

Where Spitfire injects fake closers, query `Toxic.Driver.peek_missing_terminator/1`:
- Grouped expressions: `parse_grouped_expression/1`
- Lists, tuples, bitstrings, maps: closing checks
- Do-blocks: `end` detection

### 2.2 Use Token Operator Metadata

Optionally read precedence directly from token instead of `@precedences` lookup.

### 2.3 Enhanced Lookahead

Replace `peek_token(next_token(parser))` with `TokenStream.peek_n/2`.

## Phase 3: Cleanups and Deletions

### 3.1 Remove Legacy Code
- Stop shipping `src/spitfire_tokenizer.erl` at runtime
- Update documentation

### 3.2 Configuration
```elixir
config :spitfire, :tokenizer, :toxic  # vs :legacy
```

## Token Shape Parity Checklist

Ensure **exact** compatibility with these Spitfire token shapes:

### Identifiers
```elixir
{:identifier | :alias | :paren_identifier | :bracket_identifier | :op_identifier | :do_identifier, 
 {line, col, extra}, atom}
```

### Numbers/Characters  
```elixir
{:int | :flt | :char, {line, col, value_or_repr}, repr}
```

### Strings/Heredocs
```elixir
{:bin_string | :list_string, {line, col, delimiter}, [parts_or_interpolation_triples]}
{:bin_heredoc | :list_heredoc, {line, col, extra}, indent, [parts_or_interpolation_triples]}
```

### Sigils
```elixir
{:sigil, meta, sigil_atom, parts_or_tokens, modifiers, indent, delimiter}
```

### Operators (unchanged)
```elixir
:assoc_op, :type_op, :stab_op, :pipe_op, :unary_op, :range_op, :ternary_op, 
:dual_op, :mult_op, :power_op, :or_op, :and_op, :rel_op, :comp_op, :xor_op, 
:in_match_op, :concat_op
```

### EOL/Punctuation
```elixir
{:eol | :";\" | :\",\", {line, column, newlines_or_extra}}
{:{, :}, :[, :], :(, :), :\"<<\", :\">>\"}
```

### Keyword Identifiers
```elixir
{:kw_identifier, {line, col, delimiter}, atom_or_unsafe_parts}
```

## File Changes Summary

1. **`lib/spitfire.ex`**:
   - Line 2153: `tokenize/2` - return stream sentinel
   - Lines 2235-2245: `new/2` - handle stream state
   - Lines 2247-2354: `next_token/1` - add streaming clauses  
   - Lines 2320-2360: `eat_eol/1`, `eat_at/3` - conditional advance
   - Lines 2355-2513: Token accessors - ensure field-only access

2. **`lib/spitfire/token_stream.ex`** - New compatibility adapter

3. **No changes to `@precedences` initially**

## Testing Strategy

1. **Preserve all existing tests**: `mix test` passes in both modes
2. **Add focused tests**:
   - String/heredoc/sigil interpolation and indentation
   - Quoted identifiers and space-sensitive rewrites
   - Missing closers across all container types
   - EOL newline count preservation
3. **Fuzz testing**: Malformed input handling

## Migration Strategy

1. **Default to `:toxic` in dev/test**
2. **Allow `:legacy` override** for bisecting regressions  
3. **Gradual rollout** with config flag

## Acceptance Criteria

- All current tests pass with Toxic streaming
- No behavioral regressions in parser AST/errors
- Streaming handles large inputs without full materialization
- Terminator-based closer synthesis reduces synthetic injection
- Memory usage improved for large files
- First-token latency reduced

## Critical Implementation Notes

The **token collapser** is the most complex component - it must perfectly reconstruct Spitfire's nested token structures from Toxic's linear stream. This requires:

1. **State machine** to track collapsing contexts (string, heredoc, sigil, quoted_id)
2. **Buffer management** for holding partial tokens during collapse
3. **Metadata preservation** including positions, delimiters, and indentation
4. **Error handling** for malformed linear sequences

Success depends on getting this collapsing layer **exactly right** to maintain 100% compatibility with existing parser logic.