defmodule Spitfire.Property.GrammarTree do
  @moduledoc """
  Type definitions for grammar tree nodes.

  Grammar trees are intermediate representations that compile to Toxic tokens.
  Each node type corresponds to a syntactic construct in Elixir.

  ## Phase Coverage

  - **Phase 1**: Literals, identifiers, matched/unary/binary ops, fn_single,
    parens_call, capture_int, no_parens_one (no keyword args)
  - **Phase 2+**: Guards, do_blocks, fn_multi, keyword args, etc.
  """

  # ===========================================================================
  # Top-level types
  # ===========================================================================

  @typedoc "A complete grammar tree (program)"
  @type t :: {:grammar, [expr_t()]}

  @typedoc "Any expression"
  @type expr_t :: t()

  @typedoc "Pattern expression (for fn arguments)"
  @type pattern_t :: :empty | {:single, expr_t()} | {:many, [expr_t()]}

  @typedoc "Guard expression (nil in Phase 1)"
  @type guard_t :: nil | expr_t()

  # ===========================================================================
  # Phase 1: Literals
  # ===========================================================================

  @typedoc """
  Integer literal.

  - `value`: the numeric value
  - `format`: `:dec`, `:hex`, `:bin`, or `:oct`
  - `chars`: the original charlist representation (e.g., `~c"123"`, `~c"0xFF"`)
  """
  @type int_t :: {:int, value :: integer(), format :: :dec | :hex | :bin | :oct, chars :: charlist()}

  @typedoc """
  Float literal.

  - `value`: the numeric value
  - `chars`: the original charlist representation (e.g., `~c"1.0"`, `~c"1.0e-10"`)
  """
  @type float_t :: {:float, value :: float(), chars :: charlist()}

  @typedoc """
  Character literal.

  - `codepoint`: the character codepoint
  - `chars`: the original charlist representation (e.g., `~c"?a"`, `~c"?\\n"`)
  """
  @type char_t :: {:char, codepoint :: integer(), chars :: charlist()}

  @typedoc "Atom literal (unquoted)"
  @type atom_lit_t :: {:atom_lit, atom()}

  @typedoc "Boolean literal"
  @type bool_lit_t :: {:bool_lit, true | false}

  @typedoc "Nil literal"
  @type nil_lit_t :: :nil_lit

  @typedoc "All literal types"
  @type literal_t :: int_t() | float_t() | char_t() | atom_lit_t() | bool_lit_t() | nil_lit_t()

  # ===========================================================================
  # Phase 1: Identifiers and Aliases
  # ===========================================================================

  @typedoc "Simple identifier (e.g., `foo`)"
  @type identifier_t :: {:identifier, atom()}

  @typedoc "Alias (e.g., `Foo`, `MyApp.Context`)"
  @type alias_t :: {:alias, atom()}

  @typedoc "Paren identifier - identifier immediately followed by `(` (e.g., `foo(`)"
  @type paren_identifier_t :: {:paren_identifier, atom()}

  @typedoc "Bracket identifier - identifier immediately followed by `[` (e.g., `foo[`)"
  @type bracket_identifier_t :: {:bracket_identifier, atom()}

  @typedoc "Do identifier - identifier followed by `do` (e.g., `if`, `case`)"
  @type do_identifier_t :: {:do_identifier, atom()}

  @typedoc "Op identifier - identifier in operator position"
  @type op_identifier_t :: {:op_identifier, atom()}

  @typedoc "All identifier types"
  @type any_identifier_t ::
          identifier_t()
          | alias_t()
          | paren_identifier_t()
          | bracket_identifier_t()
          | do_identifier_t()
          | op_identifier_t()

  # ===========================================================================
  # Phase 1: Operators
  # ===========================================================================

  @typedoc """
  Operator kind and value.

  - First element: operator category (`:dual_op`, `:mult_op`, etc.)
  - Second element: the operator atom (`:+`, `:*`, etc.)
  """
  @type op_kind :: {atom(), atom()}

  @typedoc """
  Operator with optional trailing newlines.

  - `op_kind`: the operator category and value
  - `newlines`: number of newlines after the operator (0 = no newline)
  """
  @type op_eol_t :: {:op_eol, op_kind(), non_neg_integer()}

  @typedoc """
  Binary operator expression.

  - `left`: left operand
  - `op`: operator with optional newlines
  - `right`: right operand
  """
  @type binary_op_t :: {:binary_op, expr_t(), op_eol_t(), expr_t()}

  @typedoc """
  Unary operator expression.

  - `op`: operator kind
  - `operand`: the operand expression
  """
  @type unary_op_t :: {:unary_op, op_kind(), expr_t()}

  # ===========================================================================
  # Phase 1: Calls and Captures
  # ===========================================================================

  @typedoc "Target of a call (identifier, paren_identifier, or dot expression)"
  @type target_t ::
          identifier_t()
          | paren_identifier_t()
          | {:dot, expr_t(), identifier_t() | op_identifier_t()}
          | {:dot_call, expr_t()}

  @typedoc """
  Parenthesized call expression (e.g., `foo(1, 2)` or `foo.(1)`).

  - `target`: the call target
  - `args`: list of arguments
  """
  @type call_parens_t :: {:call_parens, target_t(), [expr_t()]}

  @typedoc """
  No-parens call with one argument (e.g., `foo bar`).

  Phase 1 restriction: no keyword arguments allowed.
  """
  @type call_no_parens_one_t :: {:call_no_parens_one, target_t(), expr_t()}

  @typedoc """
  Dot-call expression (e.g., `foo.(1)`).

  The expression is the target to call.
  """
  @type dot_call_t :: {:dot_call, expr_t()}

  @typedoc """
  Capture integer (e.g., `&1`, `&10`).

  Must be a positive integer.
  """
  @type capture_int_t :: {:capture_int, pos_integer()}

  # ===========================================================================
  # Phase 1: Functions (fn_single)
  # ===========================================================================

  @typedoc """
  Stab clause for fn expressions.

  - `pattern`: the pattern (`:empty`, `{:single, expr}`, or `{:many, [expr]}`)
  - `guard`: guard expression (must be nil in Phase 1)
  - `body`: the body expression
  """
  @type stab_clause_t :: {:stab_clause, pattern_t(), guard_t(), expr_t()}

  @typedoc """
  Single-clause fn expression.

  Phase 1: only one clause, no guards, simple patterns (`:empty` or `{:single, expr}`).
  """
  @type fn_single_t :: {:fn_single, [stab_clause_t()]}

  # ===========================================================================
  # Later Phases (placeholders)
  # ===========================================================================

  @typedoc "Multi-clause fn expression (Phase 2+)"
  @type fn_multi_t :: {:fn_multi, [stab_clause_t()]}

  @typedoc "Do block (Phase 2+)"
  @type do_block_t :: {:do_block, [stab_clause_t()] | [expr_t()], [block_item_t()]}

  @typedoc "Block item (else, rescue, catch, after) (Phase 2+)"
  @type block_item_t ::
          {:block_item, :after | :else | :catch | :rescue, [stab_clause_t()] | [expr_t()]}

  @typedoc "List container (Phase 4)"
  @type list_t :: {:list, [expr_t()]}

  @typedoc "Tuple container (Phase 4)"
  @type tuple_t :: {:tuple, [expr_t()]}

  @typedoc "Map container (Phase 4)"
  @type map_t :: {:map, [assoc_t()]}

  @typedoc "Association (key => value or key: value) (Phase 4)"
  @type assoc_t :: {:assoc, expr_t(), expr_t()} | {:kw, atom(), expr_t()}

  @typedoc "String (Phase 5)"
  @type string_t :: {:bin_string, [string_part_t()]}

  @typedoc "String part (fragment or interpolation) (Phase 5)"
  @type string_part_t :: {:fragment, binary()} | {:interpolation, [expr_t()]}

  # ===========================================================================
  # Context and Budget
  # ===========================================================================

  @typedoc """
  Generation context flags.

  Controls what constructs are allowed during generation.
  """
  @type context :: %{
          phase: 1..5,
          in_do_block: boolean(),
          in_no_parens_many: boolean(),
          in_keyword_value: boolean(),
          in_parens_call_arg: boolean(),
          allow_unmatched: boolean(),
          allow_do_block: boolean(),
          allow_no_parens_many: boolean(),
          allow_ternary_after_range: boolean(),
          interpolation_depth: non_neg_integer()
        }

  @typedoc """
  Generation budget to control tree size and depth.
  """
  @type budget :: %{
          depth: non_neg_integer(),
          nodes_left: non_neg_integer()
        }

  @typedoc """
  Generator state combining budget and context.
  """
  @type state :: %{
          budget: budget(),
          context: context()
        }

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc "Create initial generation context for Phase 1"
  @spec phase1_context() :: context()
  def phase1_context do
    %{
      phase: 1,
      in_do_block: false,
      in_no_parens_many: false,
      in_keyword_value: false,
      in_parens_call_arg: false,
      allow_unmatched: false,
      allow_do_block: false,
      allow_no_parens_many: false,
      allow_ternary_after_range: false,
      interpolation_depth: 0
    }
  end

  @doc "Create initial generation budget"
  @spec initial_budget(non_neg_integer(), non_neg_integer()) :: budget()
  def initial_budget(depth \\ 4, nodes_left \\ 100) do
    %{depth: depth, nodes_left: nodes_left}
  end

  @doc "Create initial generator state"
  @spec initial_state(non_neg_integer(), non_neg_integer()) :: state()
  def initial_state(depth \\ 4, nodes_left \\ 100) do
    %{
      budget: initial_budget(depth, nodes_left),
      context: phase1_context()
    }
  end

  @doc "Decrement depth in budget"
  @spec decr_depth(state()) :: state()
  def decr_depth(%{budget: budget} = state) do
    %{state | budget: %{budget | depth: max(0, budget.depth - 1)}}
  end

  @doc "Decrement nodes_left in budget"
  @spec decr_nodes(state(), non_neg_integer()) :: state()
  def decr_nodes(%{budget: budget} = state, n \\ 1) do
    %{state | budget: %{budget | nodes_left: max(0, budget.nodes_left - n)}}
  end

  @doc "Check if budget is exhausted (depth or nodes)"
  @spec budget_exhausted?(state()) :: boolean()
  def budget_exhausted?(%{budget: %{depth: depth, nodes_left: nodes_left}}) do
    depth <= 0 or nodes_left <= 0
  end
end
