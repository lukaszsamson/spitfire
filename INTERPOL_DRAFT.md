1. Refactor String/Atom/Sigil Parsing (lib/spitfire.ex)

The main changes will be in how we handle linearized constructs:

Current Approach (Nested):

- Tokens like :bin_string contain nested token lists for interpolations
- parse_interpolation/2 recursively parses nested token structures

New Approach (Linear):

- Handle sequential tokens: begin_x → fragment → begin_interpolation → tokens → end_interpolation → fragment →
end_x
- Track interpolation nesting depth
- Build AST incrementally as we consume linear tokens

2. New Parsing Functions

Create specialized handlers for linearized constructs:

# Parse linearized strings/charlists
parse_linearized_string(parser, kind)
  - Consume :bin_string_start/:list_string_start
  - Accumulate fragments and interpolations until matching end
  - Track nesting for nested interpolations

# Parse linearized atoms
parse_linearized_atom(parser, safety)
  - Handle :atom_safe_start/:atom_unsafe_start
  - Similar to strings but build atom AST

# Parse linearized sigils
parse_linearized_sigil(parser)
  - Handle :sigil_start → content → :sigil_end → :sigil_modifiers

# Parse linearized identifiers
parse_linearized_identifier(parser)
  - Handle :quoted_identifier_start → fragments → end variants

3. Interpolation Nesting Tracker

Add interpolation context to parser state:
defstruct [
  # ... existing fields ...
  interpolation_stack: []  # Track nested interpolation contexts
]

4. Token Pattern Matching Updates

Update parse_expression/6 prefix dispatcher:
case current_token_type(parser) do
  :bin_string_start -> &parse_linearized_string(&1, :binary)
  :list_string_start -> &parse_linearized_string(&1, :charlist)
  :bin_heredoc_start -> &parse_linearized_heredoc(&1, :binary)
  :list_heredoc_start -> &parse_linearized_heredoc(&1, :charlist)
  :atom_safe_start -> &parse_linearized_atom(&1, :safe)
  :atom_unsafe_start -> &parse_linearized_atom(&1, :unsafe)
  :sigil_start -> &parse_linearized_sigil/1
  :quoted_identifier_start -> &parse_linearized_identifier/1
  # ... keep existing patterns for compatibility ...
end

5. Interpolation Handler

New function to handle interpolation sequences:
defp parse_interpolation_sequence(parser, acc, terminator, context) do
  case current_token_type(parser) do
    :begin_interpolation ->
      # Parse nested Elixir expression
      parser = next_token(parser)
      {expr, parser} = parse_expression(parser)
      # Continue until :end_interpolation

    :string_fragment ->                                                                                          
      # Accumulate fragment                                                                                      
                                                                                                                 
    ^terminator ->                                                                                               
      # End of construct                                                                                         
                                                                                                                 
    _ ->                                                                                                         
      # Handle nested interpolations by recursion                                                                
  end
end


What’s Solid

Linearized model: begin_x → fragments → begin_interpolation → tokens → end_interpolation → … → end_x is exactly how Toxic emits tokens.
Specialized handlers for strings/charlists/heredocs/sigils/quoted identifiers/atoms make sense and map well to Toxic’s token set.
Tracking interpolation depth/state is necessary because Pratt needs to treat end_interpolation as a local terminator.
Key Gaps To Address

