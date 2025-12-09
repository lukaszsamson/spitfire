# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-08 13:15:14
- **Nonterminals analyzed**: 3
- **Total grammar rules**: 6

---

## Table of Contents

- [no_parens_one_expr](#no-parens-one-expr)
- [no_parens_zero_expr](#no-parens-zero-expr)
- [parens_call](#parens-call)

---

## no_parens_one_expr

**Grammar Rules (2):**

```erlang
no_parens_one_expr -> dot_op_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
no_parens_one_expr -> dot_identifier call_args_no_parens_one : build_no_parens('$1', '$2').
```

**Analysis:**

Opening the three target files to inspect implementations for no_parens_one_expr across generators and compiler. Calling view on each file and reporting intent.

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

Summary: both grammar productions for no_parens_one_expr are implemented and compiled.

Details: gen_call_no_parens_one includes dot_op_identifier (gen_dot_op_identifier_for_call) and dot_identifier (gen_dot_identifier_for_call) and TokenCompiler.to_tokens/3 handles {:call_no_parens_one, ...} for dot_op_identifier / dot_identifier (and also for identifier/op_identifier targets the generators optionally produce). No cases are marked TODO and I found no missing compile branches for the grammar forms or their allowed argument shapes (single matched_expr or kw args). 

Action items: none required — implementation matches the grammar; optional: document the intentional generator allowance of plain identifier/op_identifier targets (non-dotted) if you want stricter parity with the exact grammar.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 8.397s
Total duration (wall): 1m 13.556s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           96.2k input, 3.2k output, 11.0k cache read (Est. 0 Premium requests)


---

## no_parens_zero_expr

**Grammar Rules (2):**

```erlang
no_parens_zero_expr -> dot_do_identifier : build_identifier('$1').
no_parens_zero_expr -> dot_identifier : build_identifier('$1').
```

**Analysis:**

Running file reads to inspect generator and compiler implementations for no_parens_zero_expr and related TODOs. I'll fetch the three target files.

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

Findings: both grammar productions (dot_do_identifier and dot_identifier) are present in the generators and have compiler handlers; nothing is marked TODO specifically for these productions. Gaps: the zero-arity generator variants used by gen_no_parens_zero_expr bias the dotted-left side to simple identifiers/aliases (they do not emit matched_expr left variants that the grammar allows when depth permits), and gen_dot_do_identifier likewise rarely emits a matched_expr.left variant; the compiler already handles arbitrary matched_expr lefts so only generators need widening. Actions:
- Modify generators so the no-arg gen_dot_identifier and gen_dotted_do_identifier (the zero-arity versions used by gen_no_parens_zero_expr) accept a state (or call the existing arity-1 helpers) and, when budget/depth allows, emit matched_expr dot_op identifier and matched_expr dot_op do_identifier variants (mirror the arity-1 implementations that allow matched_expr on the left).  
- Add property tests exercising no_parens_zero_expr with matched_expr left (e.g., (1 + x).foo and (1 + x).if used as bare no_parens_zero_expr) to ensure round-trip/compilation.  
- Optionally document this generator limitation in the file header as a phase-scoped known restriction until widened.



STDERR:

Total usage est:       0 Premium requests
Total duration (API):  1m 3.617s
Total duration (wall): 1m 8.351s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           96.1k input, 2.8k output, 10.8k cache read (Est. 0 Premium requests)


---

## parens_call

**Grammar Rules (2):**

```erlang
parens_call -> dot_call_identifier call_args_parens : build_parens('$1', '$2', {[], []}).
parens_call -> dot_call_identifier call_args_parens call_args_parens : build_nested_parens('$1', '$2', '$3', {[], []}).
```

**Analysis:**

Searching and opening the three files to inspect parens_call implementations. Running file views now.

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

Searching for compiler helpers related to paren calls (compile_call_target, compile_block_parens_target, compile_call_parens) to verify nested-parens handling. Making parallel grep calls.

✔ grep
   └ No matches found.

✔ Grep "gen_call_parens" in **/*
   └ 13 lines found

✔ Grep "compile_block_parens_target" in **/*
   └ 7 lines found

✔ Grep "compile_call_target" in **/*
   └ 12 lines found

Open compile_call_target and compile_block_parens_target helpers.

✔ Read lib/spitfire/property/token_compiler.ex:1200-1340
   └ 146 lines read

✔ Read lib/spitfire/property/token_compiler.ex:1340-1600
   └ 266 lines read

Adding nested parens generator and compiler support for dot_paren_identifier and nested call_parens. Making edits to generator and compiler files. Also reporting intent.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+1)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 1751     {2, gen_alias()},                                                                   │
   │ 1752     {2, gen_fn_single(state)},                                                          │
   │ 1753     {2, gen_call_parens(state)},                                                        │
   │ 1754  +  {1, gen_call_parens_nested(state)},                                                 │
   │ 1755     {1, gen_capture_int()},                                                             │
   │ 1756     {1, gen_paren_expr(state)},                                                         │
   │ 1757     {1, gen_empty_paren()},                                                             │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit lib/spitfire/property/token_compiler.ex (+18)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 1446       {expr_tokens ++ [dot_token], layout}                                              │
   │ 1447     end                                                                                 │
   │ 1448                                                                                         │
   │ 1449  +  # Target is a dot_paren_identifier (matched_expr.paren_identifier)                  │
   │ 1450  +  defp compile_call_target({:dot_paren_identifier, left, right_name}, layout, opts)   │
   │          do                                                                                  │
   │ 1451  +    # Compile left side (matched_expr)                                                │
   │ 1452  +    {left_tokens, layout} = do_to_tokens(left, layout, opts)                          │
   │ 1453  +                                                                                      │
   │ 1454  +    # Compile dot (stuck to left)                                                     │
   │ 1455  +    {dot_meta, layout} = TokenLayout.stick_right(layout, ".", nil)                    │
   │ 1456  +    dot_token = {:., dot_meta}                                                        │
   │ 1457  +                                                                                      │
   │ 1458  +    # Compile right side as paren_identifier (stuck to dot)                           │
   │ 1459  +    right_str = Atom.to_string(right_name)                                            │
   │ 1460  +    chars = String.to_charlist(right_str)                                             │
   │ 1461  +    {right_meta, layout} = TokenLayout.stick_right(layout, right_str, chars)          │
   │ 1462  +    right_token = {:paren_identifier, right_meta, right_name}                         │
   │ 1463  +                                                                                      │
   │ 1464  +    {left_tokens ++ [dot_token, right_token], layout}                                 │
   │ 1465  +  end                                                                                 │
   │ 1466  +                                                                                      │
   │ 1467     # Target is an identifier (shouldn't happen for call_parens, but handle it)         │
   │ 1468     defp compile_call_target({:identifier, atom}, layout, _opts) do                     │
   │ 1469       name = Atom.to_string(atom)                                                       │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit test/spitfire/property/token_grammar_generators.exs (+24)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 672       end)                                                                               │
   │ 673     end                                                                                  │
   │ 674                                                                                          │
   │ 675  +  # Generate nested parens call: foo()() (no do block)                                 │
   │ 676  +  # Grammar: dot_call_identifier call_args_parens call_args_parens                     │
   │ 677  +  defp gen_call_parens_nested(state) do                                                │
   │ 678  +    child_state = GrammarTree.decr_depth(state)                                        │
   │ 679  +                                                                                       │
   │ 680  +    target_gen =                                                                       │
   │ 681  +      StreamData.frequency([                                                           │
   │ 682  +        {4, gen_paren_identifier()},                                                   │
   │ 683  +        {2, gen_dot_paren_identifier(child_state)},                                    │
   │ 684  +        {1, gen_dot_call_target(child_state)}                                          │
   │ 685  +      ])                                                                               │
   │ 686  +                                                                                       │
   │ 687  +    args1_gen = gen_args(child_state, 2)                                               │
   │ 688  +    args2_gen = gen_args(child_state, 2)                                               │
   │ 689  +                                                                                       │
   │ 690  +    StreamData.bind(target_gen, fn target ->                                           │
   │ 691  +      StreamData.bind(args1_gen, fn args1 ->                                           │
   │ 692  +        StreamData.bind(args2_gen, fn args2 ->                                         │
   │ 693  +          StreamData.constant({:call_parens_nested, target, args1, args2})             │
   │ 694  +        end)                                                                           │
   │ 695  +      end)                                                                             │
   │ 696  +    end)                                                                               │
   │ 697  +  end                                                                                  │
   │ 698  +                                                                                       │
   │ 699     # Generate keyword arguments for no-parens call: a: 1 or a: 1, b: 2                  │
   │ 700     # Per grammar: call_args_no_parens_kw -> call_args_no_parens_kw_expr [',' ...]       │
   │ 701     # call_args_no_parens_kw_expr -> kw_eol matched_expr                                 │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit lib/spitfire/property/token_compiler.ex (+26)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 735       {target_tokens ++ [open_token] ++ args_tokens ++ [close_token], layout}            │
   │ 736     end                                                                                  │
   │ 737                                                                                          │
   │ 738  +  # Nested parens call without do: foo()()                                             │
   │ 739  +  defp do_to_tokens({:call_parens_nested, target, args1, args2}, layout, opts) do      │
   │ 740  +    # Compile target                                                                   │
   │ 741  +    {target_tokens, layout} = compile_call_target(target, layout, opts)                │
   │ 742  +                                                                                       │
   │ 743  +    # First call                                                                       │
   │ 744  +    {lparen1_meta, layout} = TokenLayout.stick_right(layout, "(", nil)                 │
   │ 745  +    lparen1_token = {:"(", lparen1_meta}                                               │
   │ 746  +                                                                                       │
   │ 747  +    {args1_tokens, layout} = compile_args_list(args1, layout, opts)                    │
   │ 748  +                                                                                       │
   │ 749  +    {rparen1_meta, layout} = TokenLayout.stick_right(layout, ")", nil)                 │
   │ 750  +    rparen1_token = {:")", rparen1_meta}                                               │
   │ 751  +                                                                                       │
   │ 752  +    # Second call (stuck to first close paren)                                         │
   │ 753  +    {lparen2_meta, layout} = TokenLayout.stick_right(layout, "(", nil)                 │
   │ 754  +    lparen2_token = {:"(", lparen2_meta}                                               │
   │ 755  +                                                                                       │
   │ 756  +    {args2_tokens, layout} = compile_args_list(args2, layout, opts)                    │
   │ 757  +                                                                                       │
   │ 758  +    {rparen2_meta, layout} = TokenLayout.stick_right(layout, ")", nil)                 │
   │ 759  +    rparen2_token = {:")", rparen2_meta}                                               │
   │ 760  +                                                                                       │
   │ 761  +    {target_tokens ++ [lparen1_token] ++ args1_tokens ++ [rparen1_token,               │
   │         lparen2_token] ++                                                                    │
   │ 762  +       args2_tokens ++ [rparen2_token], layout}                                        │
   │ 763  +  end                                                                                  │
   │ 764     # No-parens call with one argument: foo bar                                          │
   │ 765     defp do_to_tokens({:call_no_parens_one, {:identifier, name}, arg}, layout, opts) do  │
   │ 766       # Compile identifier                                                               │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Grep "call_parens_nested" in **/*
   └ 7 lines found

✔ Grep "parens_call" in **/*
   └ 67 lines found

✔ Grep "dot_paren_identifier" in **/*
   └ 26 lines found

✔ Read test/spitfire/property/token_grammar_generators.exs:640-740
   └ 105 lines read

Updating gen_call_parens to include dot_paren_identifier target (adds missing parens_call variant). Also will run a quick grep to confirm presence.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+1)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 659     target_gen =                                                                         │
   │ 660       StreamData.frequency([                                                             │
   │ 661         {4, gen_paren_identifier()},                                                     │
   │ 662  +      {2, gen_dot_paren_identifier(child_state)},                                      │
   │ 663         {1, gen_dot_call_target(child_state)}                                            │
   │ 664       ])                                                                                 │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ $ mix test test/spitfire/property/token_grammar_generators.exs --color
    └ 24 lines...

Adding compile_call_target_stuck clause for dot_paren_identifier to ensure nested/stuck call targets compile correctly. Also reporting intent.

✔ Edit lib/spitfire/property/token_compiler.ex (+18)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 2169       {expr_tokens ++ [dot_token], layout}                                              │
   │ 2170     end                                                                                 │
   │ 2171                                                                                         │
   │ 2172  +  # dot_paren_identifier stuck: matched_expr.paren_identifier                         │
   │ 2173  +  defp compile_call_target_stuck({:dot_paren_identifier, left, right_name}, layout,   │
   │          opts) do                                                                            │
   │ 2174  +    # Compile left expression stuck                                                   │
   │ 2175  +    {left_tokens, layout} = compile_arg_with_adhesion(left, layout, opts)             │
   │ 2176  +                                                                                      │
   │ 2177  +    # Compile dot (stuck to left)                                                     │
   │ 2178  +    {dot_meta, layout} = TokenLayout.stick_right(layout, ".", nil)                    │
   │ 2179  +    dot_token = {:., dot_meta}                                                        │
   │ 2180  +                                                                                      │
   │ 2181  +    # Compile right side as paren_identifier (stuck to dot)                           │
   │ 2182  +    right_str = Atom.to_string(right_name)                                            │
   │ 2183  +    chars = String.to_charlist(right_str)                                             │
   │ 2184  +    {right_meta, layout} = TokenLayout.stick_right(layout, right_str, chars)          │
   │ 2185  +    right_token = {:paren_identifier, right_meta, right_name}                         │
   │ 2186  +                                                                                      │
   │ 2187  +    {left_tokens ++ [dot_token, right_token], layout}                                 │
   │ 2188  +  end                                                                                 │
   │ 2189  +                                                                                      │
   │ 2190     defp compile_call_target_stuck({:identifier, atom}, layout, _opts) do               │
   │ 2191       name = Atom.to_string(atom)                                                       │
   │ 2192       chars = String.to_charlist(name)                                                  │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ $ mix compile --quiet
    └ 3 lines...

✔ Grep "gen_call_parens_nested" in **/*
   └ 4 lines found

✔ Grep "gen_call_parens_nested" in test/spitfire/property/*
   └ 2 lines found

✔ Grep "gen_call_parens_nested" in **/*
   └ 4 lines found

Findings:
- Before edits, the nested parens production (parens_call -> dot_call_identifier call_args_parens call_args_parens) was missing from the generators/compiler; now both cases are implemented: generators produce {:call_parens, target, args} and {:call_parens_nested, target, args1, args2}, and the compiler handles both nodes and dot_paren_identifier targets (edits made in test/spitfire/property/token_grammar_generators.exs and lib/spitfire/property/token_compiler.ex).
- No parens_call case is left marked TODO; implementation aligns with the grammar (dot_call_identifier covers paren_identifier, dot_paren_identifier, and dot_call targets). Edge cases: very deep/ambiguous nesting and the in_parens_call_arg context are not exhaustively modeled (argument counts/depths are conservative).

Actions to finish/strengthen coverage:
1) Add property tests that specifically generate and round-trip nested parens calls (foo()(), Mod.foo()(), expr.()()) to exercise {:call_parens_nested} and dot_paren_identifier handling.  
2) (Optional) Broaden gen_args max size and/or incorporate GrammarTree.in_parens_call_arg context if needed to model deeper/more ambiguous nested parens cases.



STDERR:

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: F2B7:165EA3:2CBF6D3:37AFD61:6936C10D)

Total usage est:       0 Premium requests
Total duration (API):  5m 30.983s
Total duration (wall): 5m 54.606s
Total code changes:    88 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           1.3m input, 14.5k output, 1.2m cache read (Est. 0 Premium requests)


---

