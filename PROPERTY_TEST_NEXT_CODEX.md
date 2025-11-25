# PROPERTY_TEST_NEXT_CODEX

## Findings
- `Gen.program/1` currently does not terminate: `quoted_atom/0` calls `expr(:expr, 1, 0, 0)`, which eagerly rebuilds the base generator list that calls `quoted_atom/0` again (see `test/spitfire/property_generators.exs`), so any attempt to sample the generator hangs.
- The doc claims 71/71 token coverage, but `Spitfire.Property.TargetTokens.target/0` contains 82 entries and the seed samples alone only cover 70 of them; missing include `:%`, `:assoc_op`, `:begin_interpolation`, `:capture_int`, `:capture_op`, `:end_interpolation`, `:eof`, `:in_op`, `:mult_op`, `:op_identifier`, `:quoted_identifier_end`, `:quoted_op_identifier_end`, `:rel_op`, `:ternary_op`, `:unary_op`.
- Coverage seeds use interpolation that is evaluated at compile time (e.g. `"\"foo#{1}\""` → `"\"foo1\""`), so they never emit `:begin_interpolation/:end_interpolation` tokens or keyword interpolation tokens.
- With `existing_atoms_only: true`, alias/dot/struct forms from the generator produce `:error_token` because the alias atoms are never pre-created.

## Next Tasks
- [ ] Untangle the generator recursion so `Gen.program/1` can be sampled (wrap the recursive branch in `StreamData.lazy/1` or lower the depth for the interpolated atom branch) and add a smoke check to guard against regressions.
- [ ] Fix the seed samples to keep literal `\#{}` interpolation and extend generators/seeds to cover the missing tokens listed above (add explicit cases for `%Foo{}`, captures, `in`, `<`, unary ops, quoted identifiers with `do`/`op` endings, etc.), then rerun the token audit to confirm full coverage.
- [ ] Reconcile `TargetTokens.target/0` and `PROPERTY_TEST_V4.md` with the actual Toxic token set/size (82, not 71) and update the stated progress accordingly.
- [ ] Expand the atom pool seeding (include alias atoms) or relax `existing_atoms_only` where needed so Toxic does not emit `:error_token` for alias/struct/dot forms in the properties.
