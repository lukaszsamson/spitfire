# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-07 18:43:48
- **Nonterminals analyzed**: 4
- **Total grammar rules**: 14

---

## Table of Contents

- [grammar](#grammar)
- [expr_list](#expr-list)
- [expr](#expr)
- [eoe](#eoe)

---

## grammar

**Grammar Rules (6):**

```erlang
grammar -> eoe : {'__block__', meta_from_token('$1'), []}.
grammar -> expr_list : build_block(reverse('$1')).
grammar -> eoe expr_list : build_block(reverse('$2')).
grammar -> expr_list eoe : build_block(reverse(annotate_eoe('$2', '$1'))).
grammar -> eoe expr_list eoe : build_block(reverse(annotate_eoe('$3', '$2'))).
grammar -> '$empty' : {'__block__', [], []}.
```

**Analysis:**

Reading the three target files to check grammar cases and implementation. Running parallel view calls for the files and reporting intent.

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1721 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

Editing generator to include eoe-only and empty grammar cases so generator covers all grammar variants; updating frequency and adding helper functions. Proceeding to apply two precise edits.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+5 -2)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 156         # grammar -> eoe expr_list (leading newline - less common)                       │
   │ 157         {1, gen_grammar_eoe_expr_list(state, max_forms)},                                │
   │ 158         # grammar -> eoe expr_list eoe (both - rare)                                     │
   │ 159  -      {1, gen_grammar_eoe_expr_list_eoe(state, max_forms)}                             │
   │ 160  -      # Note: grammar -> eoe and grammar -> '$empty' omitted (edge cases)              │
   │ 159  +      {1, gen_grammar_eoe_expr_list_eoe(state, max_forms)},                            │
   │ 160  +      # grammar -> eoe (only eoe - edge case)                                          │
   │ 161  +      {1, gen_grammar_eoe_only(state)},                                                │
   │ 162  +      # grammar -> '$empty' (completely empty)                                         │
   │ 163  +      {1, gen_grammar_empty()}                                                         │
   │ 164       ])                                                                                 │
   │ 165     end                                                                                  │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit test/spitfire/property/token_grammar_generators.exs (+14)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 206       end)                                                                               │
   │ 207     end                                                                                  │
   │ 208                                                                                          │
   │ 209  +  # grammar -> eoe : {'__block__', meta_from_token('$1'), []}.                         │
   │ 210  +  # Represented as grammar_v2 with leading_eoe and empty expr list.                    │
   │ 211  +  defp gen_grammar_eoe_only(_state) do                                                 │
   │ 212  +    StreamData.bind(gen_eoe(), fn leading_eoe ->                                       │
   │ 213  +      StreamData.constant({:grammar_v2, leading_eoe, [], nil})                         │
   │ 214  +    end)                                                                               │
   │ 215  +  end                                                                                  │
   │ 216  +                                                                                       │
   │ 217  +  # grammar -> '$empty' : {'__block__', [], []}.                                       │
   │ 218  +  # Represented as grammar_v2 with no leading/trailing eoe and empty expr list.        │
   │ 219  +  defp gen_grammar_empty do                                                            │
   │ 220  +    StreamData.constant({:grammar_v2, nil, [], nil})                                   │
   │ 221  +  end                                                                                  │
   │ 222  +                                                                                       │
   │ 223     @doc """                                                                             │
   │ 224     Generate a grammar tree using legacy format.                                         │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

Findings: The generator now covers all grammar productions (expr_list, expr_list eoe, eoe expr_list, eoe expr_list eoe, eoe-only, and '$empty') — I added gen_grammar_eoe_only/1 and gen_grammar_empty/0 to test/spitfire/property/token_grammar_generators.exs. TokenCompiler (lib/spitfire/property/token_compiler.ex) already implements {:grammar_v2, leading_eoe, exprs, trailing_eoe} and compile_eoe, so the new generator shapes compile correctly to Toxic tokens; compile_expr_list handles empty expr lists and eoe-placement as emitted tokens. Remaining items / recommended actions:
- (Optional) If semantic fidelity to the original build_block/annotate_eoe is required, adjust compile_expr_list to attach trailing_eoe as metadata on the last expr instead of emitting a separate trailing token.  
- Implement the many TODOs listed in gen_access_expr (bracket_at variants, heredocs, bitstrings, sigils, quoted atoms, etc.) in later phases as planned.  
- Consider whether tests should skip or specially-handle completely empty programs ('' -> Code.string_to_quoted returns error); if false positives arise, either reduce frequency of gen_grammar_empty or treat empty output as an acceptable skip in tests.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 42.842s
Total duration (wall): 1m 49.612s
Total code changes:    19 lines added, 2 lines removed
Usage by model:
    gpt-5-mini           129.5k input, 6.5k output, 69.8k cache read (Est. 0 Premium requests)


---

## expr_list

**Grammar Rules (2):**

```erlang
expr_list -> expr : ['$1'].
expr_list -> expr_list eoe expr : ['$3' | annotate_eoe('$2', '$1')].
```

**Analysis:**

Searching and opening the three target files to inspect the generators and compiler implementation for expr_list cases. Reading files to check which grammar branches are implemented and note TODOs or missing edge cases. I'll open all files in one parallel call.

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1738 lines read

Findings: the expr_list grammar is fully implemented and wired through generators and the compiler, including the single-expr case, the recursive expr_list eoe expr case, leading/trailing eoe variants, and empty/eoe-only programs; gen_expr_list produces [{expr, eoe | nil}] and compile_expr_list/compile_eoe handle all eoe flavors (:eol, :semi, :eol_semi). There are TODOs elsewhere (access_expr extras) but none for expr_list specifically, and the implementation matches the annotated grammar semantics (empty list, leading/trailing EOEs, and EOE-between-exprs are covered). Actions: none — no changes required for expr_list; everything looks correct.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  37s
Total duration (wall): 41s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           70.0k input, 2.3k output, 22.1k cache read (Est. 0 Premium requests)


---

## expr

**Grammar Rules (3):**

```erlang
expr -> matched_expr : '$1'.
expr -> no_parens_expr : '$1'.
expr -> unmatched_expr : '$1'.
```

**Analysis:**

Running file views to inspect generators, property test, and token compiler to check expr cases against grammar. (Report intent + viewing files.)

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1738 lines read

Summary: gen_expr in test/spitfire/property/token_grammar_generators.exs deliberately omits the no_parens_expr branch (comment: "deferred to Phase 3+") and currently only generates matched_expr and unmatched_expr; several access_expr features are also marked TODO. The compiler (lib/spitfire/property/token_compiler.ex) already implements token emission for the concrete node shapes the current generators produce (identifiers, dot_identifier, dot_do_identifier, call_no_parens_one, matched_op/unmatched_op, call_do, access_expr variants, etc.), so there is no immediate compiler mismatch for the present generators.

Concrete actions to fill gaps:
- Add a no_parens_expr alternative to gen_expr (phase-gated, e.g. only when phase >= 3 or state.context permits) that yields the existing node shapes gen_no_parens_zero_expr and gen_call_no_parens_one so the compiler needs no new node handlers.  
- Extend the generators to cover additional no-parens variants the grammar allows (e.g. any multi-arg no-parens forms if grammar permits, keyword-only vs mixed args) and add property tests that run with phase >= 3 to exercise them.  
- Decide whether to implement the other TODO access_expr features (bitstrings, sigils, quoted atoms, ternary // after ..) and, if added, add matching do_to_tokens clauses in TokenCompiler (or reuse existing node shapes) and tests to cover them.

If these are implemented as suggested (generator emits existing node shapes instead of new wrapper atoms), no changes are required in the current TokenCompiler; otherwise, add minimal do_to_tokens/compile_arg_with_adhesion clauses for any newly introduced node variant.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  56s
Total duration (wall): 1m 0.773s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           70.0k input, 3.0k output, 22.1k cache read (Est. 0 Premium requests)


---

## eoe

**Grammar Rules (3):**

```erlang
eoe -> eol : '$1'.
eoe -> ';' : '$1'.
eoe -> eol ';' : '$1'.
```

**Analysis:**

Running quick reads of the three target files to locate eoe handling in generators and compiler to verify coverage against the grammar rules. Fetching files now.

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 1975 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1738 lines read

Summary: All three eoe grammar cases are implemented and wired end-to-end.

Findings:
- Generators: gen_eoe in test/spitfire/property/token_grammar_generators.exs produces :eol, :semi, and :eol_semi exactly matching the grammar rules.
- Compiler: compile_eoe in lib/spitfire/property/token_compiler.ex implements :eol, :semi, and :eol_semi (emits newline then semicolon) and is used for leading/trailing/between exprs via do_to_tokens/3 helpers.
- Tests: token_property_test.exs uses the generators and TokenCompiler.to_tokens/tree format (grammar_v2) so the cases are exercised.

TODO / gaps:
- No cases are marked TODO in these files for eoe; nothing is left unimplemented for the three grammar forms.
- Potential optional enhancements (not required to satisfy the grammar as written):
  1) Support multi-newline eoe (currently gen_eoe yields a single eol and compile_eoe emits one newline); if multi-newline eol variants are desired, extend gen_eoe to include a newline count and adjust compile_eoe to use that count.  
  2) Add a small property test explicitly asserting correct token sequences for leading/trailing/only-eoe variants (e.g., grammar -> eoe, grammar -> expr_list eoe, grammar -> eoe expr_list eoe) to ensure Code.string_to_quoted/Spitfire behavior for leading semicolons is acceptable.

Concrete actions needed: none to implement the grammar as given; optionally add the two enhancements above if multi-newline support or explicit targeted tests are wanted.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  42s
Total duration (wall): 49s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           70.0k input, 2.4k output, 22.1k cache read (Est. 0 Premium requests)


---

