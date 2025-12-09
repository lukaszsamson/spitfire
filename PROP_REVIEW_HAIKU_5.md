# Property Test Grammar Rule Coverage Analysis

## Summary

- **Model**: `claude-haiku-4.5`
- **Tool**: `copilot`
- **Generated**: 2025-12-08 13:10:51
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

I'll analyze the implementation of the `no_parens_one_expr` grammar rules. Let me start by examining the files.

✔ List directory test/spitfire/property
   └ 7 files found

✔ List directory lib/spitfire/property
   └ 9 files found

Now let me examine each file:

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

Now let me search for specific references to `no_parens_one_expr` in the files to understand the implementation:

✔ Grep "no_parens_one" (/Users/lukaszsamson/spitfire/test/spitfire/property)
   └ 29 lines found

Now let me look at the grammar file to understand what `no_parens_one_expr` should generate:

✔ $ grep -n "no_parens_one_expr" /Users/lukaszsamson/spitfire/src/elixir_parser.yrl | head -30
    └ 2 lines...

Let me find the grammar file:

✔ $ find /Users/lukaszsamson/spitfire -name "*parser*" -o -name "*grammar*" | head -20
    └ 21 lines...

✔ $ grep -n "no_parens_one_expr" /Users/lukaszsamson/spitfire/elixir_parser.yrl
    └ 6 lines...

Perfect! Now let me see the full context of these rules:

✔ $ sed -n '257,260p' /Users/lukaszsamson/spitfire/elixir_parser.yrl
    └ 4 lines...

Now I understand. Let me verify what's generated in the code. Let me check how `gen_call_no_parens_one` is currently implemented and see what targets it supports:

✔ Read test/spitfire/property/token_grammar_generators.exs:698-742
   └ 49 lines read

Now let me check what the compiler does with these:

✔ $ grep -n "call_no_parens_one"
    /Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex | head -20
    └ 5 lines...

Perfect! Now let me verify all the cases are covered by looking at each compiler implementation:

✔ Read lib/spitfire/property/token_compiler.ex:738-787
   └ 54 lines read

Excellent! Now let me create a comprehensive analysis. Let me check the grammar file one more time to be absolutely sure about the rules:

✔ $ sed -n '250,270p' /Users/lukaszsamson/spitfire/elixir_parser.yrl
    └ 22 lines...

Perfect! Now let me create a detailed analysis document. Let me also check what happens in matched_expr:

✔ $ sed -n '155,165p' /Users/lukaszsamson/spitfire/elixir_parser.yrl
    └ 12 lines...

Perfect! Now I have all the information I need. Let me create a comprehensive analysis:

✘ $ cat > /tmp/analysis.md << 'EOF'
   # Analysis of `no_parens_one_expr` Implementation

   ## Grammar Rules
   According to `elixir_parser.yrl` lines 258-259:...
   Permission denied and could not request permission from user

Let me output the analysis directly:

✔ $ cat << 'EOF'
    # ANALYSIS: no_parens_one_expr Implementation Review

    ## GRAMMAR RULES (elixir_parser.yrl lines 258-259)
    ```...
    └ 218 lines...

Perfect! Now let me create a concrete list of actions needed:

✔ $ cat << 'EOF'

    ================================================================================
    CONCRETE ACTIONS TO FIX GAPS
    ================================================================================...
    └ 241 lines...

Perfect! Now let me create a final summary document:

## Summary

I've completed a comprehensive analysis of the `no_parens_one_expr` implementation across the three files. Here are the **concrete actions needed**:

### **FINDING: One Target Type is Not Aligned with Grammar**

The grammar defines `no_parens_one_expr` with only 2 rules (lines 258-259):
1. `dot_op_identifier call_args_no_parens_one` (e.g., `expr.+ bar`)
2. `dot_identifier call_args_no_parens_one` (e.g., `foo bar` or `Mod.fun bar`)

However, both the **generator and compiler support 4 target variants**, including:
- ✓ Simple identifier (`foo bar`)
- ✓ Dotted identifier (`Mod.fun bar`)
- ✓ Dotted operator identifier (`expr.+ bar`)
- ⚠️ **Bare operator identifier** (`+ bar`) ← **NOT IN GRAMMAR**

---

### **CONCRETE ACTION ITEMS**

**ACTION 1: Remove bare operator from generator**
- **File**: `test/spitfire/property/token_grammar_generators.exs`
- **Location**: `gen_call_no_parens_one` function, lines 713-715
- **Change**: Delete the op_identifier frequency entry
```elixir
# DELETE THESE 3 LINES:
# Operator-as-identifier: +/2, -/2 (op_identifier)
{1, StreamData.bind(StreamData.member_of(@binary_ops), fn {_, op} -> StreamData.constant({:op_identifier, op}) end)}
```

**ACTION 2: Remove bare operator from compiler**
- **File**: `lib/spitfire/property/token_compiler.ex`
- **Location**: `do_to_tokens` function, lines 752-764
- **Change**: Delete the entire `op_identifier` case
```elixir
# DELETE ENTIRE CLAUSE (lines 752-764):
defp do_to_tokens({:call_no_parens_one, {:op_identifier, op}, arg}, layout, opts) do
  # ... 12 lines ...
