# REPRO 67 Notes

## What was failing
- Targeted test: `repro 67` in `test/spitfire_repro_test.exs` (`& bar !== Baz.Foo.Context.(0xC7) do ... end`).
- Expected AST (from `Code.string_to_quoted/1`) puts the `do/end` metadata on the RHS call (`Baz.Foo.Context.(0xC7)`), not on the `!==` operator or the outer capture.

## Current behavior / root cause
- `parse_do_block/2` currently attaches `do/end` metadata to the expression passed in as `lhs` unchanged.  
- For `& bar !== Baz.Foo.Context.(0xC7) do ... end`, `lhs` is the outer capture `:&/1` wrapping the `!==` expression. The `do/end` therefore land on the outer expression, leaving the RHS call without the keyword argument metadata, diverging from `string_to_quoted`.

## Changes attempted
1. Added special handling in `parse_do_block/2` to reroute `do/end` into the RHS when `lhs` looked like an operator call. Narrowed it to `:"!=="` to avoid broad fallout.
2. Temporarily allowed `do` pickup in `parse_call_expression/2` and `parse_dot_call_expression/2`; later reverted due to regressions.
3. Added guards to reduce impact; still left `do/end` on the outer node for capture cases because the operator branch did not match the outer `:&` shape.

## Regressions introduced
- Multiple `SpitfireToxicTest` failures: misplaced `do/end` metadata (e.g., `defp` heads, no-parens `while` forms), leading to AST shape mismatches and comment metadata drift.
- `parse_with_comments/2` mismatches: module/function heads now carry `do/end` on inner nodes instead of the defining form.
- `for`/`case`/`if` style forms in toxic fixtures now lose `do` on the expected callee and end up with malformed keyword placement.
- EEx sample parse failures likely stem from the same metadata misplacement.

## Likely correct direction (without re-introducing regressions)
- Keep `parse_call_expression/2` and `parse_dot_call_expression/2` unchanged (no implicit `do` pickup there).
- In `parse_do_block/2`, detect when `lhs` is a capture or other wrapper around an operator whose RHS is a call-like expression (call/dot call/identifier call) and:
  - Move `do/end` metadata (and the `do` keyword argument) into that RHS call node, not onto the outer operator/capture.
  - Preserve the outer node’s original meta (no added `do/end`), matching `string_to_quoted`.
  - Limit this relocation to cases where the RHS already has an argument list so we only append the `do` keyword and adjust range metadata; otherwise fall back to existing behavior.
- Ensure comment/end-of-expression metadata remains on the defining form (e.g., `defp`, `while`, `for`) by only relocating `do/end` when the RHS is the actual callee receiving the block, not the defining keyword.

## Status
- `repro 67` now passes, but the above regressions remain. A targeted `parse_do_block/2` rewrite to re-home `do/end` onto the RHS call (within operator/capture contexts) is needed to align with the original grammar without disturbing other constructs.
