## Context
- Task: fix operator precedence issues between unary/do blocks without breaking tests.
- Current date: 2025-12-08T14:28:15.002Z.

## What I changed
- Added postwalk block splitting for unary operators (including `@` and `&`) when their operand parsed as a multi-expression `__block__`.
- Introduced `@block_split_unaries` alongside `@block_sensitive_unaries`.
- Added back semicolon consumption in `peek_token_eat_eol/1`.

## Current failures
- 20 tests fail after changes. Most failures are token grammar roundtrips for `if/try/case` do-blocks now emitted as `{:call_do, ...}` that the token compiler doesn’t support, leading to "Unimplemented grammar tree node" errors.
- Grammar tests `fn_eoe` / `open_paren` still fail because unary block splitting is now applied too late/early.
- Pin operator (`^`) not included in block-splitting set (noted by user).

## Root issues
- Moving unary/block splitting to post-normalization changed AST shape for do-block constructs, breaking token compiler expectations.
- Expanding the split-unary set without aligning with `unary_op_eol` from `elixir_parser.yrl` caused mismatches.
- Semicolon handling was toggled multiple times; final behavior may still differ from baseline.

## Next steps (for fresh attempt)
- Revert to baseline before block-splitting changes; reintroduce only necessary fix with alignment to `unary_op_eol` operators (`+ - ! ^ not ~~~` and possibly dual/ternary?), include pin if required.
- Ensure unary/do splitting happens in parser (not postwalk) only when tokenizer would produce a single expression operand per Elixir grammar.
- Verify semicolon/EOL handling matches `eoe` rules and doesn’t over-consume.
- Re-run full `mix test` to confirm no regressions before finalizing.
