@@ -0,0 +1,465 @@
Below is a consolidated roadmap showing exactly what you need to change in the tokenizer and in the Spitfire Pratt parser to get a fully error-tolerant, incremental Pratt pipeline with precise spans and rich recovery.

⸻

A. Tokenizer Changes
	1.	Explicit End Spans
	•	Add an end_pos field to every token record (in addition to the existing start_pos).
	•	Compute it in each tokenize/5 clause (e.g. end_pos = advance_pos(start_pos, lexeme_length)) before tail-recursing.
	2.	Error-Emission Mode
	•	Introduce a “tolerant” flag (Opts #{tolerant => boolean}) so callers can request non–fail-fast lexing.
	•	On lex errors, emit a special token {error, Pos, Reason} and sync to the next safe point (e.g. ;, newline, or matching closer) instead of returning.
	3.	Incremental Hooks & Stable IDs
	•	Allow lexing only a sub‐range ({OffsetStart, OffsetEnd}) by passing offsets into tokenize/5, so incremental reparses can slice out just the edited region.
	•	Tag each token with a stable identity (e.g. a hash of its text+start_pos) so the parser/incremental layer can detect unchanged tokens and reuse them.
	4.	Flat Stream for Interpolation
	•	Optionally flatten nested interpolation forests into a linear stream by emitting explicit {:begin_interp, Pos}/{:end_interp, Pos} tokens around the inner tokens.
	•	Ensure these markers carry full spans so the parser can match them like any other delimiters.
	5.	Operator Metadata
	•	Lookup table mapping raw operator text to {op_kind :: prefix|infix|postfix, precedence :: integer} (you already have @precedences, so pull this into the lexer).
	•	Embed op_kind and prec into each operator token at emission time, so the parser needn’t re-classify them.
	6.	Terminator-Stack Introspection
	•	Expose the Scope#terminators stack (e.g. via lexer:current_terminators/0), so the parser can ask “what closer is next expected?” instead of blind EOF injection.
	•	Add a helper lexer:peek_missing_terminators/0 returning the minimal list of closers needed at the cursor.
	7.	Stream API
	•	Wrap the raw token list in a small iterator module with next/1, peek/1, and pushback/2 so the Pratt parser can look ahead or unget tokens without manually manipulating lists.

⸻

B. Pratt Parser Changes
	1.	Use Full Spans
	•	Update all AST-node constructors to read both start_pos and end_pos from tokens (instead of computing end via peer lookups).
	•	Propagate those spans into the meta map of each AST node for accurate source mapping.
	2.	Consume Error Tokens
	•	Extend your nud and led dispatch to handle {error, Pos, Reason} tokens gracefully: record a diagnostic, skip over them (or wrap in an {:error_node, …}), and resume parsing.
	3.	Replace Synthetic-Closer Logic
	•	Remove hardcoded :fake_closing_bracket injection in the parser. Instead, when you detect a missing closer, call lexer:peek_missing_terminators() to get exactly which closer(s) to inject, and inject only those.
	4.	Flat Interpolation Markers
	•	Adapt parse_interpolation/2 to expect :begin_interp/:end_interp tokens rather than nested lists. This lets it keep a simple two-token lookahead.
	5.	Operator Dispatch via Token Metadata
	•	Simplify your @precedences lookup by directly reading the prec and op_kind from the token record, rather than matching on token-type atoms.
	•	Prune your giant case current_token_type() into something like:

%{op_kind: :infix, prec: p} = tok


	6.	Incremental Parse Boundaries
	•	Add support in Spitfire.parse/2 for a token-range input and for returning a parse forest plus a list of reused nodes.
	•	On reparsing, splice the newly parsed subtree back into the existing AST by matching token-IDs.
	7.	Adjust Fuel & Lookahead
	•	Consider removing the fixed‐fuel guard or parameterizing it per nesting level—once you have real spans and error tokens, runaway recursion is less of a risk.
	•	If needed, extend lookahead beyond two tokens by using your new peek/1/pushback/2 API, rather than ad-hoc state peeks.

⸻

Putting It All Together
	1.	Lexer first: roll out items A.1–A.7 so you can emit a fully featured token stream.
	2.	Parser next: refactor Spitfire to consume the new stream shape and metadata, replacing all custom span-and-closer hacks with calls into the lexer’s APIs.
	3.	Integrate incrementally: wire up your incremental lexing + parsing driver to test real-time edits and cursor-based completion.

With these two synchronized sets of changes, you’ll have a Pratt parser that’s:
	•	Error-tolerant (never dies on bad input),
	•	Span-accurate (nodes know exactly where they begin/end),
	•	Incremental (re-lexes/parses only what’s changed),
	•	Precedence-driven (uses baked-in metadata), and
	•	Ready for IDE workflows like hover, signature help, and completion at the cursor.


Below is a sketch of two complementary incremental-parsing architectures—one that augments your existing absolute-offset tokenizer/AST, and a more advanced, fine-grained approach built on relative offsets and a finger-tree token buffer. Both designs aim to re-parse only what changed while preserving as much of the old AST as possible.

⸻

1. “Absolute Offsets → Coarse Invalidation”

Overview

This approach layers minimal incremental support on top of your current lexer & Pratt parser. Tokens retain absolute start/end positions in the file. On each edit, you:
	1.	Re-lex from the earliest edited character to the end of file.
	2.	Re-parse from the smallest AST node covering the edit (or its parent) to the end of the AST.

Everything after the edit cursor is considered “dirty” and thrown away; only the prefix AST remains intact.

Data Structures
	•	Token List: a flat list [t0, t1, …, tN] where each ti records {start_pos, end_pos, kind, metadata}.
	•	AST with Spans: tree nodes carrying {span = {start,end}, children, meta}.

Algorithm
	1.	On Text Edit
	•	Compute edit_start (absolute offset where change begins).
	•	Invalidate all tokens whose end_pos > edit_start.
	•	Invalidate all AST nodes whose span.end > edit_start.
	2.	Re-lex
	•	Call tokenizer on the suffix starting at edit_start, producing new tokens with correct absolute spans.
	•	Append them to the retained prefix token list.
	3.	Re-parse
	•	Locate the smallest retained AST node whose span.start ≤ edit_start (often the node containing the cursor).
	•	Drop that node and all its siblings/subtrees that extend past edit_start.
	•	Invoke Pratt’s parse_expression/6 (or parse_program) at that point, feeding it the new token list.
	•	Reconstruct a fresh subtree and splice it back into the old AST.

Pros & Cons

Pros	Cons
Simple to implement on top of existing	Re-lexing/re-parsing up to EOF can be expensive for large files
Easily reuses current span-based logic	Granularity is coarse: most of the file after edit is redone
Minimal data-structure changes	Loss of AST node identity; tooling (e.g. incremental indent) suffers


⸻

2. “Relative Offsets + Finger-Tree → Fine-Grained Invalidation”

Overview

Here we build an indexable, editable token buffer (a finger tree) that associates each token with a relative offset (e.g. character count from the previous token). Edits mutate only affected nodes; the rest of the buffer and AST remain untouched.

Data Structures
	1.	Finger Tree of Tokens
	•	Each leaf is a token record {length, kind, meta}.
	•	Internal nodes store the accumulated length of their subtree, enabling O(log n) “split at offset k” operations.
	2.	AST with Back-Pointers
	•	AST nodes reference the exact token leaves they cover.
	•	Instead of spans, each node carries {start_leaf_ref, end_leaf_ref}.
	3.	Incremental Parse Context
	•	A small cache mapping each token leaf to its parsed AST node (if any).
	•	A “dirty” flag on leaves and AST nodes.

Algorithm
	1.	On Text Edit
	•	Locate the leaf and offset within it corresponding to the edit point via finger_tree:split_at_char(EditOffset).
	•	Replace the affected leaf(s) with new token(s) from re-lexing only the edited region (and a small lookahead buffer).
	•	Mark any leaf whose content changed as dirty; propagate dirtiness upward only to the first common ancestor AST node.
	2.	Incremental Re-lex
	•	Run the tolerant lexer only on an edit window—from the preceding synchronization point (e.g. previous semicolon or matching brace) through a small suffix (enough to lex multi-character tokens or close the context).
	•	Emit new leaves, splice them into the finger tree, and adjust sibling offsets automatically via the tree’s stored lengths.
	3.	Incremental Re-parse
	•	Identify the smallest dirty AST node by tracing from dirty leaves up via back-pointers.
	•	Drop that node (and only its subtree).
	•	Invoke Pratt’s parse routines on the finger-tree’s slice(start_leaf, end_leaf) to rebuild that subtree.
	•	Reattach the new subtree to the original parent; other siblings and ancestors remain untouched.
	4.	Cursor Context
	•	Since leaves still carry relative offsets, you can compute absolute positions on demand by summing path lengths in O(log n).
	•	The parse context around the cursor is fully preserved except for the minimal dirty region.

Pros & Cons

Pros	Cons
Only re-lex/par re parse a small window around the edit	Significant data-structure complexity (finger tree!)
AST nodes outside the dirty subtree are fully reused	Requires refactoring AST node references to leaves
Fine-grained incremental tooling (IDE features stay fast)	More machinery: leaf-to-node maps, dirty-node tracking
Absolute positions derivable on demand	Debugging can be trickier due to indirection


⸻

Choosing Between the Two
	1.	Start with Approach 1 if you want a quick win:
	•	Leverage your existing offsets and Pratt routines.
	•	Accept coarse invalidation but get incremental UX for moderate-sized files.
	2.	Evolve to Approach 2 when performance demands grow:
	•	Introduce the finger tree and relative offsets.
	•	Achieve minimal re-work on every keystroke, ideal for large codebases or deep ASTs.

Both designs share key elements—error-tolerant lexing, precise node spans (or leaf refs), and an injectable parse entry point—but differ in granularity and engineering effort. Start simple, then layer on the fine-grained incremental architecture as needs dictate.


Here’s a step-by-step recipe for implementing Approach 1’s “coarse invalidation”—showing exactly how to update the AST (and its spans) when tokens after the cursor are discarded and re-parsed.

⸻

1. Preliminaries: Spans on AST Nodes

First, make sure every AST node carries an explicit span:

%Node{
  type: ...,
  children: [...],
  meta: %{start_pos: {line, col}, end_pos: {line, col}, ...}
}

Whenever you build a node, you compute:

start_pos = leftmost_child.meta.start_pos
end_pos   = rightmost_child.meta.end_pos

(or, for leaf nodes, use the token’s own start_pos and end_pos).

⸻

2. Detecting the Dirty Region

On a text edit that begins at absolute offset E:
	1.	Compute edit_offset = number of characters before the change (you already track this in your editor integration).
	2.	Mark as dirty any token whose token.end_pos_char_index > edit_offset.
	3.	Mark as dirty any AST node whose meta.end_pos_char_index > edit_offset.

In practice you can pre-compute a flattened list of nodes sorted by start offset, so you can binary-search the first node ending after E.

⸻

3. Choosing the Re-parse Root

Rather than throw away the entire AST, pick the smallest retained node whose span contains edit_offset. Call this node R. All of R’s subtree is now considered invalid and will be re-parsed.

find_reparse_root(ast, edit_offset) ->
  traverse_down(ast, edit_offset)
where
  traverse_down(node, off) do
    Enum.find_value(node.children, fn child ->
      if child.meta.start_pos_char_index <= off and off <= child.meta.end_pos_char_index do
        traverse_down(child, off)
      end
    end) || node
  end


⸻

4. Invalidate Tokens and AST Subtrees
	1.	Slice your token list into

{prefix_tokens, suffix_tokens} = Enum.split_while(tokens, fn t -> t.end_pos_char_index <= edit_offset end)


	2.	Drop suffix_tokens.
	3.	Detach R from its parent (P), and remember the position in P.children where it lived.

⸻

5. Re-lex and Re-parse
	1.	Re-lex starting at edit_offset through end-of-file, producing new_suffix_tokens.
	2.	Append them to prefix_tokens → all_tokens.
	3.	Invoke your Pratt entry point on the token slice corresponding to R’s span start:

{new_subtree, leftover_tokens} = parse_from(tokens = all_tokens |> drop_prefix_before(R.meta.start_pos), state = initial_state_for_R)


	4.	Verify that leftover_tokens aligns with the old suffix start (i.e. you didn’t accidentally skip or double-parse anything).

⸻

6. Splicing the New Subtree
	1.	Insert new_subtree back into P.children at the original index where R was.
	2.	Replace the parser’s token buffer with all_tokens for future edits.

⸻

7. Recomputing Parent Spans

Because you replaced R with new_subtree, every ancestor of new_subtree may now have different end_pos. Bottom-up:

update_spans(node) do
  %{children: kids} = node
  start = Enum.min_by(kids, & &1.meta.start_pos_char_index).meta.start_pos_char_index
  end_  = Enum.max_by(kids, & &1.meta.end_pos_char_index).meta.end_pos_char_index
  %{ node | meta: Map.put(node.meta, :start_pos_char_index, start)
                   |> Map.put(:end_pos_char_index,   end_) }
end

Walk from P up to the root, calling update_spans/1 at each level.

⸻

8. Putting It All Together

def incremental_update(ast, tokens, edit_offset, new_text) do
  # 1. Find and detach
  R = find_reparse_root(ast, edit_offset)
  {P, idx} = detach_child(ast, R)

  # 2. Invalidate tokens
  prefix = Enum.take_while(tokens, &(&1.end_pos_char_index <= edit_offset))

  # 3. Re-lex suffix
  new_suffix = tokenize(new_text, start_at: edit_offset, opts: [:tolerant])
  all_tokens = prefix ++ new_suffix

  # 4. Parse new subtree
  {new_subtree, _} = parse_from(all_tokens, at_pos: R.meta.start_pos)

  # 5. Splice back and recompute spans
  P2 = insert_child(P, new_subtree, idx)
  P3 = recompute_ancestor_spans(P2)
  ast2 = reconnect(ast, old_parent: P, new_parent: P3)

  {ast2, all_tokens}
end

Why This Works
	•	Coarse invalidation guarantees correctness: anything that could be affected by the edit is thrown away.
	•	You only re-lex/re-parse from the nearest meaningful syntactic boundary (the re-parse root) down, rather than from the very top.
	•	By recomputing spans on ancestors you restore accurate start/end positions throughout the tree.
	•	This keeps most of your old AST intact, preserves identity for nodes before the edit, and avoids a full-file re-parse on every keystroke (assuming edits are small and trees deep).

⸻

Performance Considerations
	•	If your language has natural “statement boundaries” (e.g. semicolons, end tokens), you can often choose R to be the enclosing statement, not the smallest node, trimming your re-parse scope even more.
	•	For very frequent small edits, you can throttle incremental updates (e.g. debounce 50 ms) to batch contiguous keystrokes.

With this in place, you get reasonably fine-grained incremental parsing using only absolute offsets and your existing Pratt machinery—no fancy data structures required.

##############

To marry your Pratt parser’s fuel‐based error‐recovery with a truly streaming, on‐demand lexer, you’ll want to turn lexing from a “produce the whole list up front” step into a lazy process that hands tokens to the parser one at a time—charging parser fuel both for parsing work and for the lex requests that drive it. Here’s how you can do it:

⸻

1. Refactor the Lexer into a Pull‐Based Iterator
	1.	Lexer State as Opaque Handle
Package up (RemainingCode, LineColState, Scope, TerminatorStack) into a single opaque record or closure (e.g. LexState).
	2.	next_token/1 API
Replace your batch tokenize/5 with a function:

-spec next_token(LexState) -> {Token, NewLexState}.

It consumes exactly up to the next token (including any error‐tokens or synthetic closers), updates line/col and scope, and returns the updated state.

	3.	peek_token/1 via Pushback
Build a tiny wrapper that lets you “peek” by calling next_token/1 and then storing the returned (Token, NewLexState) in a one‐slot buffer, so a subsequent next_token/1 will return the buffered token.

⸻

2. Embed Fuel Consumption into Parser–Lexer Interaction
	1.	Unify Fuel and Lex Calls
Every time the Pratt parser calls next/0 or peek/0, wrap that call in your consume_fuel/1 logic. For example:

get_next_token(Parser = #parser{fuel = Fuel, lex_state = LS}) ->
  case Fuel =< 0 of
    true  -> {error, no_fuel_remaining, Parser};
    false ->
      {Tok, LS2} = lex:next_token(LS),
      Parser2 = Parser#parser{fuel = Fuel - 1, lex_state = LS2, current_token = Tok},
      {ok, Parser2}
  end.


	2.	Fuel for Syntax Workflows
If you have complex led or nud handlers that do multi‐step lookahead (e.g. to distinguish postfix vs. call), subtract additional fuel per lookahead or per subtree.

⸻

3. On‐Demand Lexing in Incremental Contexts
	1.	Range‐Based Lexing
Give your LexState the concept of a text offset. That way, lexing “from 0 to N” is just a matter of initializing the state with the file binary and offset 0; lexing “from M to cursor” is just starting at offset M.
	2.	Partial Replay & Reuse
	•	Attach a token ID (e.g. hash of binary slice + start offset) when you emit each token.
	•	On edits, only rebuild the LexState for the edited range; keep old LexState handles (and their cached tokens) for unmodified ranges so the parser can switch streams without re‐lexing.
	3.	Lazy Interpolation
When you encounter a sigil or string interpolation, don’t lex the entire nested fragment at once. Instead, return a special :begin_interp token, then let the parser drive lexing inside until it consumes :end_interp. That automatically bounds nested lex work to what the parser actually needs.

⸻

4. Error Recovery & Fuel Exhaustion
	1.	Synchronized Error Tokens
When next_token/1 hits a lex error, it now emits {error, Pos, Reason} and advances to the next synchronization point (e.g. ;\n, matching ], or end of file), so the parser sees and can recover from the error inline—still charged against fuel.
	2.	Graceful Fuel Exhaustion
If fuel hits zero mid‐lex—or mid‐parse—return a sentinel token (e.g. {error, Pos, no_fuel}) to the parser instead of throwing. That lets the parser wrap up the current expression and hand back a partial AST with a “fuel‐exhausted” diagnostic.

⸻

5. Putting It All Together
	1.	Initialize

LexState0 = lex:init(FileBinary, 0, TolerantMode),
Parser0  = #parser{fuel=MaxFuel, lex_state=LexState0},


	2.	Drive Parsing
Every parse_expression/6, get_next_token, peek_token, and synthetic‐closer routine goes through your new fuel‐aware driver.
	3.	Incremental Updates
When the user edits—say at byte B to C—re‐init a new LexState for just that slice, and splice tokens (by ID) back into the old parser’s token stream. Fuel, error tokens, and lex state stay localized to what actually changed.

⸻

With that architecture, every parser step and every lex request pays into the same fuel meter, lexing happens only as the parser asks for it, and you’ve got built-in hooks for error tokens, sync points, and incremental reuse.


You’re right—those in-flight edits (newline coalescing and do/keyword disambiguation) break the pure “emit-and-forget” model that a streaming lexer+parser depend on.  Here are three complementary strategies to tame them:

⸻

1. Turn Mutations into Deferred Rewrite Events

Instead of literally mutating a past token, have the lexer:
	1.	Buffer the last N tokens (e.g. just the previous one in the case of newline-coalescing, or the last two for do-disambiguation).
	2.	Emit only when they’re “stable” (i.e. when you know no future input can change them).
	3.	When you detect a situation that would have mutated them, emit a small “patch” event:

{patch_prev, TokenID, NewToken}


	4.	Your token‐stream abstraction applies patches to its internal buffer and propagates them to the parser before processing further tokens.

Pros:
	•	Parser sees a correct, immutable stream.
	•	You only delay emission a tiny window, so lookahead remains low-latency.

Cons:
	•	Slight buffering complexity.
	•	You have to be very sure you know exactly how far back mutations can reach.

⸻

2. Eliminate Back‐Patching by Extending the Matching Grammar

Where feasible, refactor those rules so you don’t need to go back:
	•	Newline aggregation:
Rather than coalescing after the fact, have the lexer’s EOL rule match /\n(\s*\n)*/ as a single multi-EOL token.
	•	do disambiguation:
Use a tiny lookahead in the lexer clause that matches do + whitespace + do:-style constructs versus block introduces, emitting two distinct token kinds (:kw_do_block vs. :kw_do_kwlist) right away.

Pros:
	•	Tokens are correct on first emission—no mutation or buffering needed.
	•	Simplifies your streaming API.

Cons:
	•	Lexer rules become more complex, potentially duplicating some parser logic.
	•	Harder to maintain if the grammar evolves.

⸻

3. Versioned Tokens with Incremental Invalidations

If you need to support full incremental re-lexing:
	1.	Give each token a stable ID (e.g. hash of its start_pos + raw text).
	2.	Expose a patch API on your lex stream:

{patch, TokenID, NewToken}


	3.	When the lexer mutates a past token, it simply re-emits that patch.
	4.	The parser’s incremental driver watches for patch events and updates any cached AST nodes whose span overlaps the old token’s span (marking them dirty for re-parse).

Pros:
	•	Fully incremental: you only touch the AST subtrees that truly changed.
	•	You can record token provenance and maintain precise reuse.

Cons:
	•	Requires an incremental AST framework (or at least cache-invalidation hooks).
	•	More bookkeeping in both lexer and parser.

⸻

Putting It into Practice
	1.	Choose a baseline:
	•	If you just need streaming with minimal buffer, go with Option 1.
	•	If you’re comfortable enriching your lex grammar, go with Option 2.
	•	If you’re already building an incremental pipeline around token IDs, layer in Option 3.
	2.	Implement the minimal buffer:
	•	In your new next_token/1 iterator, keep a one-token look-behind in the state.
	•	Only emit that buffered token once the next token is scanned and you know no mutation applies.
	3.	Emit patch events:
	•	Introduce an event type in your lex API:

type token_event() ::= {token, Token} | {patch, TokenID, Token}.


	•	Make the parser driver apply both kinds of events in order.

	4.	Adjust the parser driver to accept patches:
	•	When it sees {patch, ID, NewTok}, find the matching entry in its lookahead buffer or AST cache and replace it.

⸻

By buffering just enough to catch mutation points—or better yet, folding mutations into your lex rules—you restore the invariant that once a token is handed off, it never changes.  Pair that with patch events or immutable re-emission, and your Pratt parser can safely consume a clean, stable stream.
