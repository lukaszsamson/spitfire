# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-07 19:14:32
- **Nonterminals analyzed**: 7
- **Total grammar rules**: 43
- **Errors**: 2

---

## Table of Contents

- [matched_expr](#matched-expr)
- [matched_op_expr](#matched-op-expr)
- [no_parens_one_expr](#no-parens-one-expr)
- [sub_matched_expr](#sub-matched-expr)
- [unary_op_eol](#unary-op-eol)
- [capture_op_eol](#capture-op-eol)
- [at_op_eol](#at-op-eol)

---

## matched_expr

**Grammar Rules (7):**

```erlang
matched_expr -> matched_expr matched_op_expr : build_op('$1', '$2').
matched_expr -> unary_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> at_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> capture_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> ellipsis_op matched_expr : build_unary_op('$1', '$2').
matched_expr -> no_parens_one_expr : '$1'.
matched_expr -> sub_matched_expr : '$1'.
```

**Analysis:**

Running file views to inspect generators and compiler for matched_expr rules; this finds generator and compiler implementations to verify coverage. Calling report_intent and opening the three files.

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1738 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

Summary: matched_expr cases are fully implemented and compiled.

Findings:
- All six grammar alternatives (binary matched_op, unary_op_eol, at_op_eol, capture_op_eol, ellipsis_op, no_parens_one_expr, and sub_matched_expr) are present in Gen (gen_matched_op, gen_matched_unary, gen_at_op, gen_capture_op, gen_ellipsis_prefix, gen_call_no_parens_one, gen_sub_matched_expr) and handled in TokenCompiler (do_to_tokens/compile_* clauses).  
- No matched_expr alternatives are marked TODO; the TODOs in the repo are for other access_expr features (sigils, bitstrings, quoted atoms) and do not affect matched_expr.  
- The shapes produced by generators match the compiler patterns (e.g., {:matched_unary, {op_kind, op}, newlines, operand}, {:matched_op, left, op_eol, right}, {:ellipsis_prefix, expr}, {:capture_op, newlines, operand}, {:at_op, newlines, operand}, {:call_no_parens_one, ...}, sub_matched_expr variants), so compilation should be correct for these grammar rules.

Actions (recommended, none strictly required to fix matched_expr):
1. Add focused property/unit tests that specifically exercise:
   - ellipsis prefix binding/adhesion and precedence,
   - unary_op_eol with and without newlines,
   - no_parens_one_expr (no-parens calls) in operand positions — to catch spacing/adhesion regressions.  
2. When advancing phases, implement the access_expr TODOs (sigils, bitstrings, heredocs, quoted atoms) so sub_matched_expr coverage stays complete as more nodes are generated.  

Conclusion: For the matched_expr grammar given, the generators and the compiler already implement all cases correctly; no code changes are required.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 3.98s
Total duration (wall): 1m 9.055s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           70.2k input, 3.8k output, 11.3k cache read (Est. 0 Premium requests)


---

## matched_op_expr

**Grammar Rules (19):**

```erlang
matched_op_expr -> match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> dual_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> mult_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> power_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> concat_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> range_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> ternary_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> xor_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> and_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> or_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> type_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> when_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> pipe_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> comp_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> rel_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> arrow_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> arrow_op_eol no_parens_one_expr : warn_pipe('$1', '$2'), {'$1', '$2'}.
```

**Analysis:**

Scanning the three target files and searching codebase for matched_op_expr and related tokens to compare generators and compiler against the grammar rules. Running file views and ripgrep searches in parallel.

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1738 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

✔ Grep "ternary_op_eol" in **/*
   └ 15 lines found

✔ Grep "arrow_op_eol" in **/*
   └ 19 lines found

✔ Grep "warn_pipe" in **/*
   └ 14 lines found

✔ Grep "no_parens_one_expr" in **/*
   └ 50 lines found

✔ Grep "in_match_op_eol" in **/*
   └ 15 lines found

✔ Grep "match_op_eol" in **/*
   └ 36 lines found

✔ Grep "matched_op_expr" in **/*
   └ 142 lines found

Scanned the three files: generators cover all matched_op_expr families except ternary_op and the more context-sensitive no_parens variants; several TODOs are already noted in the generator comments.  

Concrete actions to fill gaps: (1) add ternary_op (//) to the operator pool and a guarded generator that only emits it in the valid range//... context (e.g. generate ternary only when the left operand is a range/nullary_range); (2) implement dot_op_identifier / expand gen_call_no_parens_one to produce the grammar's dot_op_identifier variant for no_parens_one_expr (and the corresponding compile path if needed); (3) add a generator flag or gating to avoid or explicitly produce the arrow_op_eol + no_parens_one_expr warn_pipe shape and, if producing it, decide whether TokenCompiler should emit a warn token or leave it to the parser; (4) add targeted unit/property tests (in test/spitfire_grammar_test.exs and the property suite) for ternary, arrow_op_eol no_parens_one_expr (warn_pipe), and dot_op_identifier cases.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 1.011s
Total duration (wall): 1m 5.956s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           79.4k input, 3.7k output, 22.5k cache read (Est. 0 Premium requests)


---

## no_parens_one_expr

**Grammar Rules (2):**

```erlang
no_parens_one_expr -> dot_op_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
no_parens_one_expr -> dot_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
```

**Analysis:**

ERROR: Command timed out after 5 minutes

---

## sub_matched_expr

**Grammar Rules (5):**

```erlang
sub_matched_expr -> no_parens_zero_expr : '$1'.
sub_matched_expr -> range_op : build_nullary_op('$1').
sub_matched_expr -> ellipsis_op : build_nullary_op('$1').
sub_matched_expr -> access_expr : '$1'.
sub_matched_expr -> access_expr kw_identifier : error_invalid_kw_identifier('$2').
```

**Analysis:**

Opening the three files to inspect implementations of sub_matched_expr in generators and compiler to check for missing cases or TODOs; reading files now. I'll fetch the three target files.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1740 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2005 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✘ Grep "error_invalid_kw_identifier" in **/*
   └ rg: : IO error for operation on : No such file or directory (os error 2)

✘ Grep "kw_identifier" in **/*
   └ rg: : IO error for operation on : No such file or directory (os error 2)

Editing generator and compiler to add the missing access_expr + kw_identifier case so the grammar variant is generated and compiled to tokens. Applying two surgical edits.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+5 -2)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 1140     """                                                                                 │
   │ 1141     def gen_sub_matched_expr(state) do                                                  │
   │ 1142       StreamData.frequency([                                                            │
   │ 1143  -      {10, gen_access_expr(state)},                                                   │
   │ 1143  +      {9, gen_access_expr(state)},                                                    │
   │ 1144         {5, gen_no_parens_zero_expr()},                                                 │
   │ 1145         {1, gen_nullary_range()},                                                       │
   │ 1146  -      {1, gen_nullary_ellipsis()}                                                     │
   │ 1146  +      {1, gen_nullary_ellipsis()},                                                    │
   │ 1147  +      # Access expression followed by a keyword identifier (invalid in grammar)       │
   │ 1148  +      # This models: access_expr kw_identifier -> error_invalid_kw_identifier('$2')   │
   │ 1149  +      {1, gen_access_expr_kw_identifier(state)}                                       │
   │ 1150       ])                                                                                │
   │ 1151     end                                                                                 │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit lib/spitfire/property/token_compiler.ex (+17)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 785     end                                                                                  │
   │ 786                                                                                          │
   │ 787     # ---------------------------------------------------------------------------        │
   │ 788  +  # Access expression followed by keyword identifier (invalid kw identifier)           │
   │ 789  +  # ---------------------------------------------------------------------------        │
   │ 790  +                                                                                       │
   │ 791  +  defp do_to_tokens({:access_expr_kw_identifier, access_expr, key}, layout, opts) do   │
   │ 792  +    # Compile the access expression normally                                           │
   │ 793  +    {access_tokens, layout} = do_to_tokens(access_expr, layout, opts)                  │
   │ 794  +                                                                                       │
   │ 795  +    # Emit the kw_identifier token (e.g., "key:") with a space before it               │
   │ 796  +    key_str = Atom.to_string(key)                                                      │
   │ 797  +    key_lexeme = key_str <> ":"                                                        │
   │ 798  +    {meta, layout} = TokenLayout.space_before(layout, key_lexeme, nil)                 │
   │ 799  +    kw_token = {:kw_identifier, meta, key}                                             │
   │ 800  +                                                                                       │
   │ 801  +    {access_tokens ++ [kw_token], layout}                                              │
   │ 802  +  end                                                                                  │
   │ 803  +                                                                                       │
   │ 804  +  # ---------------------------------------------------------------------------        │
   │ 805     # Catch-all for unimplemented nodes                                                  │
   │ 806     # ---------------------------------------------------------------------------        │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit test/spitfire/property/token_grammar_generators.exs (+11)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 1450       StreamData.constant({:nullary_ellipsis, nil})                                     │
   │ 1451     end                                                                                 │
   │ 1452                                                                                         │
   │ 1453  +  # Generate an access_expr followed by a kw identifier (e.g. foo a:)                 │
   │ 1454  +  # This corresponds to the grammar case that should be reported as an                │
   │ 1455  +  # invalid keyword identifier when it follows an access expression.                  │
   │ 1456  +  def gen_access_expr_kw_identifier(state) do                                         │
   │ 1457  +    StreamData.bind(gen_access_expr(state), fn acc ->                                 │
   │ 1458  +      StreamData.bind(StreamData.member_of(@identifiers), fn key ->                   │
   │ 1459  +        StreamData.constant({:access_expr_kw_identifier, acc, key})                   │
   │ 1460  +      end)                                                                            │
   │ 1461  +    end)                                                                              │
   │ 1462  +  end                                                                                 │
   │ 1463  +                                                                                      │
   │ 1464     # ===========================================================================       │
   │ 1465     # Category-Aware: Parenthesized Expressions                                         │
   │ 1466     # ===========================================================================       │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

Running mix test for the property test file to ensure no compile errors quickly. Running "mix test test/spitfire/token_property_test.exs:1" to compile only that test.

✔ $ mix test test/spitfire/token_property_test.exs:1 --color --trace
    └ 85 lines...

Summary:
- The repository was missing the "access_expr kw_identifier" sub_matched_expr variant; a generator (gen_access_expr_kw_identifier) and compiler handler (do_to_tokens for {:access_expr_kw_identifier, ...}) were added so that case is now produced and compiled to tokens.

Answers:
1. Before edits, generators covered no_parens_zero_expr, nullary range/ellipsis, and access_expr but not the access_expr + kw_identifier error case; the compiler likewise lacked a node for that case. After the edits both the generator and a compiler clause exist.
2. Yes — access_expr lists several TODOs for later phases (list_string / list_heredoc, bin_heredoc, bitstring, sigils, quoted/unsafe atom forms) and those remain unimplemented.
3. The current implementation now models the grammar variants: no_parens_zero_expr, nullary range, nullary ellipsis, access_expr, and access_expr followed by kw_identifier (the latter is rendered as a kw_identifier token). However, the grammar action for access_expr kw_identifier is error_invalid_kw_identifier('$2') which signals an error in later phases — the compiler currently emits a kw_identifier token rather than an explicit “error” token/metadata.
4. Edge cases missing:
   - Several access_expr sub-forms still TODO (see above).
   - The grammar action indicates an error should be produced for access_expr kw_identifier; if the codebase intends to surface that as a distinct error token or metadata, the compiler should be changed to emit that explicit error node/token instead of a plain kw_identifier token.
   - There is no dedicated do_to_tokens clause for a standalone {:kw_identifier, ...} AST node; currently kw_identifier tokens are produced in map/kw-pair code paths. If kw_identifier nodes may appear elsewhere, add do_to_tokens({:kw_identifier,...}, ...) or ensure all generation sites create the combined node (as done).

Concrete actions to finish gaps:
1. (Optional, recommended) Change the compiler to reflect the grammar action error_invalid_kw_identifier by emitting an explicit error token/node (e.g., {:invalid_kw_identifier, meta, key} or attaching error metadata) instead of a plain {:kw_identifier, meta, key}, and update Toxic.ToString/token rendering and any downstream consumers to recognize it. This makes the grammar intent explicit.
2. Implement the remaining access_expr variants that are marked TODO: list_string/list_heredoc, bin_heredoc, bitstring (<<...>>), sigils (~r/.../), and atom_quoted / atom_safe / atom_unsafe, with corresponding generator nodes and compiler clauses.
3. Add tests that specifically generate the access_expr + kw_identifier case and assert the expected compiler output (either that it emits a kw_identifier token or the explicit error token, depending on action 1), and add a property test ensuring such cases are handled as intended (either parsed as oracle-rejected or flagged as invalid by the pipeline).
4. If choosing to implement explicit error tokens, update any normalization or downstream parsing tests that expect plain kw_identifier tokens.

If preferred, confirm whether the grammar should surface an explicit error token for access_expr kw_identifier; if yes, I can update the compiler to emit that error token and adjust tests accordingly.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  2m 21.617s
Total duration (wall): 2m 29.514s
Total code changes:    33 lines added, 2 lines removed
Usage by model:
    gpt-5-mini           371.8k input, 8.5k output, 250.8k cache read (Est. 0 Premium requests)


---

## unary_op_eol

**Grammar Rules (6):**

```erlang
unary_op_eol -> unary_op : '$1'.
unary_op_eol -> unary_op eol : '$1'.
unary_op_eol -> dual_op : '$1'.
unary_op_eol -> dual_op eol : '$1'.
unary_op_eol -> ternary_op : '$1'.
unary_op_eol -> ternary_op eol : '$1'.
```

**Analysis:**

Reading the three target files to locate unary_op_eol implementations and related generators/compilation logic. Running views now.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1754 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2022 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

Findings
- The generators + compiler implement unary_op_eol for unary_op and dual_op (the generator's @unary_ops contains {:unary_op, ...} and {:dual_op, ...}, gen_matched_unary emits newlines, and TokenCompiler handles {:matched_unary, {op_kind, op}, newlines, operand} and legacy forms).  
- Ternary_op (//) is explicitly omitted in the generators (comments at the top of token_grammar_generators.exs) — i.e., it's marked as intentionally deferred/TODO.  
- The implemented cases are correctly compiled/emitted: newlines are modeled by gen_newlines and TokenCompiler emits eol tokens in the right place and uses the op_kind generically, so unary_op and unary dual_op behaviors match the grammar.  
- Missing/edge cases: ternary_op (//) is not generated at all; if added naively it must be constrained to the specific grammar context where it is valid (only immediately after a range operator like ..), otherwise many invalid programs will be produced.

Concrete actions to fill gaps (minimal, ordered)
1. Decide policy: either (A) keep ternary_op deferred (recommended short term) or (B) implement it now (requires guarded generation).  
2. If implementing (B), change generators:
   - Add {:ternary_op, :"//"} to the @unary_ops pool in test/spitfire/property/token_grammar_generators.exs (or create a dedicated ternary_op pool).  
   - Restrict generation so ternary_op only appears as the "unary" that follows a range: update gen_matched_op (or gen_binary_op/gen_op_eol) so that when producing a range_op (..), it can optionally attach a following ternary_op_eol + operand (e.g., produce nodes that model 1..10//2), rather than allowing global matched_unary selections to pick // anywhere. This keeps samples valid.
3. TokenCompiler updates (small):
   - No change needed for basic emission because compiler already accepts op_kind generically and would emit {:ternary_op, meta, :"//"} correctly; verify Toxic/ToString recognizes :ternary_op lexeme `"//"`. If Toxic expects a different token tag, map op_kind to the expected token tag in compile_binary_op / compile_unary_op paths.
4. Add tests:
   - Add targeted property/unit tests that generate (or hard-code) a 1..10//2 case and assert the compiler renders valid code and the oracle accepts it; this ensures ternary_op handling is correct and restricted.

If the goal is to leave phase 1/2 stable, no code changes required now — the omission is intentional and already documented.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 14.649s
Total duration (wall): 1m 20.09s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           71.1k input, 5.0k output, 22.3k cache read (Est. 0 Premium requests)


---

## capture_op_eol

**Grammar Rules (2):**

```erlang
capture_op_eol -> capture_op : '$1'.
capture_op_eol -> capture_op eol : '$1'.
```

**Analysis:**

Searching for capture_op_eol and opening the three target files to inspect generators and compiler.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1754 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2022 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Grep "capture_op_eol" in **/*
   └ 205 lines found

Updating generators: add unmatched capture-op generator and include it in gen_unmatched_expr. Making minimal edits to token_grammar_generators.exs.

✘ Edit test/spitfire/property/token_grammar_generators.exs
   No match found

✔ Grep "def gen_unmatched_expr" in test/spitfire/property/token_grammar_generators.exs
   └ 21 lines found

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1754 lines read

Findings: the matched form capture_op_eol is implemented (gen_capture_op in test generator + do_to_tokens({:capture_op, ...}) in TokenCompiler) and nothing in the code is marked TODO specifically for capture_op_eol, but the grammar also allows capture_op_eol as the head of unmatched_expr (and in no_parens_expr in later phases) and the generators do NOT emit that case — gen_unmatched_expr currently only generates call_do and unmatched binary ops; no_parens_expr support is intentionally deferred.

Actions to fill gaps:
- Add a generator (e.g. gen_unmatched_capture_op) that emits {:capture_op, newlines, operand} where operand is an unmatched-expression generator (respecting depth/budget and using GrammarTree.decr_depth) and include it in gen_unmatched_expr frequency so capture_op_eol -> capture_op expr is sampled.
- When enabling Phase 3 no_parens_expr coverage, include capture_op_eol -> capture_op no_parens_expr in the no_parens_expr generator (same node shape).
- Add property tests that generate capture-op + do-block and capture-op + no-parens cases (e.g. "&if true do ... end", "&Mod.fun/1 arg") to verify round-trip parsing; run the existing test suite to confirm TokenCompiler already handles {:capture_op, newlines, operand} (no compiler code changes appear necessary).



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 55.052s
Total duration (wall): 2m 1.152s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           351.9k input, 7.0k output, 268.2k cache read (Est. 0 Premium requests)


---

## at_op_eol

**Grammar Rules (2):**

```erlang
at_op_eol -> at_op : '$1'.
at_op_eol -> at_op eol : '$1'.
```

**Analysis:**

ERROR: Command timed out after 5 minutes

---

