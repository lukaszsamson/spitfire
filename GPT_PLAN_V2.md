Here’s a tighter plan that addresses gaps and a few inaccuracies in CLAUDE_TOXIC_PLAN.md, while minimizing churn to the large parser.

What To Fix From CLAUDE Plan

Token stream vs. parser fields: Removing current_token/peek_token across lib/spitfire.ex is too invasive now. Keep them and back the parser with a streaming adapter that feeds those two fields, preserving two-token lookahead semantics.
Terminator API: Use Toxic.Driver.current_terminators/1 and Toxic.Driver.peek_missing_terminator/1 (not TokenStream). Surface driver state via the adapter.
Interpolation: Don’t rewrite parse_interpolation/2 yet. Instead, collapse Toxic’s linear markers into Spitfire’s existing nested shapes so parse_interpolation/2 keeps working unchanged.
EOL handling: Always use eol_mode: :emit. Comment preservation is a different concern and shouldn’t toggle EOL mode.
Error tokens: Toxic currently doesn’t emit explicit error tokens broadly. Treat tolerant mode as “continue; no hard error tokens to parse” until Toxic fully exposes them.
Cursor flow: Spitfire’s vendored cursor/missing-stab logic in tokenize/2 needs functional parity. Keep legacy for container_cursor_to_quoted/2 initially or gate Toxic path behind a flag for that function.
Revised Implementation Plan

Phase 1 — Adapter-Backed Streaming (no parser refactor)

Add lib/spitfire/token_stream.ex:
Wrap Toxic.TokenStream.new/4 and retain driver access.
Implement next/peek/pushback/peek_n/position/terminators.
Streamingly collapse Toxic linear markers into Spitfire’s legacy token shapes (strings, heredocs, sigils, quoted identifiers/atoms, interpolation) and convert ranged metas to legacy metas.
On EOF with unterminated constructs, synthesize minimal closing tokens using Toxic.Driver.current_terminators/1 (and peek_missing_terminator/1), then return :eof.
Wire into parser with minimal edits:
lib/spitfire.ex:2148 tokenize/2: return {:stream, stream} instead of a flat list when Toxic is enabled.
lib/spitfire.ex:2235 new/2: accept tokens: {:stream, stream}, keep current_token and peek_token.
lib/spitfire.ex:2247–2297 next_token/1: if stream-backed, shift current_token <- peek_token; fill peek_token via adapter next/1.
lib/spitfire.ex:2355–2381 peek_token/1 and lib/spitfire.ex:2443–2455 peek_token_type/1: read from peek_token only (adapter ensures shape).
lib/spitfire.ex:2320–2360 eat_eol/eat_at: for stream-backed state, consume one token from the stream only if allowed token matches (no list mutation).
Do not change parse_interpolation/2; adapter feeds expected nested tokens.
Keep legacy path as a config fallback (config :spitfire, :tokenizer, :legacy | :toxic).
Phase 2 — Terminator-Aware Recovery

Replace parser’s synthetic closer branches with adapter-provided closers. Start with:
Grouping: parse_grouped_expression/1 closures (lib/spitfire.ex around 399–520).
Lists, tuples, bitstrings, maps closures (multiple sites).
Do/end block handling (block identifiers and end).
Use adapter terminators/1 and peek_missing_terminator/1 to inject only the required closers and improve diagnostics.
Phase 3 — Stream-First Enhancements (optional)

Replace ad-hoc two-token peeks like peek_token(next_token(parser)) with TokenStream.peek_n/2 for clarity where helpful.
Cursor path: Reimplement missing-stab cursor completion using terminators/1 snapshots, then remove vendored reverse_tokens/4 cursor logic. Until then, keep legacy for container_cursor_to_quoted/2.
Incremental APIs: add Spitfire.parse_range/3 that accepts source slices; use TokenStream.slice/6, checkpoints (checkpoint/1, rewind_to/3) for backtracking convenience.
Adapter Responsibilities

Collapse linear sequences into Spitfire shapes:
Strings: {:bin_string | :list_string, {line, col, delimiter?}, [parts | {start_meta, end_meta, tokens}]}.
Heredocs: {:bin_heredoc | :list_heredoc, {line, col, _}, indent, parts_with_interpolations} with indentation trimming parity.
Sigils: {:sigil, meta, sigil_atom, parts_or_tokens, modifiers, indent, delimiter}; collect :sigil_modifiers emitted before *_end.
Quoted identifiers: collapse *_quoted_identifier_* ends to :identifier | :paren_identifier | :bracket_identifier | :do_identifier | :op_identifier with correct metas.
Quoted atoms: map to :atom_quoted or :atom_unsafe (parts list) as today.
Operators and punctuation:
Maintain existing token atoms/types: :assoc_op, :type_op, :stab_op, :pipe_op, :unary_op, :range_op, :ternary_op, :dual_op, :mult_op, :power_op, :or_op, :and_op, :rel_op, :comp_op, :xor_op, :in_match_op, :concat_op, :{}, :[], :(), :<<, :>>, :",", :";"
Dots: Toxic emits {:., meta}; Spitfire precedence maps :. to @dot_call_op already, so no special-case required.
Keyword identifiers:
Produce :kw_identifier for safe forms and :kw_identifier_unsafe with parts list when unsafe (parity with Spitfire).
EOL/newlines:
Emit {:eol, {line, column, newlines}}, keep the third meta field as newline count, as Spitfire uses it in current_eoe/peek_eoe.
Meta conversion:
Tokens use legacy metas {line, column, extra}; for ranged inputs, use start position and preserve “extra” (e.g., delimiters, newline counts). AST nodes continue to compute spans as they do today.
Affected Code

lib/spitfire.ex:2148
lib/spitfire.ex:2235
lib/spitfire.ex:2247–2297
lib/spitfire.ex:2320–2360
lib/spitfire.ex:2355–2381
lib/spitfire.ex:2443–2467
New: lib/spitfire/token_stream.ex
Configuration

Default to Toxic in dev/test; allow fallback via config :spitfire, :tokenizer, :legacy.
Token stream options: eol_mode: :emit, error_mode: :tolerant, error_sync: [:semicolon, :newline, :closer], max_batch: 256, line, column.
Testing

Run current test suite in both modes (legacy/Toxic).
Add tests for:
Interpolation within strings/heredocs/sigils (including quoted identifiers).
Space-sensitive operator cases and kw_identifier safe/unsafe variants.
Missing closers (paren/bracket/brace/bitstring) and do/end blocks.
EOL/newline meta counts.
Differential smoke test: tokenize via legacy and via Toxic+adapter on a corpus; compare token sequences modulo acceptable differences (e.g., range vs. start-only meta).
Risks & Mitigations

Collapser correctness: mirror toxic_tokenizer:collapse_linear_ranges/1 behavior in streaming adapter; test interpolation and delimiter edge-cases thoroughly.
Cursor path regressions: gate Toxic path off for container_cursor_to_quoted/2 until equivalent behavior is implemented.
Performance: monitor per-token overhead; adjust max_batch; avoid over-peeking; reuse adapter state.
