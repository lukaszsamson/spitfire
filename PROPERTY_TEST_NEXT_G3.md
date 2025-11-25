# Spitfire Property Test Next Steps (G3)

## Status Review (2025-11-25)

The implementation of `PROPERTY_TEST_V4.md` is complete. All planned modules and tests exist and match the specification.

- **Generators**: `test/spitfire/property_generators.exs` (Implemented)
- **Helpers**: `test/spitfire/property.exs` (Implemented)
- **Tests**:
    - `test/spitfire_property_test.exs` (Core Parity)
    - `test/spitfire_property_coverage_test.exs` (Coverage)
    - `test/spitfire_property_acceptance_test.exs` (Acceptance)
    - `test/spitfire_property_error_test.exs` (Error/Integration)

## Identified Gaps & Improvements

1.  **Context-Aware Generation**:
    - The `expr/4` function accepts a `context` argument (`:expr`, `:pattern`, `:guard`) but currently ignores it.
    - **Impact**: Generators may produce invalid syntax for specific contexts (e.g., calling a function in a match pattern), reducing the acceptance rate.

2.  **Generator Coverage**:
    - The coverage test relies on `extra_tokens` (e.g., `foo |> bar`, `Foo.bar(1)`) and seed samples to hit 100% of the target tokens.
    - **Goal**: Tune generators to hit these tokens naturally.

3.  **Edge Case Generators**:
    - The plan mentioned specific edge-case generators (operator spacing, escaped interpolation, nested stabs) which are not explicitly broken out in `property_generators.exs`.

## Next Tasks

### 1. Refine Generators
- [x] **Implement Context Awareness**: Update `expr/4` to dispatch to context-specific helpers.
    - `expr(:pattern, ...)` should only generate valid pattern matches (literals, variables, pinned variables, tuples/lists/maps of patterns).
    - `expr(:guard, ...)` should only generate valid guard expressions (allowed kernel functions, type checks).
- [x] **Add Edge-Case Generators**: Explicitly add generators for:
    - Operator spacing (`foo+bar` vs `foo + bar`).
    - Escaped interpolation (`"foo\#{bar}"`).
    - Nested stabs (`fn -> fn -> end end`).
- [x] **Tune Frequencies**: Adjust `frequency/1` weights to ensure `|>` and `.` calls are generated often enough to pass coverage without seeds.

### 2. Operationalize Tests
- [ ] **CI Integration**: Create a `mix test.property` alias that runs these tests (excluding `:skip` by default, but including them with the alias).
- [ ] **Performance Tuning**: Adjust `max_runs` and `max_size` to keep the suite runtime under 2 minutes for CI.

### 3. Expand Scope
- [ ] **Unsafe Atom Coverage**: Add a test suite variant that runs with `existing_atoms_only: false` to exercise `kw_identifier_unsafe_end` and atom creation.
- [ ] **New Tokens**: As Spitfire supports more features, add them to `Spitfire.Property.TargetTokens`.
