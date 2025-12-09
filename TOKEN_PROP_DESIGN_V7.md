# Token-Driven Property Tests Design (V7)

V7 is the final, frozen implementation spec for token-driven properties. It
refines V6 with very small clarifications from the V6 reviews; nothing
structural has changed.

V7 is the **only** design document you should follow when implementing this
feature.

---

## 1. Step 0 – `Toxic.to_string/1` Verification (Final)

Step 0 must be implemented and run **before** any property fuzzing or generator
work.

### 1.1. Meta format and `extra`

- Use **ranged metas**: `{kind, {{sl, sc}, {el, ec}, extra}}`.
- Confirm `extra` behavior:
  - `:eol`, `:","`, `:";"` – newline count (>= 1)
  - Numbers – parsed numeric value (or `nil` if Toxic ignores it)
  - Atoms/aliases/identifiers/kw identifiers – original charlist when available
  - Operators, `:block_identifier` – `extra` `nil` or `0` (we never rely on
    them for newlines)

### 1.2. Smoke-test checklist (extended)

Same as in V6, with additional edge cases; see V6 §1.2. At minimum, include:

- All adhesion examples: `%{a: 1}`, `&10`, `foo.(1)`
- All numeric formats mentioned in V6
- Atoms and quoted atoms like `:"foo\nbar"`
- Guards and blocks (`case` with `when`)
- A heredoc and a sigil heredoc where you can assert the
  **closing delimiter column** (see §3.3 and §7)

If any behavior deviates (double newlines, wrong adhesion, incorrect heredoc
closing column), fix `TokenLayout`/`to_tokens/2`, **then treat that behavior as
canonical** going forward.

---

## 2. Canonical Newline Model (No Branches)

The newline model is **fixed**:

- Only `:eol`, `:","`, and `:";"` tokens render newlines.
- Operators and keywords never render newlines from `extra`.
- `_op_eol` and `*_eoe` grammar nodes **always** compile to:

  ```elixir
  # Example for an operator with n newlines after it
  [{:some_op_token, meta_op(extra: 0), op}, {:eol, meta_eol(extra: n)}]
  ```

- If Step 0 reveals Toxic also interprets operator `extra` as newline counts,
  we set operator/keyword `extra` to `0` and rely solely on `:eol` tokens.

There is no alternative model; if Toxic behaves differently, we shim around it
in `to_tokens/2` and keep this abstraction.

---

## 3. Interpolation and Heredoc Metas (Explicit Spans)

### 3.1. Interpolation brace spans

For interpolation tokens:

- `begin_interpolation` meta spans exactly the `"#{"` lexeme.
- Inner tokens start **after** `{` and advance layout over their **entire**
  rendered code (including internal newlines).
- `end_interpolation` meta spans exactly `"}"` and starts immediately after the
  inner code.

Deterministic tests must assert that **ranges are monotonic** even when the
inner interpolated code is multi-line.

### 3.2. Heredoc closing column

For heredocs (and sigil heredocs):

- After `*_heredoc_start`, layout moves to the **next** line at column 1.
- Each `:string_fragment` advances layout over its bytes, including `"\n"`.
- The closing `*_heredoc_end` meta:
  - Starts at column `indent + 1` on the line after the last fragment, where
    `indent` is the leading-space count of the closing delimiter.
  - Ends after the delimiter.
- Tokens after the heredoc start immediately after that closing delimiter.

Include at least one deterministic test along these lines:

```elixir
# """
#   hello
#   """
# indent = 2 ⇒ closing at col 3

tree = {:bin_heredoc, 2, [{:fragment, "hello\n"}]}

# ...to_tokens/2, Toxic.to_string/1, etc...
# Assert closing delimiter column == 3
```

---

## 4. Atom/Identifier `extra` and Quoted Identifiers

The `extra` table from V6 is final; we only clarify quoted identifiers:

- Quoted identifiers that collapse to
  `:identifier`/`:paren_identifier`/`:bracket_identifier`/`:do_identifier`/
  `:op_identifier` **must** carry the **original quoted chars** in `extra`.
- This ensures `get_extra_or_atom/2` (or equivalent) can re-render the exact
  original form, including quotes and escapes.

Everything else in V6 §3.2 remains as written.

---

## 5. Guards and Phase 1 Enforcement

Guard scope is as in V6; we only stress the enforcement point:

- Phase 1:
  - `{:stab_clause, pattern, guard, body}` must have `guard == nil`.
  - Generators must not introduce `when` anywhere in `fn` clauses.
- Phase 2+:
  - Guards allowed, but restricted to `matched_expr` trees and modest depth.

Implementation detail: ensure Phase-2 guard generators are **not reused**
unmodified in Phase 1.

---

## 6. Warnings: Default Gating and Assertion

V6 fixes the default gating; V7 adds an assertion:

- Core properties run with `emit_warnings: false` and `warnings_on: false`.
- Generators do not intentionally emit:
  - `warn_trailing_comma/1`
  - `warn_pipe/2`
  - `warn_no_parens_after_do_op/1`
  - `warn_nested_no_parens_keyword/2`
