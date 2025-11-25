# PROPERTY_TEST_NEXT_CODEX

## Status
- `Gen.program/1` is now sampleable: the recursive `quoted_atom/0` branch is delayed via a constant bind so it no longer rebuilds `expr/4` eagerly.
- Coverage seeds now keep literal `\#{}` interpolation and include the previously missing token shapes (assoc `=>`, captures, `in`, `<`, `//`, `~~~`, struct `%Foo{}`, quoted identifiers/op identifiers, etc.). A manual audit over seeds + generated samples now covers 82/82 target tokens.
- Alias atoms are pre-created in `touch_atom_pools/0` to avoid `:error_token` emission when `existing_atoms_only: true`.
- `PROPERTY_TEST_V4.md` progress updated to reflect the 82-token target set.

## Next Tasks
- [ ] Add a lightweight smoke script/ExUnit test that asserts the token audit returns 0 missing tokens (using the seed list + a handful of generated programs) so regressions are caught without running the full property suite.
- [ ] Decide whether to keep `@seed_samples` hard-coded in the coverage test or extract them into a shared helper to make the audit reusable in ad-hoc scripts.