end
```

**ACTION 3: Add clarifying comment to generator** (optional but recommended)
- **File**: `test/spitfire/property/token_grammar_generators.exs`
- **Location**: Before `gen_call_no_parens_one` function (line 701)
- **Add**: Documentation explaining the 2 valid target types per grammar

**ACTION 4: Verify warn_pipe pattern**
- **File**: `test/spitfire/property/token_grammar_generators.exs`
- **Location**: `gen_matched_op_warn_pipe` function uses `gen_call_no_parens_one`
- **Status**: Will automatically be fixed by Actions 1-2; no changes needed here

---

### **VERIFICATION**

After applying these changes:
- ✓ All 3 remaining generator targets match grammar rules 258-259
- ✓ All 3 compiler implementations match generator outputs  
- ✓ Code is aligned with real Elixir semantics (bare operators like `+ 1` are invalid)
- ✓ warn_pipe pattern still works correctly

**Total lines to delete**: ~15 lines across 2 files



STDERR:

Total usage est:       0.33 Premium requests
Total duration (API):  1m 21.915s
Total duration (wall): 1m 41.042s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    claude-haiku-4.5     1.5m input, 7.6k output, 1.4m cache read (Est. 0.33 Premium requests)


---

## no_parens_zero_expr

**Grammar Rules (2):**

```erlang
no_parens_zero_expr -> dot_do_identifier : build_identifier('$1').
no_parens_zero_expr -> dot_identifier : build_identifier('$1').
```

**Analysis:**

I'll analyze the implementation to review how `no_parens_zero_expr` grammar rules are handled.

✔ List directory .
   └ 78 files found

✔ List directory test/spitfire/property
   └ 7 files found

Now let me view the specific files:

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

Now let me search for how `no_parens_zero_expr` is being generated and compiled:

✔ $ grep -n "no_parens_zero_expr"
    /Users/lukaszsamson/spitfire/test/spitfire/property/token_grammar_generators.exs
    /Users/lukaszsamson/spitfire/lib/spitfire/property/token_compiler.ex 2>/dev/null | head -30
    └ 9 lines...

Now let me look at the actual grammar to understand the exact rules:

✔  $ grep -A2 -B2 "^no_parens_zero_expr" /Users/lukaszsamson/spitfire/elixir_parser.yrl 2>/dev/null
     || echo "File not found, searching in other locations..."
    └ 7 lines...

Perfect! Now I have all the information. Let me create a comprehensive analysis document:

✘ $ cat > /tmp/no_parens_zero_expr_analysis.md << 'EOF'
   # Analysis: no_parens_zero_expr Grammar Rules Implementation

   ## Grammar Rules (from elixir_parser.yrl)...
   Permission denied and could not request permission from user

Let me provide the analysis directly:

## Analysis Summary: `no_parens_zero_expr` Grammar Rules Implementation

Based on my review of the three files, here's what I found:

### Grammar Rules (elixir_parser.yrl)
```erlang
no_parens_zero_expr -> dot_do_identifier : build_identifier('$1').
no_parens_zero_expr -> dot_identifier : build_identifier('$1').
```

**Only 2 production rules exist for `no_parens_zero_expr`.**

---

## Issues Found

### ❌ **Issue 1: Bare Identifiers Generated Incorrectly**

**Location:** `TokenGrammarGenerators.ex` lines 1653-1662

```elixir
def gen_no_parens_zero_expr do
  StreamData.frequency([
    {6, gen_identifier()},           # ❌ INCORRECT - NOT IN GRAMMAR
    {2, gen_dot_identifier()},       # ✓ Correct
    {1, gen_dot_do_identifier()}     # ✓ Correct (but wrong weight)
  ])
