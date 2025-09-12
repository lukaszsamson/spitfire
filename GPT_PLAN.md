Here’s a concrete, staged implementation plan to integrate Spitfire with the Toxic streaming tokenizer, preserving correctness first and then unlocking streaming and incremental benefits.

Goals

Replace :spitfire_tokenizer with Toxic while keeping Spitfire’s AST and error behavior stable.
Preserve current token shapes and metas expected by lib/spitfire.ex.
Migrate to a streaming, tolerant tokenizer with precise spans and terminator introspection.
Non-Goals

Changing AST shape or precedence semantics.
Rewriting parser logic beyond token I/O and missing-closer handling (until Phase 2).
Phase 0 — Baseline Understanding (done)

Read parser/tokenizer docs: PARSER.md, HIGH_LEVEL_TOKENIZER_PLAN.md.
Review current parser/lexer interfaces:
Parser token API: new/2, tokenize/2, next_token/1, current_token/1, peek_token/1, current_meta/1, current_precedence/1, parse_interpolation/2 in lib/spitfire.ex.
Erlang tokenizer and interpolation: src/spitfire_tokenizer.erl, src/spitfire_interpolation.erl.
Inspect Toxic API:
Streaming: Toxic.TokenStream (Elixir) and Toxic.Driver (Elixir).
Token shapes and ranges: toxic_tokenizer.erl, Toxic.Token (range metas).
Linear markers collapse helpers: toxic_tokenizer:collapse_linear_ranges/1, ranges_to_legacy/1.
Terminator introspection: Toxic.Driver.current_terminators/1, Toxic.Driver.peek_missing_terminator/1.
Phase 1 — Compatibility Adapter (keep parser unchanged)

Add a compatibility layer that converts Toxic streaming tokens into Spitfire’s existing token shapes and legacy metas on the fly. Do not change parsing logic yet.

New module: lib/spitfire/token_stream.ex