- Additionally, the core properties should **track and assert** that no
  warning-producing constructs were hit:

  ```elixir
  {warnings, _others} = get_warning_counters()
  assert warnings == 0
  ```

- A separate, opt-in `warnings_on: true` mode may later test these shapes
  explicitly with different properties.

---

## 7. Grammar Tree and Types (Reference)

The grammar-tree node list and helper aliases from V6 §2 are complete. For
implementation, you should also define:

```elixir
# String parts (strings, sigils, heredocs, quoted forms)
@type string_part_t :: {:fragment, binary()} | {:interpolation, [expr_t()]}

# Stab-related
@type stab_clause_t :: {:stab_clause, pattern_t(), guard_t(), expr_t()}
@type stab_t :: [stab_clause_t()]
@type pattern_t :: :empty | {:single, expr_t()} | {:many, [expr_t()]}
@type guard_t :: nil | expr_t()

# Block-related
@type call_t ::
        {:call_parens, target_t(), [expr_t()]}
      | {:call_no_parens_one, target_t(), expr_t()}
      | {:call_no_parens_many, target_t(), [expr_t()]}
      | {:call_no_parens_ambig, target_t(), expr_t()}

@type do_block_t :: {:do_block, stab_t() | [expr_t()], [block_item_t()]}
@type block_item_t :: {:block_item, :after | :else | :catch | :rescue,
                       stab_t() | [expr_t()]}

# Expression category aliases
@type matched_t :: expr_t()
@type unmatched_t :: expr_t()
@type no_parens_t :: expr_t()
@type sub_matched_t :: expr_t()
@type access_t :: expr_t()

# Operator kinds (sketch)
@type op_kind :: term()  # refine as needed from the grammar

# Budget / state
@type budget :: %{depth: non_neg_integer(), nodes_left: non_neg_integer()}
@type state :: %{budget: budget(), context: context()}
```

You can refine `op_kind` into a more precise union using the Elixir parser’s
operator families as needed; the exact shape is an implementation detail.

---

## 8. Phases (Embedded Summary)

For convenience (so you don’t have to open V5):

| Phase | Main additions (on top of previous phases) |
|-------|-------------------------------------------|
| 1     | Literals, identifiers, matched/unary/binary ops, `fn_single`, `parens_call`, `capture_int`, `no_parens_one` (no keyword args) |
| 2     | `unmatched_expr`, `do_block`, `fn_multi`, block lists (`else`/`rescue`/`catch`/`after`), simple stab patterns |
| 3     | Full `no_parens_expr` family, `when` + keywords, complex do-block/no-parens combinations |
| 4     | Containers (lists/tuples/maps/bitstrings), keyword lists, bracket access, map/struct updates, `dot_container` |
| 5     | Strings, heredocs, sigils, quoted atoms/keywords/identifiers, interpolation |

Phase 1 must **not** include guarded stabs or keyword-based `no_parens_expr`.

---

## 9. Deterministic `to_tokens/2` Tests (Concrete Heredoc Example)

The deterministic “golden” tests from V6 stand; V7 only makes the heredoc
assertion concrete. For example:

```elixir
test "heredoc closing delimiter position" do
  # """
  #   hello
  #   """
  tree = {:bin_heredoc, 2, [{:fragment, "hello\n"}]}

  tokens = TokenGrammarGenerators.to_tokens(tree, phase: 5)
  code = Toxic.to_string(tokens)

  assert code == ~S""""
  hello
  """"  # three quotes, two-space indent

  {:bin_heredoc_end, {{_sl, _sc}, {_el, closing_col}, _extra}, _delim, _indent} =
    Enum.find(tokens, &match?({:bin_heredoc_end, _, _, _, _}, &1))

  assert closing_col == 3  # indent (2) + 1
end
```

You do not need exactly this code, but you should assert:

- The closing delimiter’s column is `indent + 1`.
- The token after the heredoc starts immediately after that column.

---

## 10. AST Normalization, Acceptance Guard, and Warnings

V6’s rules on AST normalization and acceptance guard remain unchanged:

- Strip meta keys: `:from_brackets`, `:ambiguous_op`, `:parens`, `:format`,
  `:closing` (and `:end_of_expression` if needed).
- Enforce:

  ```elixir
  assert accepted > 0
  rejection_rate = rejected / (accepted + rejected)
  assert rejection_rate < 0.7
  ```

And with V7’s addition, also assert that the **warning count is zero** in the
core properties.

---

## 11. Implementation Order (Unchanged)

Follow this order when implementing:

1. Step 0 (`ToxicToStringSmokeTest`).
2. `TokenLayout` and `GrammarTree` (with types and helpers from V6/V7).
3. Phase 1 generators + `to_tokens/2` + deterministic “golden” tests.
4. Enable Phase 1 property with acceptance and warning guards.
5. Incrementally add Phases 2–5, each with added deterministic coverage.

V7 is the final word on the design; older versions are only historical
background. Start coding against this document. 