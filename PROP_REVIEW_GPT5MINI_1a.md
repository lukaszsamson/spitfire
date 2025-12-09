# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-07 19:31:19
- **Nonterminals analyzed**: 1
- **Total grammar rules**: 2

---

## Table of Contents

- [no_parens_one_expr](#no-parens-one-expr)

---

## no_parens_one_expr

**Grammar Rules (2):**

```erlang
no_parens_one_expr -> dot_op_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
no_parens_one_expr -> dot_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
```

**Analysis:**

Searching for references and opening the three target files to inspect implementations of no_parens_one_expr and related code. I'll list findings and propose actions.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1795 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2093 lines read

Finding duplicate gen_call_no_parens_one definitions to remove the unreachable one and enable dot_op_identifier generation.

✔ Grep "defp gen_call_no_parens_one\(" in test/spitfire/property/token_grammar_generators.exs
   └ 2 lines found

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 1795 lines read

Summary: The compiler implements both no_parens_one_expr forms (dot_identifier and dot_op_identifier) and TokenGrammarGenerators ultimately emits them (the later gen_call_no_parens_one definition includes both), but the generators contain a duplicated gen_call_no_parens_one with an outdated comment and intentionally‑narrow choices (simple_expr) that omit some matched_expr variants the grammar allows.

Actions to close gaps:
- Remove the earlier/duplicate defp gen_call_no_parens_one block and update its comment so it no longer claims dot_op_identifier isn’t generated (small surgical edit).
- Expand gen_dot_identifier and gen_dot_op_identifier_for_call to allow a general matched_expr as the left side (use gen_matched_expr with depth/budget guards) so they match the grammar alternative matched_expr dot_op identifier/op_identifier.
- Allow call_args_no_parens_one single-arg generation to produce a full matched_expr (with depth guard) in addition to current simple_expr and kw-args so matched_expr arguments are covered.
- Add property cases that specifically exercise: (a) op_identifier (operator-as-identifier) as a no-parens call target, (b) dot_op_identifier where the left is a non-trivial matched_expr, and (c) dot_identifier likewise, to validate round-trip behavior.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 14.722s
Total duration (wall): 1m 20.111s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           213.7k input, 5.1k output, 143.9k cache read (Est. 0 Premium requests)


---