Build on Toxic.TokenStream.new/4 with opts:
eol_mode: :emit (Spitfire expects explicit :eol)
error_mode: :tolerant (matches Spitfire’s error-accumulating behavior)
map opts[:line], opts[:column]
optionally pass elixir_compatibility: true if needed for shape parity
Maintain internal state:
driver_stream :: Toxic.TokenStream.t()
collapse_stack for linear markers (strings, heredocs, sigils, quoted identifiers, quoted atoms)
buffer :: :queue of ready-to-emit, collapsed tokens
push :: [token] pushback buffer
eof_closers :: [token] to flush closers after EOF
Implement public API:
new(source, line, column, opts) :: t
next/1 :: {:ok, token, t} | {:eof, t}
peek/1 :: {:ok, token, t} | {:eof, t}
pushback/2 :: t
position/1 :: {{line, column}, t} (from Toxic.TokenStream.position/1)
terminators/1 :: [{start, meta, indent}] (proxy to Toxic.Driver.current_terminators/1)
Collapser (streaming):
Parse linear tokens (*_start, string_fragment, begin_interpolation, end_interpolation, *_end) and emit collapsed tokens identical to Spitfire’s current container forms:
{:bin_string, {line, col, delim?}, parts}
{:list_string, {line, col, delim?}, parts}
{:bin_heredoc, {line, col, _}, indent, parts}
{:list_heredoc, {line, col, _}, indent, parts}
{:sigil, {line, col, _}, sigil_atom, parts_or_tokens, modifiers, indent, delimiter}
{:quoted_identifier_end ...} → collapse to {:identifier | :paren_identifier | :bracket_identifier | :do_identifier | :op_identifier, meta, atom}
Convert range metas {{sl, sc}, {el, ec}, extra} to legacy metas {line, column, extra} when pushing to buffer (use start pos).
Ensure :eol meta extra holds newline count (Toxic uses this in range extra; conversion should keep extra).
Accept interpolation fragments as:
binaries → retained as binaries
embedded interpolation → triples {start_meta, end_meta, tokens_list}; emit exactly what parse_interpolation/2 expects.
Closer injection:
On {:eof, stream} from Toxic but while Toxic.Driver.current_terminators(driver) non-empty, synthesize closers (e.g. :")", :"]", :"}", :">>", :end) as tokens with legacy metas based on last known position; drain stack to buffer before returning :eof`.
Error tokens:
Toxic doesn’t emit error tokens today; if you enable it later, accept {:error, meta, reason} and either drop or convert to {:__block__, [error: true | meta], []} sentinel (parser already handles error blocks). For now, ignore strict mode and keep tolerant flow.
Wire adapter into parser:

Replace tokenize/2 in lib/spitfire.ex:2148 to build a Spitfire.TokenStream and return a special sentinel (e.g., {:stream, stream_handle}) instead of a flat list. Keep the function signature stable; downstream new/2 will interpret this sentinel.
Update new/2 in lib/spitfire.ex:2230:
state: tokens: {:stream, stream}, current_token: nil, peek_token: nil.
Rewrite next_token/1 clauses (lib/spitfire.ex:2247–2297):
If tokens is {:stream, stream}, advance:
shift current_token <- peek_token
fill peek_token <- stream.next
update stored stream returned by next/1
reset fuel to 150
Maintain old list-based clauses for fallback (config gated).
Rewrite peek_token/1, peek_token_type/1, current_token/1, current_token_type/1:
Ensure unchanged external behavior by pattern matching on peek_token/current_token only; don’t read tokens list directly.
Keep existing special-cases (sigil/heredocs patterns).
Adjust eat_eol/1 and eat_at/3 (lib/spitfire.ex:2320–2360):
For stream-backed parser, implement “eat one if peek is in set”: if peek_token_type ∈ allowed, call stream.next/1 and update peek_token with the following; else no-op.
For list-backed parser, keep current code.
Keep reverse_tokens/4 and vendored cursor logic in place for list-backed mode; streaming mode will not invoke it.
Options mapping

Pass through :cursor_completion, :check_terminators, :preserve_comments as no-ops for now; Toxic does not yet persist comments into tokens.
Honor :line and :column in both drivers.
Acceptance criteria for Phase 1

mix test passes unchanged on streaming mode.
No regressions in token-driven behaviors like :kw_identifier lists, stab_op handling, do/end blocks, heredocs/sigils, access lhs[...]/Kernel.[].
Parser fuel logic still protects against infinite loops.
Phase 2 — Stream-First and Terminator-Aware Parser

Replace parser’s synthetic-closer recovery with driver-assisted closers:
Where Spitfire injects fake closers or raises “missing closing …”, query Toxic.Driver.peek_missing_terminator/1 and synthesize only those closers; reduce noisy diagnostics.
Touchpoints:
Grouped expressions: parse_grouped_expression/1 branches around :")" (lib/spitfire.ex:399–520).
Lists, tuples, bitstrings, maps: closing checks (multiple sites).
Do-blocks: end detection and block identifiers.
Use token operator metadata directly (optional):
Toxic can carry op kinds and precedence at emission time; refactor @precedences lookups to read from token (optional improvement; not required for parity).
Incremental lookahead:
Replace ad-hoc two-token lookahead (e.g., peek_token(next_token(parser))) with TokenStream.peek_n/2 where beneficial.
Cursor completion and partial program parsing:
For container_cursor_to_quoted/2 and interactive features, rely on TokenStream.terminators/1 to generate minimal closers at the cursor, not the vendored reverse_tokens/4.
Phase 3 — Cleanups and Deletions

Stop shipping src/spitfire_tokenizer.erl and src/spitfire_interpolation.erl at runtime (keep in repo until full cutover complete and tested).
Update documentation:
PARSER.md: token stream semantics, ranged metas, terminator introspection.
HIGH_LEVEL_TOKENIZER_PLAN.md: mark implemented items (A.1–A.7, B.1–B.5 as applicable).
Optional config flag :spitfire, :tokenizer:
:legacy vs :toxic to enable fallback until fully confident.
Token Shape Parity Checklist

Identifiers: {:identifier | :alias | :paren_identifier | :bracket_identifier | :op_identifier | :do_identifier, {line,col,_}, atom}
Numbers/char: {:int | :flt | :char, {line,col, value_or_repr}, repr}
Strings/heredocs:
{:bin_string | :list_string, {line,col, '" or '\''}, [parts | interpolation_triples]}
{:bin_heredoc | :list_heredoc, {line,col,_}, indent, [parts | interpolation_triples]}
Sigils: {:sigil, meta, sigil_atom, parts_or_tokens, modifiers, indent, delimiter}
Operators (unchanged): :assoc_op, :type_op, :stab_op, :pipe_op, :unary_op, :range_op, :ternary_op, :dual_op, :mult_op, :power_op, :or_op, :and_op, :rel_op, :comp_op, :xor_op, :in_match_op, :concat_op
Punctuation: :{, :}, :[, :], :(, :), :"<<", :">>"
EOL/semicolon/comma: {:eol | :\";\" | :\",\" , {line, column, newlines}}
Kw identifiers: {:kw_identifier, {line, col, delim?}, atom | unsafe_parts}
File Changes

lib/spitfire.ex:2148
lib/spitfire.ex:2230–2297
lib/spitfire.ex:2320–2360
lib/spitfire.ex:2415–2467 (type/meta helpers reference only current/peek)
New: lib/spitfire/token_stream.ex (adapter + collapser)
No changes to @precedences initially.
Testing

Run mix test in both modes (legacy and Toxic).
Add focused tests for:
Strings/heredocs/sigils with interpolation and indentation.
Quoted identifiers, do_identifier, and space-sensitive dual_op rewrites.
Missing closers across containers and do/end.
EOL newlines counts preserved in AST metadata (current_eoe/1, peek_eoe/1).
Fuzz tests for unmatched delimiters and malformed input (ensure no crashes, errors recorded, AST returns).
Migration/Rollback

Keep legacy tokenizer path behind config: config :spitfire, :tokenizer, :legacy | :toxic.
Default to :toxic in dev/test, allow :legacy override for bisecting regressions.
Acceptance Criteria (Final)

All current tests pass with Toxic streaming.
No behavioral regressions in parser AST and errors across core test corpus.
Streaming mode handles large inputs without materializing full token lists.
Terminator-based closer synthesis reduces “fake closing …” branches.