End-of-interpolation as terminal: parse_expression’s Pratt loop must treat :end_interpolation as a terminator while inside interpolation contexts; otherwise it will happily parse past it.
Reset nesting inside interpolation: the current code spawns a sub-parser with nesting: 0 for nested interpolation (see lib/spitfire.ex:2148 and 1413–1465). When parsing inline, you must temporarily set nesting: 0 for the interpolation expression and restore it after consuming :end_interpolation.
Token coverage: expand prefix dispatch and token readers to include all Toxic linear tokens:
Starts: :bin_string_start, :list_string_start, :bin_heredoc_start, :list_heredoc_start, :sigil_start, :quoted_identifier_start, :atom_safe_start, :atom_unsafe_start
Ends: :bin_string_end, :list_string_end, :bin_heredoc_end, :list_heredoc_end, :sigil_end, :sigil_modifiers, :quoted_identifier_end, :quoted_paren_identifier_end, :quoted_bracket_identifier_end, :atom_safe_end, :atom_unsafe_end
Interp: :begin_interpolation, :end_interpolation
Meta fidelity: preserve delimiter, indentation (heredocs), and closing meta. Previously, end meta came from nested token tuples; with Toxic, use end token meta (or :end_interpolation meta) explicitly.
Identifier calling variants: quoted identifiers have three end tokens (:quoted_identifier_end, :quoted_paren_identifier_end, :quoted_bracket_identifier_end). The parser should emit the same shapes as unquoted: plain identifier, paren_identifier, or bracket_identifier.
Unsafe vs safe atoms: keep the distinction. Unsafe with interpolation must remain :erlang.binary_to_atom({:<<>>,...}, :utf8); safe atoms without interpolation should remain literal atoms; safe with interpolation may need to stay unsafe at runtime (flag dictates what the tokenizer emits).
Heredoc/sigil indentation: Toxic end tokens carry indent; propagate to AST meta as today (see heredoc branches around lib/spitfire.ex:1320 and sigil at 1465–1515).
EOL model alignment: Toxic streams EOLs with ranged metas. Your current_meta already supports ranged metas (lib/spitfire.ex:2347–2356). Ensure EOL consumption functions remain compatible; no changes needed if you continue using eat_eol/1, peek_newlines/1.
Refined Plan

