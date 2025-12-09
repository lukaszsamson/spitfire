# Token-Driven Property Tests – Grammar Alignment Snapshot (R1)

This note reassesses the Phase 1–2 implementation against the original Elixir grammar (`elixir/lib/elixir/src/elixir_parser.yrl`) and pinpoints what is currently generated vs. missing. It is meant to realign the generators/compilers with the grammar categories before proceeding to further phases.

## 1) What Phase 1–2 Can Generate Today

Paths refer to `lib/spitfire/property/token_compiler.ex` unless noted.

- **grammar / expr_list**: compiled via `do_to_tokens/3` and `compile_forms/3` (`:grammar` node), emitting forms separated by `:eol` (newline only; no `;` yet).
- **eoe**: implicit newline between forms (`compile_forms/3`); semicolon and mixed `eol ;` variants not emitted.
- **Literals**: int/flt/char/atom/true/false/nil (`do_to_tokens/3` clauses ~40–80).
- **Identifiers/Alias**: `identifier`, `alias` (and `paren_identifier` when used as call targets).
- **Capture**: `capture_int` → `&N` with adhesion.
- **Unary/Binary Ops**: `unary_op`, `binary_op` (matched-op subset) with optional trailing newlines (`do_to_tokens/3` ~106–146).
- **Calls**: `call_parens` (`foo(...)`, `foo.(...)`), `call_no_parens_one` (simple `foo bar`), dot-call target support.
- **fn**: `fn_single` and `fn_multi` (single/multi clause) including guarded stabs; patterns `:empty | {:single, expr} | {:many, [expr]}`.
- **do-blocks**: `call_do` (`if/identifier do ... end` with optional block items) compiled at ~259–290.

## 2) Coverage vs. `elixir_parser.yrl`

Status legend: **Full** (all productions covered), **Partial** (some forms), **Missing** (not generated).

- **grammar (101–106)**: **Partial** – only `expr_list` with newline separators; no leading/trailing `eoe` variants, no semicolons.
- **expr (112–114)**: **Partial** – generated as a flat expression; **no matched / unmatched / no_parens partition**.
- **expr_list (109–110)**: **Partial** – only newline-separated.
- **eoe (331–333)**: **Partial** – only `eol`; `;` and `eol ';'` missing.
- **matched_expr (155–161)**: **Missing as category** – operands are not distinguished; no `matched_expr -> no_parens_one_expr` separation, no `sub_matched_expr` wrapper.
- **unmatched_expr (163–171)**: **Missing as category** – do-block-bearing expressions not separated from matched/no_parens; unmatched_op_expr not modeled.
- **no_parens_expr (173–179)**: **Missing** – only `call_no_parens_one` (single arg) exists; no `no_parens_many/ambig`, no keyword-arg variants.
- **matched_op_expr / unmatched_op_expr (187–228)**: **Partial** – binary ops exist but only in a single bucket; no `*_op_eol` categories per grammar, no `unmatched_op_expr` recursion.
- **sub_matched_expr (263–267)**: **Missing** – not represented; nullary `range_op`/`ellipsis_op` not emitted.
- **access_expr (273–301)**: **Partial** – literals, identifiers, `capture_int`, `fn`, paren calls are present; **containers, range/ellipsis nullaries, bracket access, paren stabs, empty_paren** are missing.
- **block_expr (181–185)**: **Partial** – `identifier do_block` forms supported; `dot_call_identifier call_args_parens (call_args_parens) do_block` variants not covered; no no-parens+do combinations.
- **stab_expr / stab / stab_parens_many (350–363, 528–529)**: **Partial** – stabs emit patterns/guards but not gated by phase; parenthesized pattern lists allowed but not tied to grammar categories; no `stab_parens_many` wrappers.
- **do_block / block_list (322–329, 368–370)**: **Partial** – `do` + body + `end` plus extras emitted, but without grammar-driven `block_eoe` handling and without guarding against invalid placements.
- **Dot forms (478–498)**: **Missing** – no `dot_identifier`, `dot_alias`, `dot_bracket_identifier`, `dot_paren_identifier`, `dot_op_identifier`, `dot_do_identifier` constructs beyond the simple `dot_call`.
- **Containers / keywords / access**: **Missing** – lists, tuples, maps/structs, bitstrings, assoc/kw, bracket access not present.
- **Strings / heredocs / sigils / quoted identifiers**: **Missing**.

## 3) Required Realignment to the Grammar Categories

To align with `elixir_parser.yrl`, restructure generators/trees to honor the three expression categories:

- **expr** ::= `matched_expr` | `no_parens_expr` | `unmatched_expr`
- **matched_expr** ::= `matched_expr matched_op_expr` | unary variants | `no_parens_one_expr` | `sub_matched_expr`
- **unmatched_expr** ::= do-block-bearing and unmatched-op-bearing forms; cannot appear where matched operands are required.
- **no_parens_expr** ::= `matched_expr no_parens_op_expr` | unary variants | `no_parens_one_ambig_expr` | `no_parens_many_expr`
- **sub_matched_expr** ::= `access_expr` | nullary `range_op` | nullary `ellipsis_op` | `no_parens_zero_expr`
- **access_expr** ::= literals, aliases, dot forms, paren calls, `fn`, paren stabs, containers, captures, etc.

Additionally, wire `eoe` as its own generator (newline, `;`, `eol ';'`) and honor `*_op_eol` productions by category (`matched_op_expr`, `unmatched_op_expr`, `no_parens_op_expr`).

## 4) Concrete Next Steps to Fix Phase 1–2

- **Introduce category-aware generators**: `gen_matched_expr/1`, `gen_unmatched_expr/1`, `gen_no_parens_expr/1`, `gen_sub_matched_expr/1`, each respecting depth/budget and context.
- **Add `eoe` generator**: emit `eol`, `;`, and `eol ;` variants; update `compile_forms/3` to consume grammar `eoe` nodes instead of hardcoding newline.
- **Split binary op handling**: separate `matched_op_expr`, `unmatched_op_expr`, `no_parens_op_expr` with correct operand categories.
- **Implement `sub_matched_expr` nullaries**: emit nullary `range_op` and `ellipsis_op`.
- **Add `access_expr` breadth**: paren stabs/empty_paren, dot_identifier/alias forms, dot_call_identifier, dot_do_identifier, dot_op_identifier; wire `capture_int int` as a distinct production.
- **Guard stabs by phase**: Phase 1 guards off; Phase 2 guards limited to `matched_expr`.
- **Limit do-block placement**: enforce `unmatched_expr` contexts; avoid attaching `do` in matched/no_parens positions.

## 5) Out-of-Scope for Phase 2 (to be added later phases)

- `no_parens_many/ambig` and keyword-argument variants
- Containers (list/tuple/map/struct/bitstring), keyword lists, bracket access
- Strings, heredocs, sigils, quoted atoms/identifiers/keywords, interpolation
- Map/struct updates and assoc variants

Use this snapshot as the alignment checklist before moving to Phase 3+; the immediate focus should be on restoring the matched/unmatched/no-parens separation and proper `eoe` handling. 
