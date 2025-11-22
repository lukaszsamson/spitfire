# Spitfire Pratt Parser Architecture

## 1. Overview
Spitfire implements a *Pratt parser* – a **top-down operator-precedence** algorithm (aka *TDOP*).  
Unlike classic recursive-descent or LR(k) parsers, a Pratt parser encodes the grammar’s expression rules in a *binding-power table* and two mutually-recursive functions:

* **Null denotation (nud)** – parses a *prefix* / *atomic* expression when no left-hand context exists.
* **Left denotation (led)** – parses an *infix* / *postfix* expression when a left-hand side (LHS) has already been parsed.

`Spitfire.parse/2` drives tokenization, initializes parser state, and enters `parse_program/1`.  Expression parsing is delegated to `parse_expression/6` which embodies both `nud` and `led` roles.

```
parse_expression(parser, (assoc, bp), is_list, is_map, is_top, is_stab)
```
* `assoc, bp` – current minimum binding power (precedence).
* Boolean flags tweak parsing behaviour for lists, maps, top-level contexts, and `->` *stab* expressions.

## 2. Token stream & look-ahead
The tokenizer in `src/spitfire_tokenizer.erl` emits Elixir-flavoured tokens plus markers such as `:kw_identifier`, `:unary_op`, etc.  A parser struct maintains **two-token look-ahead** (`current_token`, `peek_token`) enabling Pratt’s precedence dispatch without backtracking.

### Fuel meter
`consume_fuel/1` decrements a counter (default *150*) each recursive entry to guard against *left-recursion* loops.  Depletion raises `NoFuelRemaining`, returned to callers as `{:error, :no_fuel_remaining}`.

## 3. Precedence lattice
`@precedences` maps token classes to `{:assoc, power}` tuples.  Powers increment by *2* so that `(right_bp = left_bp-1)` properly separates *left* vs *right* associativity during `calc_prec/3`.

Highest-to-lowest extract (subset):

| Power | Assoc | Example |
|-------|-------|---------|
| 64    | left  | `@` (module attribute) |
| 60    | left  | `.` call  |
| 52    | left  | `**` power |
| 22    | right | `|>` pipe |
|  4    | left  | `do` keyword |

During `led` evaluation, `calc_prec/3` decides whether the upcoming operator should bind tighter than the expression already parsed; if not, recursion unwinds.

## 4. Null denotation (prefix / atom handling)
A massive `case` in `parse_expression/6` selects the appropriate `prefix` handler – e.g. `parse_int/1`, `parse_list_literal/1`, `parse_grouped_expression/1` – based on `current_token_type/1`.

Typical flow:
1. Consume fuel.
2. Dispatch `nud`.
3. Enter Pratt loop: while next token is *not* a terminator and its precedence outranks the current minimum, call its `led`.

## 5. Left denotation (infix / postfix)
The `led` dispatcher is driven by `peek_token_type/1`.  Representative handlers:
* `parse_infix_expression/2` – generic binary ops (`+`, `&&`, `when`, …).
* `parse_pipe_op/2`, `parse_range_expression/2` – special-cased semantics.
* `parse_call_expression/2`, `parse_dot_expression/2`, `parse_access_expression/2` – postfix call chains.
* `parse_stab_expression/2` – Elixir-specific anonymous-function arrows.

Each `led` builds an AST node of shape `{op, meta, [lhs, rhs]}` and recurses with the operator’s binding power.

## 6. Structured literals & special forms
Beyond expression parsing, specialised routines cover:
* List (`[ … ]`), tuple (`{ … }`), map / struct (`%{ … }`, `%Mod{ … }`) literals with newline-sensitive layout metadata.
* Heredoc & sigil interpolation via `parse_interpolation/2`.
* `do … end` blocks built by `parse_do_block/2`, producing Elixir’s `{:do, …}` keyword pairs inside call nodes.

## 7. Error handling & recovery
Errors are recorded (not thrown) via `put_error/2` and accumulate in `parser.errors` allowing parsing to continue and deliver partial AST + diagnostics.

