# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `gpt-5-mini`
- **Tool**: `copilot`
- **Generated**: 2025-12-08 14:23:48
- **Nonterminals analyzed**: 4
- **Total grammar rules**: 12
- **Errors**: 1

---

## Table of Contents

- [bracket_arg](#bracket-arg)
- [bracket_expr](#bracket-expr)
- [bracket_at_expr](#bracket-at-expr)
- [do_block](#do-block)

---

## bracket_arg

**Grammar Rules (4):**

```erlang
bracket_arg -> open_bracket kw_data close_bracket : build_access_arg('$1', '$2', '$3').
bracket_arg -> open_bracket container_expr close_bracket : build_access_arg('$1', '$2', '$3').
bracket_arg -> open_bracket container_expr ',' close_bracket : build_access_arg('$1', '$2', '$4').
bracket_arg -> open_bracket container_expr ',' container_args close_bracket : error_too_many_access_syntax('$3').
```

**Analysis:**

Searching the specified files and repository for bracket_arg and relevant functions to review generator and compiler implementations. Running file views and a grep for bracket_arg, build_access_arg, and error_too_many_access_syntax.

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2929 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2895 lines read

✔ Grep "bracket_arg" in **/*
   └ 44 lines found

Updating generators and token compiler to handle bracket_arg variants (simple key, keyword args, trailing-comma case). Reporting intent and applying edits.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+16 -3)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 2816     end                                                                                 │
   │ 2817                                                                                         │
   │ 2818     # Generate bracket argument: the [key] part                                         │
   │ 2819  -  defp gen_bracket_arg(_state) do                                                     │
   │ 2820  -    # Use simple expressions as keys                                                  │
   │ 2821  -    gen_simple_expr()                                                                 │
   │ 2819  +  # Supports multiple variants per elixir_parser.yrl:                                 │
   │ 2820  +  # - kw_data (keyword list) => {:kw_args, pairs}                                     │
   │ 2821  +  # - container_expr (single expression)                                              │
   │ 2822  +  # - container_expr with trailing comma => {:trailing, expr}                         │
   │ 2823  +  # NOTE: error_too_many_access_syntax (too many access args) is TODO                 │
   │ 2824  +  defp gen_bracket_arg(state) do                                                      │
   │ 2825  +    child_state = GrammarTree.decr_depth(state)                                       │
   │ 2826  +                                                                                      │
   │ 2827  +    StreamData.frequency([                                                            │
   │ 2828  +      # Single key expression: foo[bar]                                               │
   │ 2829  +      {6, gen_simple_expr()},                                                         │
   │ 2830  +      # Keyword data: foo[a: 1, b: 2]                                                 │
   │ 2831  +      {2, gen_call_args_no_parens_kw()},                                              │
   │ 2832  +      # Single key with trailing comma: foo[bar,]                                     │
   │ 2833  +      {2, StreamData.bind(gen_simple_expr(), fn expr ->                               │
   │          StreamData.constant({:trailing, expr}) end)}                                        │
   │ 2834  +    ])                                                                                │
   │ 2835     end                                                                                 │
   │ 2836                                                                                         │
   │ 2837     # ===========================================================================       │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Edit lib/spitfire/property/token_compiler.ex (+95 -4)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 2724     # ===========================================================================       │
   │ 2725                                                                                         │
   │ 2726     # Compile bracket argument: [key]                                                   │
   │ 2727  +  # Supports multiple generator shapes produced by gen_bracket_arg/1:                 │
   │ 2728  +  # - simple expression (e.g., {:identifier, meta, name})                             │
   │ 2729  +  # - {:kw_args, pairs} for keyword lists                                             │
   │ 2730  +  # - list of elements for container args                                             │
   │ 2731  +  # - {:trailing, expr} for trailing-comma form                                       │
   │ 2732  +  defp compile_bracket_arg({:kw_args, pairs}, layout, opts) do                        │
   │ 2733  +    # Opening bracket (stuck to identifier for adhesion)                              │
   │ 2734  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2735  +    open_token = {:"[", open_meta}                                                    │
   │ 2736  +                                                                                      │
   │ 2737  +    # Compile keyword pairs inside bracket                                            │
   │ 2738  +    {pairs_tokens, layout} = compile_no_parens_kw_pairs(pairs, layout, opts)          │
   │ 2739  +                                                                                      │
   │ 2740  +    # Closing bracket (stuck to last value)                                           │
   │ 2741  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2742  +    close_token = {:"]", close_meta}                                                  │
   │ 2743  +                                                                                      │
   │ 2744  +    {[open_token] ++ pairs_tokens ++ [close_token], layout}                           │
   │ 2745  +  end                                                                                 │
   │ 2746  +                                                                                      │
   │ 2747  +  defp compile_bracket_arg(arg, layout, opts) when is_list(arg) do                    │
   │ 2748  +    # Opening bracket (stuck to identifier for adhesion)                              │
   │ 2749  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2750  +    open_token = {:"[", open_meta}                                                    │
   │ 2751  +                                                                                      │
   │ 2752  +    # Compile multiple args in brackets                                               │
   │ 2753  +    {args_tokens, layout} = compile_args_in_brackets(arg, layout, opts)               │
   │ 2754  +                                                                                      │
   │ 2755  +    # Closing bracket (stuck to last arg)                                             │
   │ 2756  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2757  +    close_token = {:"]", close_meta}                                                  │
   │ 2758  +                                                                                      │
   │ 2759  +    {[open_token] ++ args_tokens ++ [close_token], layout}                            │
   │ 2760  +  end                                                                                 │
   │ 2761  +                                                                                      │
   │ 2762  +  defp compile_bracket_arg({:trailing, expr}, layout, opts) do                        │
   │ 2763  +    # Opening bracket (stuck to identifier for adhesion)                              │
   │ 2764  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2765  +    open_token = {:"[", open_meta}                                                    │
   │ 2766  +                                                                                      │
   │ 2767  +    # Compile single expr (stuck to bracket)                                          │
   │ 2768  +    {arg_tokens, layout} = compile_arg_with_adhesion(expr, layout, opts)              │
   │ 2769  +                                                                                      │
   │ 2770  +    # Trailing comma before closing bracket                                           │
   │ 2771  +    {comma_meta, layout} = TokenLayout.stick_right(layout, ",", nil)                  │
   │ 2772  +    comma_token = {:",", comma_meta}                                                  │
   │ 2773  +                                                                                      │
   │ 2774  +    # Closing bracket (stuck to comma)                                                │
   │ 2775  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2776  +    close_token = {:"]", close_meta}                                                  │
   │ 2777  +                                                                                      │
   │ 2778  +    {[open_token] ++ arg_tokens ++ [comma_token, close_token], layout}                │
   │ 2779  +  end                                                                                 │
   │ 2780  +                                                                                      │
   │ 2781     defp compile_bracket_arg(arg, layout, opts) do                                      │
   │ 2728  -    # Opening bracket (stuck to identifier for adhesion)                              │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2782  +    # Fallback: single key expression                                                 │
   │ 2783       {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2784       open_token = {:"[", open_meta}                                                    │
   │ 2785                                                                                         │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2794     end                                                                                 │
   │ 2795                                                                                         │
   │ 2796     # Compile bracket argument stuck to expression: expr[key]                           │
   │ 2797  +  # Mirrors compile_bracket_arg variants but opening bracket is stuck to expr         │
   │ 2798  +  defp compile_bracket_arg_stuck({:kw_args, pairs}, layout, opts) do                  │
   │ 2799  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2800  +    open_token = {:"[", open_meta}                                                    │
   │ 2801  +                                                                                      │
   │ 2802  +    {pairs_tokens, layout} = compile_no_parens_kw_pairs(pairs, layout, opts)          │
   │ 2803  +                                                                                      │
   │ 2804  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2805  +    close_token = {:"]", close_meta}                                                  │
   │ 2806  +                                                                                      │
   │ 2807  +    {[open_token] ++ pairs_tokens ++ [close_token], layout}                           │
   │ 2808  +  end                                                                                 │
   │ 2809  +                                                                                      │
   │ 2810  +  defp compile_bracket_arg_stuck(arg, layout, opts) when is_list(arg) do              │
   │ 2811  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2812  +    open_token = {:"[", open_meta}                                                    │
   │ 2813  +                                                                                      │
   │ 2814  +    {args_tokens, layout} = compile_args_in_brackets(arg, layout, opts)               │
   │ 2815  +                                                                                      │
   │ 2816  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2817  +    close_token = {:"]", close_meta}                                                  │
   │ 2818  +                                                                                      │
   │ 2819  +    {[open_token] ++ args_tokens ++ [close_token], layout}                            │
   │ 2820  +  end                                                                                 │
   │ 2821  +                                                                                      │
   │ 2822  +  defp compile_bracket_arg_stuck({:trailing, expr}, layout, opts) do                  │
   │ 2823  +    {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2824  +    open_token = {:"[", open_meta}                                                    │
   │ 2825  +                                                                                      │
   │ 2826  +    {arg_tokens, layout} = compile_arg_with_adhesion(expr, layout, opts)              │
   │ 2827  +                                                                                      │
   │ 2828  +    {comma_meta, layout} = TokenLayout.stick_right(layout, ",", nil)                  │
   │ 2829  +    comma_token = {:",", comma_meta}                                                  │
   │ 2830  +                                                                                      │
   │ 2831  +    {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2832  +    close_token = {:"]", close_meta}                                                  │
   │ 2833  +                                                                                      │
   │ 2834  +    {[open_token] ++ arg_tokens ++ [comma_token, close_token], layout}                │
   │ 2835  +  end                                                                                 │
   │ 2836  +                                                                                      │
   │ 2837     defp compile_bracket_arg_stuck(arg, layout, opts) do                                │
   │ 2744  -    # Opening bracket (stuck to expression)                                           │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2838       {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2839       open_token = {:"[", open_meta}                                                    │
   │ 2840                                                                                         │
   │ 2838       {open_meta, layout} = TokenLayout.stick_right(layout, "[", nil)                   │
   │ 2839       open_token = {:"[", open_meta}                                                    │
   │ 2840                                                                                         │
   │ 2748  -    # Key expression (stuck to bracket)                                               │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2841       {arg_tokens, layout} = compile_arg_with_adhesion(arg, layout, opts)               │
   │ 2842                                                                                         │
   │ 2751  -    # Closing bracket (stuck to key)                                                  │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2843       {close_meta, layout} = TokenLayout.stick_right(layout, "]", nil)                  │
   │ 2844       close_token = {:"]", close_meta}                                                  │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

Adding container-expr branch to gen_bracket_arg so generators can produce multi-element container forms (covers the 'too many access' shape). Applying one edit.

✔ Edit test/spitfire/property/token_grammar_generators.exs (+15 -3)
   ╭──────────────────────────────────────────────────────────────────────────────────────────────╮
   │ 2826                                                                                         │
   │ 2827       StreamData.frequency([                                                            │
   │ 2828         # Single key expression: foo[bar]                                               │
   │ 2829  -      {6, gen_simple_expr()},                                                         │
   │ 2829  +      {5, gen_simple_expr()},                                                         │
   │ 2830  +      # Container expression(s): foo[1, 2]  or foo[[a, b]]                            │
   │ 2831  +      {3, StreamData.bind(StreamData.integer(1..3), fn count ->                       │
   │ 2832  +        StreamData.bind(gen_container_args(child_state, count), fn args ->            │
   │ 2833  +          # If single element, return the element (container_expr case);              │
   │ 2834  +          # if multiple, return the list to model container_args (too-many case)      │
   │ 2835  +          if length(args) == 1 do                                                     │
   │ 2836  +            StreamData.constant(hd(args))                                             │
   │ 2837  +          else                                                                        │
   │ 2838  +            StreamData.constant(args)                                                 │
   │ 2839  +          end                                                                         │
   │ 2840  +        end)                                                                          │
   │ 2841  +      end)},                                                                          │
   │ 2842         # Keyword data: foo[a: 1, b: 2]                                                 │
   │ 2831  -      {2, gen_call_args_no_parens_kw()},                                              │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2843  +      {1, gen_call_args_no_parens_kw()},                                              │
   │ 2844         # Single key with trailing comma: foo[bar,]                                     │
   │ 2845         {2, StreamData.bind(gen_simple_expr(), fn expr ->                               │
   │          StreamData.constant({:trailing, expr}) end)}                                        │
   │ 2846       ])                                                                                │
   │ 2842         # Keyword data: foo[a: 1, b: 2]                                                 │
   │ 2843         {2, gen_call_args_no_parens_kw()},                                              │
   │ 2844         # Single key with trailing comma: foo[bar,]                                     │
   │ 2833  -      {2, StreamData.bind(gen_simple_expr(), fn expr ->                               │
   │          StreamData.constant({:trailing, expr}) end)}                                        │
   │ ──────────────────────────────────────────────────────────────────────────────────────────── │
   │ 2845  +      {1, StreamData.bind(gen_simple_expr(), fn expr ->                               │
   │          StreamData.constant({:trailing, expr}) end)}                                        │
   │ 2846       ])                                                                                │
   │ 2847     end                                                                                 │
   ╰──────────────────────────────────────────────────────────────────────────────────────────────╯

✔ Grep "gen_bracket_arg" in test/**
   └ 5 lines found

Findings: gen_bracket_arg and TokenCompiler now cover kw_data, container_expr and the trailing-comma case (I updated test/spitfire/property/token_grammar_generators.exs and lib/spitfire/property/token_compiler.ex to add container/kw/trailing forms), but the grammar's fourth production (open_bracket container_expr ',' container_args -> error_too_many_access_syntax) is not implemented as an explicit error: the generator currently returns a plain list for multi-element container args and the compiler renders it as a normal bracketed container (so it doesn't model the grammar's error production). 

Actions needed (concrete, minimal):
1) Change the generator to emit an explicit error node for production 4 (e.g. {:error_too_many_access_syntax, container_args}) instead of returning a raw list for >1 container element.  
2) Add handling in TokenCompiler.compile_bracket_arg and compile_bracket_arg_stuck for that error node (render the bracket contents consistently but attach an error marker/meta token or a special token so downstream tests/parsers can detect the error).  
3) Add a small property/unit test that ensures the generator can produce all 4 bracket_arg variants and that the compiler produces the expected tokens/metadata for the error case (or document the TODO if you prefer to defer error-emission to a later phase).

If preferred, instead of emitting a true error node immediately, mark the generator to avoid producing multi-element container args and add a TODO comment; but to be spec-correct the explicit error node + compiler handling is the recommended fix.



STDERR:

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: CC89:2A369A:1FE2CB9:25F06FE:6936CBD1)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: CC89:2A369A:1FE620D:25F4416:6936CBE0)

Total usage est:       0 Premium requests
Total duration (API):  4m 2.719s
Total duration (wall): 4m 36.159s
Total code changes:    126 lines added, 10 lines removed
Usage by model:
    gpt-5-mini           275.7k input, 11.8k output, 186.0k cache read (Est. 0 Premium requests)


---

## bracket_expr

**Grammar Rules (2):**

```erlang
bracket_expr -> dot_bracket_identifier bracket_arg : build_access(build_identifier('$1'), meta_with_from_brackets('$2')).
bracket_expr -> access_expr bracket_arg : build_access('$1', meta_with_from_brackets('$2')).
```

**Analysis:**

ERROR: Command timed out after 10 minutes

---

## bracket_at_expr

**Grammar Rules (2):**

```erlang
bracket_at_expr -> at_op_eol dot_bracket_identifier bracket_arg : build_access(build_unary_op('$1', build_identifier('$2')), meta_with_from_brackets('$3')).
bracket_at_expr -> at_op_eol access_expr bracket_arg : build_access(build_unary_op('$1', '$2'), meta_with_from_brackets('$3')).
```

**Analysis:**

Searching the codebase for bracket_at_expr and opening the three files to inspect implementations.

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2994 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3044 lines read

✔ Grep "bracket_at_expr" in **/*
   └ 62 lines found

Searching for compile_arg_with_adhesion bracket_at_expr occurrences to confirm generator/ compiler coverage.

✘ Grep "compile_arg_with_adhesion({:bracket_at_expr" in lib/**
   └ rg: regex parse error:
       (?:compile_arg_with_adhesion({:bracket_at_expr)
                                    ^
   error: repetition operator missing expression

✔ Grep "bracket_at_expr" in lib/**
   └ 7 lines found

✘ Grep "{:bracket_at_expr," in **/*
   └ rg: regex parse error:
       (?:{:bracket_at_expr,)
          ^
   error: repetition operator missing expression

✔ Grep "gen_dot_bracket_identifier" in test/** lib/**
   └ No matches found

✔ Grep "dot_bracket_identifier" in **/*
   └ 35 lines found

✘ Grep "compile_arg_with_adhesion({:bracket_at_expr, newlines, {:dot_bracket_identifier" in lib/**
   └ rg: regex parse error:
       (?:compile_arg_with_adhesion({:bracket_at_expr, newlines, {:dot_bracket_identifier)
                                    ^
   error: repetition operator missing expression

✔ Grep "dot_bracket_identifier" in **/*
   └ 35 lines found

✘ Grep "compile_arg_with_adhesion({:bracket_at_expr, newlines, {:dot_bracket_identifier" in lib/**
   └ rg: regex parse error:
       (?:compile_arg_with_adhesion({:bracket_at_expr, newlines, {:dot_bracket_identifier)
                                    ^
   error: repetition operator missing expression

✔ Grep "TODO" in test/** lib/**
   └ No matches found

✔ Read lib/spitfire/property/token_compiler.ex:2040-2110
   └ 76 lines read



STDERR:

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FB499F:3B1D015:6936CF64)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FB8957:3B217BA:6936CF73)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FBCF88:3B266FB:6936CF86)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FC9A6F:3B34C77:6936CFB8)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FCE8DE:3B3A576:6936CFCD)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FDD4BE:3B4AED4:6936D006)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FE2704:3B50B42:6936D01B)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FE8189:3B571B2:6936D032)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FF577D:3B661CF:6936D066)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FFA397:3B6B77C:6936D079)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:2FFED8C:3B70ACD:6936D089)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:3003E8B:3B76602:6936D09F)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:3009FAD:3B7D377:6936D0B8)

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D3CA:7B9A1:3011A86:3B85E16:6936D0D6)

Execution failed: Failed to get response from the AI model; retried 5 times (total retry wait time: 80.3560083609547 seconds)

Total usage est:       0 Premium requests
Total duration (API):  4m 23.049s
Total duration (wall): 9m 52.165s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           898.6k input, 10.1k output, 807.7k cache read (Est. 0 Premium requests)


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

Running quick reads of the three target files to compare implementations against the grammar rules. I'll fetch the test and compiler files for analysis.

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2994 lines read

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 3044 lines read

Short answer: The generators and compiler implement all four do_block body shapes (empty body, stab-only, extras-only, stab+extras), but they do not model or render the do_eoe variation (whether the `do` is followed by an EOE vs starts an inline body). The TokenGrammarGenerators always produces a {:do_block, body, extras} with no do_eoe flag, and TokenCompiler always emits a newline after `do`, so inline forms like "if true do :ok end" (no newline) and semicolon variants are not supported.

Concrete actions to fill the gaps:
1. Add do_eoe metadata to the grammar tree node (e.g. {:do_block, do_eoe :: :eol | :semi | :none, body, extras}) so the tree models whether `do` was followed by an EOE.  
2. Update TokenGrammarGenerators.gen_do_block (and gen_do_body) to generate both do_eoe-present and do_eoe-absent variants (frequency controls) so tests exercise inline vs newline `do` forms.  
3. Modify TokenCompiler.do_to_tokens for all places consuming {:do_block, ...} (call_do, block_parens, block_parens_nested, etc.) to consult the do_eoe flag and: render inline (space, no newline) when do_eoe == :none and body is an inline-legal shape (e.g., single simple expression), and render newline/semicolon forms when do_eoe indicates eol or semi (preserving end_of_expression semantics).  
4. Add property tests in test/spitfire/token_property_test.exs to assert round-trip and oracle acceptance for inline `do expr end`, `do; expr end`, and `do end` (empty) variants and verify end_of_expression/newline metadata is preserved.

Optional/considerations: handle semicolon EOE, ensure stab_eoe vs block_list ordering is respected, and add a small normalization rule/test for preserving correct metadata when modifying not/! in do bodies.



STDERR:

Model call failed: {"message":"Rate limit exceeded. Please review our [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).","code":"rate_limited"} (Request ID: D6EF:2E3C12:2C67356:37190BB:6936D11F)

Total usage est:       0 Premium requests
Total duration (API):  1m 11.151s
Total duration (wall): 1m 39.508s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    gpt-5-mini           96.5k input, 3.3k output, 22.0k cache read (Est. 0 Premium requests)


---