Parsing Entrypoints
Add prefix handlers:
:bin_string_start → parse_linearized_string(parser, :binary)
:list_string_start → parse_linearized_string(parser, :charlist)
:bin_heredoc_start → parse_linearized_heredoc(parser, :binary)
:list_heredoc_start → parse_linearized_heredoc(parser, :charlist)
:sigil_start → parse_linearized_sigil/1
:quoted_identifier_start → parse_linearized_identifier/1
:atom_safe_start / :atom_unsafe_start → parse_linearized_atom(parser, :safe | :unsafe)
Interpolation Awareness
Add parser.interpolation_depth (or interpolation_stack) with accessors to push/pop.
Update parse_expression/6 to choose terminal sets:
At top-level: @terminals
Inside interpolation: MapSet.put(@terminals, :end_interpolation)
With commas: same but with comma added
Ensure validate_peek/2 treats :end_interpolation as valid when in interpolation.
Linearized Constructors
Implement a shared scanner:
scan_linearized(parser, terminators, on_fragment, on_begin_interp, on_end)
Loop:
:string_fragment → call on_fragment(meta, binary) and accumulate
:begin_interpolation → push interpolation depth; save old_nesting; set nesting: 0; parse one expression; expect/consume :end_interpolation; restore nesting; record closing meta from :end_interpolation
Matching end token → call on_end(end_meta, extra) and return
Unexpected token → error + recovery (peek Driver.peek_missing_terminator/1 if you want to improve)
parse_linearized_string/2:
For :binary: build {:<<>>, meta_with_delimiter, parts}; each interpolation emits the typed segment {:\"::\", meta, [{{:., meta, [Kernel, :to_string]}, [from_interpolation: true, closing: end_meta], [expr]}, {:binary, meta, nil}]} as in parse_interpolation/2 today (lib/spitfire.ex:2153+).
For :charlist: wrap parts in {{{:., meta, [List, :to_charlist]}, [{:delimiter, \"'\"} | meta], [parts]}}; interpolation expression wrapped with Kernel.to_string like in list_string branch (lib/spitfire.ex:1413–1465).
parse_linearized_heredoc/2:
Same as string but include {:indentation, indent} from end token meta (Toxic end carries indent).
parse_linearized_sigil/1:
Start token: {:sigil_start, meta, sigil_atom, delim}; collect fragments and interpolations as binary; on :sigil_end, produce {sigil_atom, Keyword.put(meta, :delimiter, delim), [{:<<>>, meta_with_indent, args}, modifiers]}; read optional :sigil_modifiers next.
parse_linearized_identifier/1:
Collect fragments/interp as binary; on end:
:quoted_paren_identifier_end → return {:paren_identifier, meta_with_delimiter, atom}
:quoted_bracket_identifier_end → {:bracket_identifier, meta_with_delimiter, atom}
:quoted_identifier_end → {:identifier, meta_with_delimiter, atom}
parse_linearized_atom/2:
Safe without interpolation → literal atom
Unsafe or any with interpolation → {{:., meta, [:erlang, :binary_to_atom]}, [{:delimiter, ~S'\"'} | meta], [{:<<>>, meta, parts}, :utf8]} (mirror parse_atom/1 unsafe branch at 1276–1286)
Token Readers
Extend current_token_type/1, current_token/1, peek_token/1, current_meta/1 to recognize the new shapes (starts/ends/fragments/interp). current_meta/1 already supports ranged metas; just ensure start/end tokens are covered.
Error Recovery (optional high-leverage)
Replace fake closers: when missing end token inside a linearized construct, call Toxic.Driver.peek_missing_terminator/1 (via Spitfire.TokenStream exposing driver) to inject the correct closer rather than generic fake bracket tokens.
Backward Compatibility
Keep old nested-token branches so the legacy tokenizer still works.
Route via Application.get_env(:spitfire, :tokenizer, :legacy) as you already do in lib/spitfire/token_stream.ex:9–35.
Edge Cases To Test

Nested interpolation levels in strings/sigils/heredocs (including empty expression #{} and multiline).
Quoted identifier followed by ( or [ to ensure *_end variants map to correct AST forms.
Safe vs unsafe atoms with and without interpolation.
Heredoc indentation capture and trimming around start/end lines.
Mixing linearized constructs inside interpolation expressions (e.g., "foo#{'bar#{baz}'}").
EOL handling around interpolation boundaries to ensure end_of_expression metadata remains correct.
Suggested Implementation Order

Wire interpolation depth and terminal handling in parse_expression/6.
Add linearized prefix cases and a minimal parse_linearized_string/2 to pass simplest string tests.
Extend to charlists, heredocs, and sigils with indentation/modifiers.
Add quoted identifiers and atoms.
Optionally replace fake closers with peek_missing_terminator/1.



Refined Plan: Integrate Toxic's Linearized Token Stream into Spitfire Parser

Core Architecture Changes

1. Parser State Extensions

Add to parser struct:
defstruct [
  # ... existing fields ...
  interpolation_depth: 0,      # Track interpolation nesting level
  saved_nesting_stack: []      # Stack to save/restore nesting during interpolations
]

2. Terminal Set Management

Modify parse_expression/6 to dynamically select terminals based on context:
defp get_terminals(parser) do
  base = if parser.interpolation_depth > 0 do
    MapSet.put(@terminals, :end_interpolation)
  else
    @terminals
  end
  # Add comma variants as needed
end

Token Coverage Matrix

Start Tokens (Prefix Handlers)

- :bin_string_start → parse_linearized_string(parser, :binary)
- :list_string_start → parse_linearized_string(parser, :charlist)
- :bin_heredoc_start → parse_linearized_heredoc(parser, :binary)
- :list_heredoc_start → parse_linearized_heredoc(parser, :charlist)
- :sigil_start → parse_linearized_sigil/1
- :quoted_identifier_start → parse_linearized_identifier/1
- :atom_safe_start → parse_linearized_atom(parser, :safe)
- :atom_unsafe_start → parse_linearized_atom(parser, :unsafe)

End Tokens

- :bin_string_end, :list_string_end
- :bin_heredoc_end, :list_heredoc_end (with indentation metadata)
- :sigil_end, :sigil_modifiers
- :quoted_identifier_end, :quoted_paren_identifier_end, :quoted_bracket_identifier_end, :quoted_op_identifier_end, :quoted_do_identifier_end
- :atom_safe_end, :atom_unsafe_end
- :kw_identifier_safe_end, :kw_identifier_unsafe_end

Interpolation Markers

- :begin_interpolation - Push depth, save nesting, parse expression
- :end_interpolation - Pop depth, restore nesting, capture closing meta
- :string_fragment - Accumulate content (needs unescaping except for sigils)

Core Implementation Functions

3. Shared Linearized Scanner

defp scan_linearized(parser, end_token, kind, opts \\ []) do
  accumulator = []

  loop(parser, accumulator) do
    case current_token_type(parser) do
      :string_fragment ->
        {content, meta} = current_token_value(parser)
        # Unescape content unless it's a sigil
        content = if opts[:no_unescape], do: content, else: unescape(content)
        # For heredocs and sigil heredocs, trim whitespace using indent from end token

      :begin_interpolation ->                                                                                    
        # 1. Push interpolation depth                                                                            
        parser = %{parser | interpolation_depth: parser.interpolation_depth + 1}                                 
        # 2. Save and reset nesting                                                                              
        saved_nesting = parser.nesting                                                                           
        parser = %{parser | nesting: 0, saved_nesting_stack: [saved_nesting | parser.saved_nesting_stack]}       
        # 3. Parse expression with :end_interpolation as terminal                                                
        {expr, parser} = parse_expression(parser)                                                                
        # 4. Expect and consume :end_interpolation                                                               
        parser = expect_token(parser, :end_interpolation)                                                        
        # 5. Restore nesting and pop depth                                                                       
        [saved | rest] = parser.saved_nesting_stack                                                              
        parser = %{parser | nesting: saved, saved_nesting_stack: rest, interpolation_depth:                      
parser.interpolation_depth - 1}
        # 6. Build interpolation AST based on kind

      ^end_token ->                                                                                              
        # Extract metadata (indentation for heredocs, modifiers for sigils)                                      
        # Return accumulated AST                                                                                 
    end                                                                                                          
  end
end

4. Specialized Constructors

Here are drafts. For validated implementations translating toxic to legacy tokens read @/Users/lukaszsamson/claude_fun/toxic/src/toxic_tokenizer.erl linear_to_legacy. Generally, the emitted tokens and AST are different if there are interpolation parts.

String/Charlist Handler

defp parse_linearized_string(parser, :binary) do
  parser = next_token(parser)  # consume start token
  {parts, parser} = scan_linearized(parser, :bin_string_end, :binary)

  # Build AST: {:<<>>, meta_with_delimiter, parts}
  # Interpolations become: {:"::", meta, [to_string_call, {:binary, meta, nil}]}
end

defp parse_linearized_string(parser, :charlist) do
  parser = next_token(parser)
  {parts, parser} = scan_linearized(parser, :list_string_end, :charlist)

  # Wrap in List.to_charlist call if interpolated
  # Otherwise return plain charlist
end

Heredoc Handler (with indentation)

defp parse_linearized_heredoc(parser, kind) do
  parser = next_token(parser)
  {parts, parser, end_meta} = scan_linearized(parser, heredoc_end_token(kind), kind)

  # Extract indentation from end_meta
  indent = end_meta[:indentation]

  # Trim whitespace from fragments based on indent
  parts = trim_heredoc_parts(parts, indent)

  # Add indentation to AST metadata
  meta = Keyword.put(meta, :indentation, indent)
end

Sigil Handler (no unescaping)

defp parse_linearized_sigil(parser) do
  {:sigil_start, meta, sigil_atom, delimiter} = current_token(parser)
  parser = next_token(parser)

  {parts, parser} = scan_linearized(parser, :sigil_end, :sigil, no_unescape: true)

  # Check for modifiers
  {modifiers, parser} = case current_token_type(parser) do
    :sigil_modifiers ->
      {mods, _} = current_token_value(parser)
      {mods, next_token(parser)}
    _ ->
      {[], parser}
  end

  # Build: {sigil_atom, meta_with_delimiter, [{:<<>>, parts_meta, parts}, modifiers]}
end

Identifier Handler (five end variants) - should error on interpolation

defp parse_linearized_identifier(parser) do
  parser = next_token(parser)
  {parts, parser, end_token_type} = scan_linearized_with_end_type(parser)

  # Build identifier AST based on end token type
  case end_token_type do
    :quoted_identifier_end -> {:identifier, meta, atom}
    :quoted_paren_identifier_end -> {:paren_identifier, meta, atom}
    :quoted_bracket_identifier_end -> {:bracket_identifier, meta, atom}
    :quoted_op_identifier_end -> {:op_identifier, meta, atom}
    :quoted_do_identifier_end -> {:do_identifier, meta, atom}
  end
end

Atom Handler (safe vs unsafe)

defp parse_linearized_atom(parser, :safe) do
  parser = next_token(parser)
  {parts, parser, has_interpolation} = scan_linearized(parser, :atom_safe_end, :atom)

  if has_interpolation do
    # Must use binary_to_atom at runtime
    {{:., meta, [:erlang, :binary_to_atom]}, meta_with_delimiter, [{:<<>>, meta, parts}, :utf8]}
  else
    # Can be literal atom
    atom_value
  end
end

defp parse_linearized_atom(parser, :unsafe) do
  # Always uses binary_to_atom
  parser = next_token(parser)
  {parts, parser} = scan_linearized(parser, :atom_unsafe_end, :atom)
  {{:., meta, [:erlang, :binary_to_atom]}, meta_with_delimiter, [{:<<>>, meta, parts}, :utf8]}
end

Qualified identifier Handler (safe vs unsafe) - similar to atom

Critical Implementation Details

5. Unescaping and Trimming

# All string fragments need unescaping EXCEPT in sigils
defp process_fragment(content, :sigil, _opts), do: content
defp process_fragment(content, _kind, opts) do
  content = Toxic.Unescape.unescape(content)

  # For heredocs and sigil heredocs, apply indentation trimming
  if opts[:indent] do
    trim_whitespace(content, opts[:indent])
  else
    content
  end
end

6. Metadata Preservation

- Start token meta → opening position
- End token meta → closing position and special data (indentation)
- Interpolation boundaries → from :end_interpolation token meta
- Delimiter info → from start token, propagate to AST

7. Error Recovery Enhancement

defp handle_missing_end_token(parser, expected_end) do
  # Use Toxic's terminator stack instead of synthetic tokens
  case TokenStream.peek_missing_terminator(parser.stream) do
    {:ok, missing} when missing == expected_end ->
      # Inject the specific missing terminator
      inject_token(parser, missing)
    _ ->
      # Fall back to error recovery
      put_error(parser, "unexpected end of input, expected #{expected_end}")
  end
end

Implementation Order

1. Foundation (Day 1)
  - Add interpolation_depth and saved_nesting_stack to parser struct
  - Implement terminal set selection based on interpolation depth
  - Update validate_peek/2 to recognize :end_interpolation as valid terminal
2. Basic Strings (Day 1-2)
  - Implement scan_linearized/4 core loop
  - Add parse_linearized_string/2 for binary strings without interpolation
  - Add unescaping logic
  - Test with simple strings
3. Interpolation Support (Day 2-3)
  - Handle :begin_interpolation / :end_interpolation in scanner
  - Implement nesting save/restore mechanism
  - Build proper interpolation AST segments
  - Test nested interpolations
4. Charlists and Heredocs (Day 3-4)
  - Add charlist support with List.to_charlist wrapping
  - Implement heredoc handlers with indentation extraction
  - Add whitespace trimming for heredoc fragments
  - Test heredoc indentation preservation
5. Sigils and Atoms (Day 4-5)
  - Implement sigil handler without unescaping
  - Handle :sigil_modifiers token
  - Add safe/unsafe atom distinction
  - Test interpolated atoms
6. Identifiers (Day 5)
  - Handle three end-token variants
  - Map to correct AST shapes
  - Test quoted identifiers with parentheses/brackets
7. Error Recovery (Day 6)
  - Replace synthetic token injection
  - Use Toxic's terminator stack
  - Test malformed inputs

Test Coverage Requirements

1. Basic Constructs
  - Simple strings: "hello", 'world'
  - Escaped characters: "foo\nbar", "quote\"here"
  - Empty strings and interpolations: "", "#{}"
2. Interpolation Depth
  - Single level: "foo #{bar} baz"
  - Nested: "outer #{inner("nested #{deep}")}" end"
  - Mixed types: "string with #{~s(sigil #{interpolation})}"
3. Heredocs
  - With indentation: properly trimmed whitespace
  - With interpolation: preserving indent metadata
  - Multi-line with mixed content
4. Sigils
  - Without interpolation: ~r/pattern/
  - With interpolation: ~s(hello #{world})
  - With modifiers: ~r/pattern/iu
5. Atoms and Identifiers
  - Safe atoms: :foo, :"bar"
  - Unsafe atoms with interpolation: :"prefix_#{suffix}"
  - Quoted identifiers: foo."bar", foo."bar"(), foo."bar"[]
6. Error Cases
  - Unclosed strings/heredocs
  - Mismatched interpolation markers
  - Invalid nesting