end
```

**Problem:** The generator produces `{:identifier, atom}` (bare identifiers like `foo`), but the grammar ONLY produces:
- `dot_identifier` (e.g., `expr.foo` or simple `foo` wrapped as dot_identifier) 
- `dot_do_identifier` (e.g., `if`, `case`, or `Mod.if`)

**Impact:** Bare identifiers should NOT be generated at the `no_parens_zero_expr` level.

---

### ❌ **Issue 2: Inverted Frequency Weights**

**Current weights:** `{6, gen_identifier()}`, `{2, gen_dot_identifier()}`, `{1, gen_dot_do_identifier()}`

**Problem:**
- Bare identifiers (weight 6) = NOT in grammar yet get highest frequency
- `dot_do_identifier` (weight 1) = Grammar rule #1, gets lowest frequency  
- `dot_identifier` (weight 2) = Grammar rule #2, gets middle frequency

**Impact:** Distribution doesn't reflect grammar rule importance or frequency.

---

### ✓ **Issue 3: Compiler Implementation IS CORRECT**

The `TokenCompiler.ex` properly handles:
- Line 117-122: `{:identifier, atom}` → compiles to identifier token
- Line 125-131: `{:do_identifier, atom}` → compiles to do_identifier token
- Line 154-171: `{:dot_identifier, left, right_name}` → compiles dot notation
- Line 191-208: `{:dot_do_identifier, left, do_id}` → compiles dotted do_identifier

**Compiler has no issues.** The problem is entirely in the generator.

---

## Concrete Action Items

### Action 1: Remove Bare Identifier Generation (MUST FIX)
**File:** `test/spitfire/property/token_grammar_generators.exs` line 1653-1662

**Change:**
```elixir
# BEFORE (3 types - WRONG):
def gen_no_parens_zero_expr do
  StreamData.frequency([
    {6, gen_identifier()},           # ❌ REMOVE THIS
    {2, gen_dot_identifier()},
    {1, gen_dot_do_identifier()}
  ])
end

# AFTER (2 types - CORRECT):
def gen_no_parens_zero_expr do
  StreamData.frequency([
    {5, gen_dot_do_identifier()},    # Grammar Rule 1: do_identifier forms
    {3, gen_dot_identifier()}        # Grammar Rule 2: dot_identifier forms
  ])
