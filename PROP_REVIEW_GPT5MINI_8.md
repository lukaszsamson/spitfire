# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-09 10:18:18
- **Nonterminals analyzed**: 5
- **Total grammar rules**: 10

---

## Table of Contents

- [fn_eoe](#fn-eoe)
- [do_eoe](#do-eoe)
- [block_eoe](#block-eoe)
- [block_item](#block-item)
- [block_list](#block-list)

---

## fn_eoe

**Grammar Rules (2):**

```erlang
fn_eoe -> 'fn' : '$1'.
fn_eoe -> 'fn' eoe : next_is_eol('$1', '$2').
```

**Analysis:**

Searching for fn_eoe and opening the three target files to review their implementations.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 3436 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3648 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 421 lines read

✔ Grep "fn_eoe" in **/*
   └ 64 lines found

Summary: gen & compile cover both productions and match the grammar; no TODOs remain for fn_eoe.

Findings (concise):
- Generators: gen_fn_eoe/0 returns :none, :eol, :semi, :eol_semi — covers "fn" and "fn eoe" (eoe ∈ {eol, ';', eol ';'}).
- Compiler: compile_fn_eoe/3 implements :none/:eol/:semi/:eol_semi and do_to_tokens uses it for both fn_single and fn_multi.
- No TODO markers related to fn_eoe were found and behavior is consistent with other eoe-sensitive productions (the compiler emits explicit eol/; tokens rather than mutating the fn token's meta; that choice matches compile_stab_op_eol/do_eoe approaches).

Concrete actions (none required to meet the grammar); optional recommendations:
- Add a focused property/unit test that generates fn_eoe = :eol/:semi/:eol_semi to assert the produced token sequence (["fn", eol/";", ... , "end"]) and to assert any AST metadata expectations if the parser relies on copying eol into token meta.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  49s
Total duration (wall): 55s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           98.0k input, 2.2k output, 11.0k cache read (Est. 0 Premium requests)


---

## do_eoe

**Grammar Rules (2):**

```erlang
do_eoe -> 'do' : '$1'.
do_eoe -> 'do' eoe : '$1'.
```

**Analysis:**

Running searches and opening the three target files to find implementations and TODOs related to do_eoe. I'll fetch matching occurrences and file contents.

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3648 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 421 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 3436 lines read

✔ Grep "do_eoe" in **/*
   └ 364 lines found

Findings: The generators and compiler implement do_eoe and the 4 do_block shapes: gen_do_eoe returns :none/:eol/:semi/:eol_semi and gen_do_block produces {:do_block, do_eoe, body, extras}; TokenCompiler accepts {:do_block, do_eoe, ...} in all block contexts and compile_do_eoe handles :none/:eol/:semi/:eol_semi. No do_eoe cases are left marked TODO and the implementation matches the grammar productions.

Actions recommended:
1) Add targeted property/tests to exercise do_eoe variants (inline :none, :semi and :eol_semi) for call_do/block_parens/case to ensure round-trip/spacing; 
2) (optional) model variable newline counts (n>1) by extending gen_do_eoe and compile_do_eoe if multi-newline metadata must be tested; 
3) (optional) add a small backward-compatibility clause converting 3-element {:do_block, body, extras} for any non-list body shapes if such legacy shapes appear in tests.

Conclusion: Implementation is correct per the grammar; only testing coverage and optional refinements for newline-count/more precise metadata are advisable.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 16.663s
Total duration (wall): 1m 23.891s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           104.4k input, 3.5k output, 21.9k cache read (Est. 0 Premium requests)


---

## block_eoe

**Grammar Rules (2):**

```erlang
block_eoe -> block_identifier : '$1'.
block_eoe -> block_identifier eoe : '$1'.
```

**Analysis:**

Searching and opening the three target files to inspect generators and compiler for block_eoe handling. I'll fetch the files for review.

✔ Read test/spitfire/token_property_test.exs
   └ 421 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 3436 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3648 lines read

Searching for generator implementations of block items and block_eoe usages to verify shapes produced.

✘ grep
   The "path" argument must be of type string. Received null

✔ Grep "gen_else_block" in **/*
   └ 2 files found

✔ Grep "gen_else_block" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

✔ Grep "gen_block_eoe" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

✔ Grep "block_eoe" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

✔ Grep "gen_else_block" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

✔ Grep "defp gen_else_block" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

✔ Grep "block_item" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 1 file found

The file is long; view relevant portion around gen_block_extras and gen_block_eoe already shown earlier lines ~1334 onward. Need to inspect gen_else_block/gen_rescue_block/gen_block_extras usage. I'll search for "else" generation functions.

✔ Grep "gen_else_block" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 2 lines found

✔ Read test/spitfire/property/token_grammar_generators.exs:1336-1410
   └ 80 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1408-1490
   └ 87 lines read

✔ Grep "TODO" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ 3 lines found

✔ Grep "do_block" in **/* (/Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex)
   └ 21 lines found

✔ Grep "block_eoe" in **/* (/Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex)
   └ 17 lines found

✔ Grep "defp gen_eoe" in **/*
 (/Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs)
   └ No matches found

✘ Grep "{:do_block, do_eoe, body, extras}" in **/*
 (/Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex)
   └ rg: regex parse error:
       (?:{:do_block, do_eoe, body, extras})
          ^
   error: repetition operator missing expression

✘ Grep "{:do_block" in **/* (/Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex)
   └ rg: regex parse error:
       (?:{:do_block)
          ^
   error: repetition operator missing expression

✘ Grep "compile_block_items(" in **/*
 (/Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex)
   └ rg: regex parse error:
       (?:compile_block_items()
       ^
   error: unclosed group

✔ Grep "block_eoe" in **/* (/Users/lukaszsamson/spitfire/test/spitfire/token_property_test.exs)
   └ No matches found

Summary: block_eoe is implemented end-to-end and matches the grammar; no TODOs.

Findings (concise)
- Generators: gen_block_eoe produces all variants (:eol, :none, :semi, :eol_semi) and generators (gen_else_block, gen_rescue_block, gen_catch_block, gen_after_block, gen_block_item_stab/body) emit {:block_item, type, block_eoe, body} shapes as expected.
- Compiler: compile_block_items and compile_block_eoe handle :none, :eol, :semi, :eol_semi and compile bodies (lists or {:stab_eoe,...}) correctly; backward-compatible 3‑element formats are also handled.
- TODOs: no TODOs related to block_eoe (TODOs in the repo are about later-phase features like strings/sigils).
- Correctness: semantics and token emission match the grammar productions block_eoe -> block_identifier and block_identifier eoe; eoe variants are mapped to tokens (newline, semicolon, newline+semicolon) properly.
- Minor coverage note: generator mixes common combos (none, single extras, rescue+after) but does not exhaustively enumerate all possible multi-item block_list permutations (rare in practice).

Concrete actions (optional, low-effort, recommended)
1. Add property cases that specifically assert round-trip for do-block extras with each block_eoe variant (:none, :eol, :semi, :eol_semi) to ensure inline vs newline/semicolon variants are covered by tests.  
2. If desired, expand gen_block_extras to generate additional multi-item block_list permutations (e.g., else + rescue, rescue + catch + after) to increase coverage of complex try/do blocks.

If you want, implement action 1 now (add focused property tests) or action 2 (extend generator) — say which and will make minimal changes.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  4m 17.424s
Total duration (wall): 4m 25.665s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           1.7m input, 9.3k output, 1.7m cache read (Est. 0 Premium requests)


---

## block_item

**Grammar Rules (2):**

```erlang
block_item -> block_eoe stab_eoe : {handle_literal(?exprs('$1'), '$1'), build_stab('$2')}.
block_item -> block_eoe : {handle_literal(?exprs('$1'), '$1'), {'__block__', [], []}}.
```

**Analysis:**

Running a fast search for "block_item" and opening the three files to inspect generator and compiler implementations for block_item cases. Also reporting intent 'Exploring codebase'.

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3648 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 421 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 3436 lines read

✔ Grep "block_item" in **/*
   └ 87 lines found

Searching for gen_block_item_stab and gen_block_item_body definitions and usages.

✔ Grep "gen_block_item_stab" in test/spitfire/property/token_grammar_generators.exs
   └ 3 lines found

✔ Read test/spitfire/property/token_grammar_generators.exs:1334-1378
   └ 50 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1374-1418
   └ 50 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1418-1468
   └ 55 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1468-1524
   └ 62 lines read

Findings: The generators and compiler cover the two block_item productions: generators emit either an empty body [{:block_item, type, block_eoe, []}] or a stab body [{:block_item, type, block_eoe, {:stab_eoe, clauses, trailing_eoe}}], and TokenCompiler.compile_block_items handles the new 4-tuple form and the legacy 3-tuple forms and calls compile_do_body which supports both lists and {:stab_eoe,...}; block_eoe variants (:none/:eol/:semi/:eol_semi) are also implemented. No block_item cases are marked TODO.

Suggested (optional) actions to reach full parity/coverage:
1) If literal parity with the parser is desired, add a low-frequency generator variant that emits the parser-style empty-body node {:__block__, [], []} (currently generators use [] and the compiler already accepts []).  
2) If aiming for maximal grammar fidelity, add a generator path for else-with-stab (else + stab_eoe) only if needed (current generator intentionally treats else as expression-only).  
3) Run the property tests (mix test / the property) to validate end-to-end behavior.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 48.157s
Total duration (wall): 1m 56.413s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           544.7k input, 4.0k output, 464.6k cache read (Est. 0 Premium requests)


---

## block_list

**Grammar Rules (2):**

```erlang
block_list -> block_item : ['$1'].
block_list -> block_item block_list : ['$1' | '$2'].
```

**Analysis:**

Reading the three files to inspect block_list handling in generators and compiler. Running file views in parallel.

✔ Read test/spitfire/token_property_test.exs
   └ 421 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3648 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 3436 lines read

Searching for generator and block_item helpers to compare produced shapes against compiler expectations.

✘ Grep "{:block_item" in test/spitfire/property/token_grammar_generators.exs
   └ rg: regex parse error:
       (?:{:block_item)
          ^
   error: repetition operator missing expression

✔ Grep "gen_else_block" in test/spitfire/property/token_grammar_generators.exs
   └ 2 lines found

✔ Grep "gen_block_extras" in test/spitfire/property/token_grammar_generators.exs
   └ 2 lines found

✔ Grep "block_item" in test/spitfire/property/token_grammar_generators.exs
   └ 24 lines found

✔ Grep "gen_rescue_block" in test/spitfire/property/token_grammar_generators.exs
   └ 3 lines found

✔ Grep "gen_block_items" in lib/spitfire/property/token_compiler.ex
   └ No matches found

Opening generator around block extras to inspect exact shapes.

✔ Read test/spitfire/property/token_grammar_generators.exs:1330-1380
   └ 56 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1370-1424
   └ 60 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs:1420-1488
   └ 74 lines read

✔ Grep "do_block" in lib/spitfire/property/token_compiler.ex
   └ 21 lines found

✔ Read lib/spitfire/property/token_compiler.ex:1200-1280
   └ 85 lines read

✔ Grep "do_block, do_eoe" in lib/spitfire/property/token_compiler.ex
   └ 7 lines found

✔ Grep "do_block, do_eoe, body, extras" in lib/spitfire/property/token_compiler.ex
   └ 7 lines found

✔ Read lib/spitfire/property/token_compiler.ex:1280-1400
   └ 125 lines read

✔ Read lib/spitfire/property/token_compiler.ex:1400-1520
   └ 126 lines read

✔ Read lib/spitfire/property/token_compiler.ex:1520-1640
   └ 126 lines read

✔ Grep "TODO" in test/spitfire/property/token_grammar_generators.exs
   └ 3 lines found

Summary: both generator and compiler implement block_list/block_item variants and interoperate correctly.

Findings:
- Generators produce block_list as lists of {:block_item, block_type, block_eoe, body} where body is [] or a list of exprs or {:stab_eoe, clauses, trailing_eoe}; gen_block_extras/gen_block_item_body/gen_block_item_stab cover single and multi-item lists (including rescue+after combos).
- Compiler accepts the new 4-tuple {:block_item, type, block_eoe, body} and also provides backward-compat translation for older 3-element do_block/block_item shapes; compile_block_items/1, compile_block_eoe/3 and compile_do_body/3 correctly handle the produced shapes.
- No block-list cases are marked TODO; other TODOs in the repo refer to unrelated future phases (access_expr forms), not block_list handling.

Edge cases / suggestions (none required to make correct):
- No changes required — generators emit the exact shapes the compiler expects and the compiler handles legacy 3-element forms; coverage includes empty bodies, expression bodies, and stab clause bodies with trailing eoe metadata.
- If desired in future: add an explicit test that generates multi-item block_lists (rescue+after+else ordering permutations) to assert round-trip rendering, but this is optional.

Conclusion: block_list handling is implemented and correct; no code changes required.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  2m 33.15s
Total duration (wall): 2m 42.543s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           1.2m input, 4.6k output, 1.1m cache read (Est. 0 Premium requests)


---

