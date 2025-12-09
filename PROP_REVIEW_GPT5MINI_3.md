# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-07 20:20:48
- **Nonterminals analyzed**: 2
- **Total grammar rules**: 33

---

## Table of Contents

- [access_expr](#access-expr)
- [do_block](#do-block)

---

## access_expr

**Grammar Rules (29):**

```erlang
access_expr -> bracket_at_expr : '$1'.
access_expr -> bracket_expr : '$1'.
access_expr -> capture_int int : build_unary_op('$1', number_value('$2')).
access_expr -> fn_eoe stab_eoe 'end' : build_fn('$1', '$2', '$3').
access_expr -> open_paren stab_eoe ')' : build_paren_stab('$1', '$2', '$3').
access_expr -> open_paren ';' stab_eoe ')' : build_paren_stab('$1', '$3', '$4').
access_expr -> open_paren ';' close_paren : build_paren_stab('$1', [], '$3').
access_expr -> empty_paren : warn_empty_paren('$1'), {'__block__', parens_meta('$1'), []}.
access_expr -> int : handle_number(number_value('$1'), '$1', ?exprs('$1')).
access_expr -> flt : handle_number(number_value('$1'), '$1', ?exprs('$1')).
access_expr -> char : handle_number(?exprs('$1'), '$1', number_value('$1')).
access_expr -> list : element(1, '$1').
access_expr -> map : '$1'.
access_expr -> tuple : '$1'.
access_expr -> 'true' : handle_literal(?id('$1'), '$1').
access_expr -> 'false' : handle_literal(?id('$1'), '$1').
access_expr -> 'nil' : handle_literal(?id('$1'), '$1').
access_expr -> bin_string : build_bin_string('$1', delimiter(<<$">>)).
access_expr -> list_string : build_list_string('$1', delimiter(<<$'>>)).
access_expr -> bin_heredoc : build_bin_heredoc('$1').
access_expr -> list_heredoc : build_list_heredoc('$1').
access_expr -> bitstring : '$1'.
access_expr -> sigil : build_sigil('$1').
access_expr -> atom : handle_literal(?exprs('$1'), '$1', atom_colon_meta('$1')).
access_expr -> atom_quoted : handle_literal(?exprs('$1'), '$1', atom_delimiter_meta('$1')).
access_expr -> atom_safe : build_quoted_atom('$1', true, atom_delimiter_meta('$1')).
access_expr -> atom_unsafe : build_quoted_atom('$1', false, atom_delimiter_meta('$1')).
access_expr -> dot_alias : '$1'.
access_expr -> parens_call : '$1'.
```

**Analysis:**

Opening the three target files to compare generators and compiler implementations against the grammar rules. Making a parallel call to load all three files for inspection.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2080 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2154 lines read

Summary: most access_expr forms are present (ints/floats/chars, atom literals, true/false/nil, lists, tuples, bracket_expr/bracket_at_expr, capture_int, fn_single/fn_multi, paren_expr, empty_paren, paren calls, dot_alias), but several grammar variants are intentionally deferred or only partially wired (maps are disabled in gen_access_expr, binary/list heredocs, bitstrings, sigils, quoted atoms, and the paren-stab variants are not generated/compiled). 

Concrete actions to fill gaps:
1) Re-enable/implement the remaining access_expr generators in test/spitfire/property/token_grammar_generators.exs (maps, bin_string/list_string, bin_heredoc/list_heredoc, bitstring, sigil, atom_quoted/atom_safe/atom_unsafe) or leave them explicitly marked TODO for a later phase; add matching generator helpers where missing.  
2) Add generators for the paren-stab forms (open_paren stab_eoe ')' and the semicolon variants) and extend lib/spitfire/property/token_compiler.ex to accept and render the corresponding paren_stab nodes (emit '(' + stab clause tokens + optional semicolon handling + ')') following build_paren_stab grammar behavior.  
3) Add TokenCompiler handlers for any new node types (quoted atoms, sigils, heredocs, bitstring) and add focused unit/property tests exercising bracket_at/bracket_expr adhesion, capture_int formatting, and paren-stab cases to validate round-trip behavior (or mark tests skipped if Toxic/TokenLayout lacks support).  

If desired, I can implement these changes incrementally (start by enabling maps and bin_string in the generator and adding any missing compiler branches).



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  51s
Total duration (wall): 57s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           77.9k input, 3.7k output, 11.4k cache read (Est. 0 Premium requests)


---

## do_block

**Grammar Rules (4):**

```erlang
do_block -> do_eoe 'end' : {do_end_meta('$1', '$2'), [[{handle_literal(do, '$1'), {'__block__', [], []}}]]}.
do_block -> do_eoe stab_eoe 'end' : {do_end_meta('$1', '$3'), [[{handle_literal(do, '$1'), build_stab('$2')}]]}.
do_block -> do_eoe block_list 'end' : {do_end_meta('$1', '$3'), [[{handle_literal(do, '$1'), {'__block__', [], []}} | '$2']]}.
do_block -> do_eoe stab_eoe block_list 'end' : {do_end_meta('$1', '$4'), [[{handle_literal(do, '$1'), build_stab('$2')} | '$3']]}.
```

**Analysis:**

Searching the repository for do_block/do_eoe and opening the three target files to inspect the implementations.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2080 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2154 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 157 lines read

✔ Grep "do_eoe" in **/*
   └ 65 lines found

✔ Grep "do_block" in **/*
   └ 1058 lines found

✔ Grep "__block__" in **/*
   └ 234 lines found

Summary: Not all do_block cases are implemented — the generators and TokenCompiler only cover the bare-identifier do form ({:call_do, {:identifier, ...}, args, {:do_block, body, extras}}) and case-stab bodies; several grammar/text TODOs show paren-call and no-parens+do variants and some block extras (rescue/catch/after) are intentionally deferred.

Actions needed:
1) Generator: add variants that emit do-bearing call heads (paren-call: {:call_parens, target, args} + do_block and nested parens variant; no-parens: {:call_no_parens_one}/{call_no_parens_many} or dotted/op targets + do_block), and allow empty do bodies and generate block_extras for :rescue/:catch/:after.  
2) Compiler: generalize do_to_tokens/3 (and compile_call_target/compile_do_args) to accept and compile call_do nodes whose target may be call_parens/dot_call/dot_identifier/dot_op_identifier/no-parens targets while preserving adhesion/newline/meta behavior.  
3) Tests: implement the TODO tests for all five block_expr forms (paren, nested-paren, dot_do_identifier, dot_op_identifier no-parens, dot_identifier no-parens), add property coverage for empty bodies and rescue/catch/after, and assert the round-trip behavior.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 39.85s
Total duration (wall): 1m 44.077s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           197.2k input, 6.7k output, 110.8k cache read (Est. 0 Premium requests)


---