end
```

**Rationale:** Matches the 2 grammar rules exactly.

---

### Action 2: Update Weights to Reflect Grammar (SHOULD FIX)
The 5:3 weighting above favors do_identifiers slightly, which aligns with:
- Grammar rules of Elixir (if/unless/case/etc. are common control flow)
- The generator's own patterns (do_identifier has 4 variants internally via `gen_dot_do_identifier`)

---

### Action 3: Add Documentation (SHOULD FIX)
**Location:** Same file, add docstring to `gen_no_parens_zero_expr/0`

```elixir
@doc """
Generate a no_parens_zero_expr (bare identifier or dotted identifier).

Per grammar lines 260-261:
- no_parens_zero_expr -> dot_do_identifier
- no_parens_zero_expr -> dot_identifier

Note: Bare identifiers are NOT generated here. They only appear through
the `dot_identifier` and `dot_do_identifier` rules, never standalone.
Identifiers belong in `dot_identifier` context (as left or right parts).
"""
```

---

## Verification Checklist

- [ ] Remove `gen_identifier()` call from `gen_no_parens_zero_expr()`
- [ ] Update frequency weights to `{5, gen_dot_do_identifier()}`, `{3, gen_dot_identifier()}`
- [ ] Run property tests: `mix test test/spitfire/token_property_test.exs`
- [ ] Confirm no new test failures
- [ ] Confirm rejection rate < 70% (per test code line 77)

---

## Summary

| Aspect | Status | Details |
|--------|--------|---------|
| **Grammar Rule 1** (`dot_do_identifier`) | ✓ Implemented | Correct, but wrong weight |
| **Grammar Rule 2** (`dot_identifier`) | ✓ Implemented | Correct |
| **Bare Identifier Generation** | ❌ **BUG** | Should NOT be generated |
| **Compiler** | ✓ Correct | No changes needed |
| **Frequency Weighting** | ❌ **WRONG** | Inverted priority |

**Severity:** Medium - The generator produces grammatically invalid node types, but the compiler still handles them. Tests likely pass because normalization masks the issue, but the property test is generating invalid grammar trees.



STDERR:

Total usage est:       0.33 Premium requests
Total duration (API):  42s
Total duration (wall): 51s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    claude-haiku-4.5     432.2k input, 4.0k output, 343.5k cache read (Est. 0.33 Premium requests)


---

## parens_call

**Grammar Rules (2):**

```erlang
parens_call -> dot_call_identifier call_args_parens : build_parens('$1', '$2', {[], []}).
parens_call -> dot_call_identifier call_args_parens call_args_parens : build_nested_parens('$1', '$2', '$3', {[], []}).
```

**Analysis:**

I'll analyze the property test implementation for `parens_call` grammar rules. Let me start by examining the relevant files.

✔ List directory test/spitfire/property
   └ 7 files found

✔ List directory lib/spitfire/property
   └ 9 files found

✔ Read test/spitfire/token_property_test.exs
   └ 425 lines read

✔ Read lib/spitfire/property/token_compiler.ex
   └ 2833 lines read

✔ Read test/spitfire/property/token_grammar_generators.exs
   └ 2844 lines read

Now let me search for the specific `parens_call` implementations in the grammar generators and compiler:

✔ Grep "parens_call" (/Users/lukaszsamson/spitfire)
   └ 14 files found

✔ Grep "parens_call" (/Users/lukaszsamson/spitfire/elixir_parser.yrl)
   └ 4 lines found

Now let me search for how the generators handle parens_call:

✔ $ cd /Users/lukaszsamson/spitfire && grep -n "block_parens\|call_parens"
    test/spitfire/property/token_grammar_generators.exs | head -20
    └ 16 lines...

Perfect! Now let me understand the exact issue. Let me look at the grammar rules more carefully and check how `parens_call` relates to the generators:

✔ $ cd /Users/lukaszsamson/spitfire && grep -B2 -A2 "parens_call\|call_args_parens"
    elixir_parser.yrl | head -40
    └ 41 lines...

Now let me check what `gen_access_expr` does in relation to parens_call:

✔ $ cd /Users/lukaszsamson/spitfire && grep -n "gen_access_expr"
    test/spitfire/property/token_grammar_generators.exs | head -20
    └ 6 lines...

Let me look at the access_expr implementation more carefully:

✔ Read test/spitfire/property/token_grammar_generators.exs:1745-1776
   └ 37 lines read

Now I understand the issue! The `parens_call` grammar rule is for calls **without** a `do_block`. Let me verify what `call_parens` vs `parens_call` do:

1. **`call_parens`** - in `gen_call_parens` - represents `foo(args)` or `expr.(args)` - used as matched expressions
2. **`parens_call`** - in the grammar, it's just `dot_call_identifier call_args_parens` or `dot_call_identifier call_args_parens call_args_parens` - this is used in `access_expr`

The key insight: `parens_call` is generated by `gen_call_parens` in the `gen_access_expr` function!

Let me verify the compiler handles this correctly:

✔ $ cd /Users/lukaszsamson/spitfire && grep -n "parens_call\|call_parens"
    lib/spitfire/property/token_compiler.ex | head -30
    └ 4 lines...

Now I need to understand the distinction better. Let me check the grammar rules for `block_expr` vs `parens_call`:

✔ $ cd /Users/lukaszsamson/spitfire && grep -B1 -A1 "^block_expr\|^parens_call" elixir_parser.yrl
    └ 11 lines...

Perfect! Now I see the issue clearly:

**Grammar Rules for `parens_call` (lines 299-300):**
1. `parens_call -> dot_call_identifier call_args_parens : build_parens('$1', '$2', {[], []})`
   - Simple parenthesized call: `foo()`, `Mod.foo()`, `expr.()`

2. `parens_call -> dot_call_identifier call_args_parens call_args_parens : build_nested_parens('$1', '$2', '$3', {[], []})`
   - Nested parenthesized call: `foo()()`, `Mod.foo()()`, `expr.()()`

**Grammar Rules for `block_expr` (lines 181-185):**
1. Same signature as `parens_call` but with a `do_block` at the end
2. Same for nested version

Now let me verify whether the generators actually generate both cases. Looking at the code:

- `gen_call_parens` generates `{:call_parens, target, args}` - used in `gen_access_expr`
- `gen_block_parens` generates `{:block_parens, target, args, do_block}` - used in `gen_block_expr`

The issue is: **`parens_call` should have TWO cases, but `gen_call_parens` only generates simple calls!**

Let me check if there's a nested variant:

✔ Read test/spitfire/property/token_grammar_generators.exs:654-673
   └ 25 lines read

Now let me create a summary document analyzing the gaps:

✔ $ cd /Users/lukaszsamson/spitfire && grep -A 15 "defp gen_call_parens"
    test/spitfire/property/token_grammar_generators.exs
    └ 17 lines...

Now let me check how the compiler handles `call_parens`:

✔ Read lib/spitfire/property/token_compiler.ex:719-737
   └ 23 lines read

Now I see the complete picture. Let me verify my findings by checking the test:

✔ $ cd /Users/lukaszsamson/spitfire && head -100 test/spitfire/token_property_test.exs | tail -50
    └ 50 lines...

Perfect! Now I have all the information I need. Let me create a summary of my findings:

## Analysis Summary

After reviewing the implementation of property tests for the `parens_call` grammar rules, here are my findings:

### Grammar Rules for `parens_call` (elixir_parser.yrl lines 299-300)

**Rule 1:** `parens_call -> dot_call_identifier call_args_parens`
- Represents simple parenthesized calls: `foo()`, `Mod.foo()`, `expr.()`
- Expected AST: `build_parens('$1', '$2', {[], []})`

**Rule 2:** `parens_call -> dot_call_identifier call_args_parens call_args_parens`
- Represents nested parenthesized calls: `foo()()`, `Mod.foo()()`, `expr.()()`
- Expected AST: `build_nested_parens('$1', '$2', '$3', {[], []})`

### Generator Implementation

**Current Status:**
- `gen_call_parens` (line 655-673) only implements **Rule 1**
- It generates a single `{:call_parens, target, args}` structure
- **Rule 2 (nested parens_call) is NOT generated**

**Location in gen_access_expr:**
- Lines 1749-1776 define `gen_access_expr`
- Line 1753: `{2, gen_call_parens(state)}` includes call_parens generation
- This is the only place where parens_call should be generated (apart from block_expr variants)

### Compiler Implementation

**Current Status:**
- Line 720-736 in `token_compiler.ex`: handles `{:call_parens, target, args}`
- This compiles to tokens for simple calls only
- **No handler for nested calls** - would fail with "unimplemented" error if encountered

### Nested Parens Call Handling

**Related but different rule (block_expr):**
- `gen_block_parens_nested` (line 1306-1328) generates `{:block_parens_nested, target, args1, args2, do_block}`
- Compiler handles this at line 1150-1194
- This is for `foo()() do ... end` form (WITH do_block), not the bare `foo()()` form

---

## Concrete List of Actions Needed

### ✅ **FINDING: Gap Identified in parens_call Coverage**

1. **Missing Generator for Nested Parens Calls Without Do Block**
   - **File:** `test/spitfire/property/token_grammar_generators.exs`
   - **Location:** Near line 655 (`gen_call_parens`)
   - **Action:** Add a new generator function `gen_call_parens_nested` that generates `{:call_parens_nested, target, args1, args2}` for the second grammar rule
   - **Frequency:** Should be less common than simple call_parens (suggest 1:5 or 1:3 ratio in gen_access_expr)

2. **Missing Compiler Handler for Nested Parens Calls**
   - **File:** `lib/spitfire/property/token_compiler.ex`
   - **Location:** After line 736 (after simple call_parens handler)
   - **Action:** Add `defp do_to_tokens({:call_parens_nested, target, args1, args2}, layout, opts)` that:
     - Compiles target
     - Compiles first `(args1)`
     - Compiles second `(args2)` stuck to first closing paren
     - Returns combined tokens

3. **Update gen_access_expr to Include Nested Call Variant**
   - **File:** `test/spitfire/property/token_grammar_generators.exs`
   - **Location:** Line 1753 (frequency for call_parens)
   - **Action:** Add frequency entry for the new `gen_call_parens_nested` generator (suggest weight of 1)

4. **Add Adhesion Variant for Nested Parens Calls**
   - **File:** `lib/spitfire/property/token_compiler.ex`
   - **Location:** Near line 1703 (compile_arg_with_adhesion for call_parens)
   - **Action:** Add adhesion version of nested parens call handler

5. **Consider Edge Cases**
   - Verify nested parens calls work with `dot_paren_identifier` targets (Mod.foo()())
   - Verify nested parens calls work with `dot_call` targets (expr.()())
   - These should be generated by the nested variant's target_gen

---

## Conclusion

**Are all cases for `parens_call` implemented?**  
❌ **NO.** Only the simple case (Rule 1) is implemented. The nested case (Rule 2) is **completely missing**.

**Are any cases marked as TODO?**  
❌ **NO.** There are no TODO comments; the gap is silent.

**Is the implementation correct according to grammar?**  
⚠️ **Partially.** Rule 1 is correctly implemented; Rule 2 is missing entirely.

**Are there edge cases or variations missing?**  
✅ **YES.** The nested variant has multiple target forms that should be covered:
- Simple `{:paren_identifier, name}`
- Dotted `{:dot_paren_identifier, left, name}`
- Dot call `{:dot_call, expr}`



STDERR:

Total usage est:       0.33 Premium requests
Total duration (API):  52s
Total duration (wall): 1m 3.417s
Total code changes:    0 lines added, 0 lines removed
Usage by model:
    claude-haiku-4.5     1.4m input, 3.8k output, 1.2m cache read (Est. 0.33 Premium requests)


---