Recovery strategies:
* **Terminator sets** – Pratt loop halts on `@terminals` so unmatched braces don’t cascade.
* **Synthetic tokens** – on missing closers for lists/tuples/bitstrings the parser injects `:fake_closing_bracket`, logs an error, and proceeds.

## 8. Comment & metadata preservation
Hooks like `preserve_comments/5` capture comment blocks for a formatter.  Most AST nodes embed `meta` lists containing:
* `:line`, `:column` – original coordinates.
* `:closing`, `:newlines`, `:delimiter`, etc. – fidelity for round-tripping pretty-printers.

## 9. Complexity analysis
*Time*: Each token is consumed a constant number of times; primary loop is O(n).  
*Space*: AST plus token stream O(n).  
Fuel provides an *O(n)* guard against pathological cases but may fail for deeply nested valid code >150 `led` calls without advancement.

## 10. Extensibility considerations
Adding a new operator:
1. Append token kind in tokenizer.
2. Insert `@precedences` entry with proper binding power.
3. Extend `prefix` or `infix` selection clauses in `parse_expression/6`.

Because behaviour is encoded in Elixir functions rather than tables, *grammar evolution requires touching code*, not just data – flexible yet error-prone.

## 11. Limitations & Trade-offs
1. **Manual precedence table** – mis-ordering leads to subtle mis-parses.
2. **Fixed fuel** – legitimate highly-nested expressions may exceed 150 recursive steps.
3. **Two-token look-ahead** – cannot parse constructs needing >1 look-ahead symbol without ad-hoc checks.
4. **Error locality** – recovery uses heuristics; multiple independent errors may collapse into one diagnostic after injection of synthetic closers.
5. **Performance vs. clarity** – giant single-file (`~2.8 K LOC`) parser trades modularity for speed; difficult to unit-test individual *led/nud* functions.

## 12. References
* V. Pratt, “Top Down Operator Precedence,” 1973.  
* Douglas Crockford, “Top Down Operator Precedence,” 2010 (JS re-spin).  
* Elixir `Code.string_to_quoted/2` – inspiration for many edge-cases.

---
*Generated automatically from source `lib/spitfire.ex`.*

## 13. Range Metadata (Toxic Mode)

When using the Toxic tokenizer, Spitfire attaches a `:range` key to AST node
metadata:

- **Format**: `{:range, {{start_line, start_col}, {end_line, end_col}}}`
- **Coordinates**: 1-based (`line`, `column`), representing a half-open
  interval `[start, end)`.
- **Invariants** (guaranteed for all inputs):
  - Parent ranges contain the ranges of all children.
  - Sibling ranges do not overlap (they may touch).
  - The root node’s range spans the entire document (from parser start to
    logical EOF).

Range data is derived from Toxic’s ranged token metadata. Even in
error-tolerant mode, Toxic emits structural tokens for missing delimiters
(`)`, `]`, `}`, `end`, etc.), sometimes with zero-width ranges; Spitfire uses
these tokens to keep ranges consistent.

Example:

```elixir
{:ok, {:+, meta, [lhs, rhs]}} =
  Spitfire.parse("1 + 2", tokenizer: :toxic)

meta[:range]
# => {{1, 1}, {1, 6}}
```

Legacy (non-Toxic) mode does not attach `:range`, preserving the original AST
shape and metadata. 

### `:strip_ranges` configuration

Range metadata is enabled by default when the Toxic tokenizer is selected, but
Spitfire also exposes a `:strip_ranges` flag for compatibility with legacy
parsers.  Set `config :spitfire, strip_ranges: true` to prevent range metadata
from being attached at all (this is what `test_helper.exs` does so the old
parity tests do not observe `:range`).  `put_meta_range/2` honours that config
by behaving as a no-op, so ASTs built with the config enabled look the same as
non-Toxic output.

For callers that leave the config at `false` but still need a `:range`-free
AST, `Spitfire.parse/2` accepts `strip_ranges: true`; this triggers
`strip_ranges_if_needed/2` after parsing and removes any metadata that slipped
in.  Passing `strip_ranges: false` has no effect when the config is already
stripping ranges globally, but it allows tests to temporarily opt back in when
the config is reset to `false` (see `SpitfireRangesTest`).
