defmodule Spitfire.Property.TokenGrammarGenerators do
  @moduledoc """
  StreamData generators for grammar trees.

  Generates grammar tree nodes that can be compiled to Toxic tokens
  using `TokenCompiler.to_tokens/2`.

  ## Current Phase Support

  - **Increment 1**: Literals (integers, floats, chars, atoms, bools, nil),
    identifiers, and aliases.
  - **Increment 2**: Binary and unary operators with newline handling.
  - **Increment 3**: Calls (call_parens, call_no_parens_one, capture_int).
  - **Increment 4**: fn_single with stab clauses.
  """

  use ExUnitProperties

  alias Spitfire.Property.GrammarTree

  # ===========================================================================
  # Atom/Identifier pools (same as existing generators)
  # ===========================================================================

  @identifiers ~w(foo bar baz qux spam eggs alpha beta gamma delta)a
  @aliases ~w(Foo Bar Baz Qux Remote Mod State Schema Context Config Default)a
  @atoms ~w(ok error foo bar baz one two three alice bob)a

  # Binary operators: {token_kind, operator_atom}
  # These are safe operators that don't require special context
  @binary_ops [
    # Arithmetic (dual_op)
    {:dual_op, :+},
    {:dual_op, :-},
    {:mult_op, :*},
    {:mult_op, :/},
    # Comparison (comp_op)
    {:comp_op, :==},
    {:comp_op, :!=},
    {:comp_op, :===},
    {:comp_op, :!==},
    # Relational (rel_op)
    {:rel_op, :<},
    {:rel_op, :>},
    {:rel_op, :<=},
    {:rel_op, :>=},
    # Boolean (and_op, or_op)
    {:and_op, :and},
    {:or_op, :or},
    # Pipe
    {:pipe_op, :|>}
  ]

  # Unary operators: {token_kind, operator_atom}
  @unary_ops [
    {:unary_op, :not},
    {:unary_op, :!},
    {:dual_op, :+},
    {:dual_op, :-}
  ]

  # Fallback literals when budget is exhausted
  @fallback_literals [nil, 0, :ok]

  def atom_pool, do: @atoms
  def identifier_pool, do: @identifiers
  def alias_pool, do: @aliases
  def binary_op_pool, do: @binary_ops
  def unary_op_pool, do: @unary_ops

  # ===========================================================================
  # Public API: grammar/1
  # ===========================================================================

  @doc """
  Generate a grammar tree.

  ## Options

  - `:phase` - Phase level (1-5), default 1
  - `:max_depth` - Maximum expression depth, default 4
  - `:max_nodes` - Maximum nodes in the tree, default 100
  - `:max_forms` - Maximum top-level expressions, default 3
  """
  @spec grammar(keyword()) :: StreamData.t(GrammarTree.t())
  def grammar(opts \\ []) do
    _phase = Keyword.get(opts, :phase, 1)
    max_depth = Keyword.get(opts, :max_depth, 4)
    max_nodes = Keyword.get(opts, :max_nodes, 100)
    max_forms = Keyword.get(opts, :max_forms, 3)

    state = GrammarTree.initial_state(max_depth, max_nodes)

    gen_forms(state, max_forms)
    |> StreamData.map(fn forms -> {:grammar, forms} end)
  end

  # ===========================================================================
  # Generator: forms (top-level expressions)
  # ===========================================================================

  defp gen_forms(state, max_forms) do
    StreamData.bind(StreamData.integer(1..max_forms), fn count ->
      gen_form_list(state, count)
    end)
  end

  defp gen_form_list(_state, 0), do: StreamData.constant([])

  defp gen_form_list(state, count) when count > 0 do
    StreamData.bind(gen_expr(state), fn form ->
      StreamData.bind(gen_form_list(GrammarTree.decr_nodes(state), count - 1), fn rest ->
        StreamData.constant([form | rest])
      end)
    end)
  end

  # ===========================================================================
  # Generator: expressions
  # ===========================================================================

  defp gen_expr(state) do
    if GrammarTree.budget_exhausted?(state) do
      gen_fallback_literal()
    else
      # Phase 1-2: literals, identifiers, operators, calls, fn_single, fn_multi, call_do
      StreamData.frequency([
        {5, gen_literal()},
        {3, gen_identifier()},
        {2, gen_alias()},
        {3, gen_binary_op(state)},
        {2, gen_unary_op(state)},
        {3, gen_call_parens(state)},
        {2, gen_call_no_parens_one(state)},
        {2, gen_capture_int()},
        {2, gen_fn_single(state)},
        {2, gen_fn_multi(state)},
        {2, gen_call_do(state)}
      ])
    end
  end

  # Generate a simple expression (no operators) for use as operands
  defp gen_simple_expr do
    StreamData.frequency([
      {5, gen_literal()},
      {3, gen_identifier()},
      {2, gen_alias()}
    ])
  end

  defp gen_fallback_literal do
    StreamData.member_of(@fallback_literals)
    |> StreamData.map(fn
      nil -> :nil_lit
      0 -> {:int, 0, :dec, ~c"0"}
      :ok -> {:atom_lit, :ok}
    end)
  end

  # ===========================================================================
  # Generator: literals
  # ===========================================================================

  defp gen_literal do
    StreamData.frequency([
      {4, gen_int()},
      {2, gen_float()},
      {1, gen_char()},
      {3, gen_atom_lit()},
      {2, gen_bool_lit()},
      {1, StreamData.constant(:nil_lit)}
    ])
  end

  defp gen_int do
    StreamData.frequency([
      {5, gen_int_dec()},
      {1, gen_int_hex()},
      {1, gen_int_bin()},
      {1, gen_int_oct()}
    ])
  end

  defp gen_int_dec do
    StreamData.integer(-1000..1000)
    |> StreamData.map(fn n ->
      chars = Integer.to_charlist(n)
      {:int, n, :dec, chars}
    end)
  end

  defp gen_int_hex do
    StreamData.integer(0..255)
    |> StreamData.map(fn n ->
      hex = Integer.to_string(n, 16)
      chars = String.to_charlist("0x" <> hex)
      {:int, n, :hex, chars}
    end)
  end

  defp gen_int_bin do
    StreamData.integer(0..15)
    |> StreamData.map(fn n ->
      bin = Integer.to_string(n, 2)
      chars = String.to_charlist("0b" <> bin)
      {:int, n, :bin, chars}
    end)
  end

  defp gen_int_oct do
    StreamData.integer(0..63)
    |> StreamData.map(fn n ->
      oct = Integer.to_string(n, 8)
      chars = String.to_charlist("0o" <> oct)
      {:int, n, :oct, chars}
    end)
  end

  defp gen_float do
    StreamData.bind(StreamData.integer(0..100), fn int_part ->
      StreamData.bind(StreamData.integer(0..99), fn frac_part ->
        value = int_part + frac_part / 100.0
        # Ensure consistent representation
        chars = :erlang.float_to_list(value, [{:decimals, 2}, :compact])
        StreamData.constant({:float, value, chars})
      end)
    end)
  end

  defp gen_char do
    StreamData.frequency([
      {5, gen_simple_char()},
      {1, gen_escape_char()}
    ])
  end

  defp gen_simple_char do
    StreamData.integer(?a..?z)
    |> StreamData.map(fn c ->
      chars = [??, c]
      {:char, c, chars}
    end)
  end

  defp gen_escape_char do
    StreamData.member_of([?\n, ?\t, ?\r, ?\\])
    |> StreamData.map(fn c ->
      escape =
        case c do
          ?\n -> ~c"?\\n"
          ?\t -> ~c"?\\t"
          ?\r -> ~c"?\\r"
          ?\\ -> ~c"?\\\\"
        end

      {:char, c, escape}
    end)
  end

  defp gen_atom_lit do
    StreamData.member_of(@atoms)
    |> StreamData.map(fn atom -> {:atom_lit, atom} end)
  end

  defp gen_bool_lit do
    StreamData.member_of([true, false])
    |> StreamData.map(fn b -> {:bool_lit, b} end)
  end

  # ===========================================================================
  # Generator: identifiers and aliases
  # ===========================================================================

  defp gen_identifier do
    StreamData.member_of(@identifiers)
    |> StreamData.map(fn atom -> {:identifier, atom} end)
  end

  defp gen_alias do
    StreamData.member_of(@aliases)
    |> StreamData.map(fn atom -> {:alias, atom} end)
  end

  # ===========================================================================
  # Generator: binary operators
  # ===========================================================================

  defp gen_binary_op(state) do
    # Decrement depth to prevent infinite recursion
    child_state = GrammarTree.decr_depth(state)

    # Generate operands (use simple exprs at low depth)
    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_simple_expr()
      else
        gen_expr(child_state)
      end

    StreamData.bind(operand_gen, fn left ->
      StreamData.bind(gen_op_eol(), fn op_eol ->
        StreamData.bind(operand_gen, fn right ->
          StreamData.constant({:binary_op, left, op_eol, right})
        end)
      end)
    end)
  end

  # Generate op_eol: {op_kind, op} with optional newlines
  defp gen_op_eol do
    StreamData.bind(StreamData.member_of(@binary_ops), fn {op_kind, op} ->
      # Most of the time no newline, occasionally 1 newline
      StreamData.bind(gen_newlines(), fn newlines ->
        StreamData.constant({:op_eol, {op_kind, op}, newlines})
      end)
    end)
  end

  # Generate newline count (0 most of the time, occasionally 1)
  defp gen_newlines do
    StreamData.frequency([
      {8, StreamData.constant(0)},
      {2, StreamData.constant(1)}
    ])
  end

  # ===========================================================================
  # Generator: unary operators
  # ===========================================================================

  defp gen_unary_op(state) do
    # Decrement depth to prevent infinite recursion
    child_state = GrammarTree.decr_depth(state)

    # Generate operand (use simple exprs at low depth)
    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_simple_expr()
      else
        gen_expr(child_state)
      end

    StreamData.bind(StreamData.member_of(@unary_ops), fn {op_kind, op} ->
      StreamData.bind(operand_gen, fn operand ->
        StreamData.constant({:unary_op, {op_kind, op}, operand})
      end)
    end)
  end

  # ===========================================================================
  # Generator: calls
  # ===========================================================================

  # Generate a call with parentheses: foo(a, b) or expr.(a)
  defp gen_call_parens(state) do
    child_state = GrammarTree.decr_depth(state)

    # Generate target - either a paren_identifier or a dot_call
    target_gen =
      StreamData.frequency([
        {4, gen_paren_identifier()},
        {1, gen_dot_call_target(child_state)}
      ])

    # Generate arguments (0-3 arguments)
    args_gen = gen_args(child_state, 3)

    StreamData.bind(target_gen, fn target ->
      StreamData.bind(args_gen, fn args ->
        StreamData.constant({:call_parens, target, args})
      end)
    end)
  end

  # Generate a no-parens call with one argument: foo bar
  defp gen_call_no_parens_one(_state) do
    # Generate simple arg (no operators to avoid ambiguity)
    arg_gen = gen_simple_expr()

    StreamData.bind(StreamData.member_of(@identifiers), fn name ->
      StreamData.bind(arg_gen, fn arg ->
        StreamData.constant({:call_no_parens_one, {:identifier, name}, arg})
      end)
    end)
  end

  # Generate a capture integer: &1, &10
  defp gen_capture_int do
    StreamData.integer(1..10)
    |> StreamData.map(fn n -> {:capture_int, n} end)
  end

  # Generate a paren_identifier: foo
  defp gen_paren_identifier do
    StreamData.member_of(@identifiers)
    |> StreamData.map(fn atom -> {:paren_identifier, atom} end)
  end

  # Generate a dot_call target: expr.
  defp gen_dot_call_target(_state) do
    # Use simple expression for the target to avoid deep nesting
    gen_simple_expr()
    |> StreamData.map(fn expr -> {:dot_call, expr} end)
  end

  # Generate argument list (0 to max_args)
  defp gen_args(state, max_args) do
    StreamData.bind(StreamData.integer(0..max_args), fn count ->
      gen_arg_list(state, count)
    end)
  end

  defp gen_arg_list(_state, 0), do: StreamData.constant([])

  defp gen_arg_list(state, count) when count > 0 do
    arg_gen =
      if state.budget.depth <= 1 do
        gen_simple_expr()
      else
        gen_expr(state)
      end

    StreamData.bind(arg_gen, fn arg ->
      StreamData.bind(gen_arg_list(GrammarTree.decr_nodes(state), count - 1), fn rest ->
        StreamData.constant([arg | rest])
      end)
    end)
  end

  # ===========================================================================
  # Generator: fn_single
  # ===========================================================================

  # Generate a single-clause fn expression: fn pattern -> body end
  defp gen_fn_single(state) do
    child_state = GrammarTree.decr_depth(state)

    StreamData.bind(gen_stab_clause(child_state), fn clause ->
      StreamData.constant({:fn_single, [clause]})
    end)
  end

  # Generate a multi-clause fn expression: fn clause1; clause2; ... end
  defp gen_fn_multi(state) do
    child_state = GrammarTree.decr_depth(state)

    # Generate 2-4 clauses
    StreamData.bind(StreamData.integer(2..4), fn count ->
      gen_stab_clause_list(child_state, count)
    end)
    |> StreamData.map(fn clauses -> {:fn_multi, clauses} end)
  end

  # Generate a list of stab clauses for fn_multi
  defp gen_stab_clause_list(_state, 0), do: StreamData.constant([])

  defp gen_stab_clause_list(state, count) when count > 0 do
    StreamData.bind(gen_stab_clause_varied(state), fn clause ->
      StreamData.bind(gen_stab_clause_list(state, count - 1), fn rest ->
        StreamData.constant([clause | rest])
      end)
    end)
  end

  # Generate a stab clause with varied patterns (literals, identifiers, atoms)
  # for better pattern matching diversity in fn_multi
  defp gen_stab_clause_varied(state) do
    # Generate pattern - use varied patterns for multi-clause fns
    pattern_gen =
      StreamData.frequency([
        {3, gen_single_pattern()},
        {2, gen_single_literal_pattern()},
        {1, gen_single_atom_pattern()}
      ])

    # No guards for simplicity in multi-clause (guards added separately)
    guard_gen = StreamData.constant(nil)

    # Generate simple body
    body_gen = gen_simple_expr()

    StreamData.bind(pattern_gen, fn pattern ->
      StreamData.bind(guard_gen, fn guard ->
        StreamData.bind(body_gen, fn body ->
          StreamData.constant({:stab_clause, pattern, guard, body})
        end)
      end)
    end)
  end

  # Generate a single literal pattern for fn clauses: {:single, literal}
  defp gen_single_literal_pattern do
    StreamData.frequency([
      {3, StreamData.integer(0..10) |> StreamData.map(fn n -> {:single, {:int, n, :dec, Integer.to_charlist(n)}} end)},
      {2, StreamData.member_of(@atoms) |> StreamData.map(fn a -> {:single, {:atom_lit, a}} end)}
    ])
  end

  # Generate a single atom pattern: {:single, {:atom_lit, atom}}
  defp gen_single_atom_pattern do
    StreamData.member_of(@atoms)
    |> StreamData.map(fn atom -> {:single, {:atom_lit, atom}} end)
  end

  # ===========================================================================
  # Generator: call_do (if/unless/case with do blocks)
  # ===========================================================================

  @do_identifiers ~w(if unless)a

  # Generate a call with do block: if cond do body end
  defp gen_call_do(state) do
    child_state = GrammarTree.decr_depth(state)

    StreamData.frequency([
      {4, gen_if_unless(child_state)},
      {2, gen_case(child_state)}
    ])
  end

  # Generate if/unless with do block
  defp gen_if_unless(state) do
    StreamData.bind(StreamData.member_of(@do_identifiers), fn name ->
      StreamData.bind(gen_do_condition(), fn cond_expr ->
        StreamData.bind(gen_do_block(state), fn do_block ->
          StreamData.constant({:call_do, {:identifier, name}, [cond_expr], do_block})
        end)
      end)
    end)
  end

  # Generate case expression with stab clauses
  defp gen_case(state) do
    StreamData.bind(gen_simple_expr(), fn match_expr ->
      StreamData.bind(gen_case_block(state), fn do_block ->
        StreamData.constant({:call_do, {:identifier, :case}, [match_expr], do_block})
      end)
    end)
  end

  # Generate case block with stab clauses
  defp gen_case_block(_state) do
    # Generate 2-3 stab clauses for case
    StreamData.bind(StreamData.integer(2..3), fn count ->
      gen_case_clause_list(count)
    end)
    |> StreamData.map(fn clauses -> {:do_block, clauses, []} end)
  end

  # Generate a list of case clauses
  defp gen_case_clause_list(0), do: StreamData.constant([])

  defp gen_case_clause_list(count) when count > 0 do
    StreamData.bind(gen_case_clause(), fn clause ->
      StreamData.bind(gen_case_clause_list(count - 1), fn rest ->
        StreamData.constant([clause | rest])
      end)
    end)
  end

  # Generate a single case clause (stab clause with pattern)
  defp gen_case_clause do
    pattern_gen =
      StreamData.frequency([
        {3, StreamData.member_of(@atoms) |> StreamData.map(fn a -> {:single, {:atom_lit, a}} end)},
        {2, StreamData.member_of(@identifiers) |> StreamData.map(fn i -> {:single, {:identifier, i}} end)},
        {1, StreamData.constant({:single, {:identifier, :_}})}
      ])

    body_gen = gen_simple_expr()

    StreamData.bind(pattern_gen, fn pattern ->
      StreamData.bind(body_gen, fn body ->
        StreamData.constant({:stab_clause, pattern, nil, body})
      end)
    end)
  end

  # Generate condition for if/unless (simple expressions)
  defp gen_do_condition do
    StreamData.frequency([
      {3, StreamData.member_of([true, false]) |> StreamData.map(&{:bool_lit, &1})},
      {2, StreamData.member_of(@identifiers) |> StreamData.map(&{:identifier, &1})}
    ])
  end

  # Generate do block: {:do_block, body, extras}
  defp gen_do_block(state) do
    body_gen = gen_do_body(state)
    extras_gen = gen_block_extras()

    StreamData.bind(body_gen, fn body ->
      StreamData.bind(extras_gen, fn extras ->
        StreamData.constant({:do_block, body, extras})
      end)
    end)
  end

  # Generate body for do block (1-2 simple expressions)
  defp gen_do_body(_state) do
    StreamData.bind(StreamData.integer(1..2), fn count ->
      gen_simple_expr_list(count)
    end)
  end

  # Generate a list of simple expressions
  defp gen_simple_expr_list(0), do: StreamData.constant([])

  defp gen_simple_expr_list(count) when count > 0 do
    StreamData.bind(gen_simple_expr(), fn expr ->
      StreamData.bind(gen_simple_expr_list(count - 1), fn rest ->
        StreamData.constant([expr | rest])
      end)
    end)
  end

  # Generate block extras (empty or else)
  defp gen_block_extras do
    StreamData.frequency([
      {6, StreamData.constant([])},
      {4, gen_else_block()}
    ])
  end

  # Generate else block: [{:block_item, :else, body}]
  defp gen_else_block do
    StreamData.bind(StreamData.integer(1..1), fn count ->
      gen_simple_expr_list(count)
    end)
    |> StreamData.map(fn body -> [{:block_item, :else, body}] end)
  end

  # Generate a stab clause: pattern -> body (or pattern when guard -> body)
  # Phase 2: optionally generates guards and multiple patterns
  defp gen_stab_clause(state) do
    # Generate pattern (:empty, {:single, expr}, or {:many, [expr]})
    pattern_gen = gen_pattern()

    # Generate guard (nil most of the time, occasionally a guard expression)
    guard_gen = gen_optional_guard(state)

    # Generate body (simple expression to avoid deep nesting)
    body_gen =
      if state.budget.depth <= 1 do
        gen_simple_expr()
      else
        gen_expr(state)
      end

    StreamData.bind(pattern_gen, fn pattern ->
      StreamData.bind(guard_gen, fn guard ->
        StreamData.bind(body_gen, fn body ->
          StreamData.constant({:stab_clause, pattern, guard, body})
        end)
      end)
    end)
  end

  # ===========================================================================
  # Generator: patterns (Phase 2)
  # ===========================================================================

  # Generate a pattern: :empty, {:single, expr}, or {:many, [expr]}
  defp gen_pattern do
    StreamData.frequency([
      {2, StreamData.constant(:empty)},
      {4, gen_single_pattern()},
      {3, gen_many_pattern()}
    ])
  end

  # Generate a single pattern for fn: {:single, expr}
  defp gen_single_pattern do
    # Use identifiers for patterns (most common)
    StreamData.member_of(@identifiers)
    |> StreamData.map(fn atom -> {:single, {:identifier, atom}} end)
  end

  # Generate multiple patterns: {:many, [expr1, expr2, ...]}
  defp gen_many_pattern do
    # Generate 2-4 pattern expressions (identifiers only for simplicity)
    StreamData.bind(StreamData.integer(2..4), fn count ->
      gen_pattern_identifier_list(count)
    end)
    |> StreamData.map(fn exprs -> {:many, exprs} end)
  end

  # Generate a list of unique identifiers for patterns
  defp gen_pattern_identifier_list(count) do
    # Pick `count` distinct identifiers to avoid duplicate patterns
    StreamData.uniq_list_of(
      StreamData.member_of(@identifiers),
      length: count
    )
    |> StreamData.map(fn atoms ->
      Enum.map(atoms, fn atom -> {:identifier, atom} end)
    end)
  end

  # ===========================================================================
  # Generator: guards (Phase 2)
  # ===========================================================================

  # Generate optional guard (nil most of the time)
  defp gen_optional_guard(state) do
    StreamData.frequency([
      {7, StreamData.constant(nil)},
      {3, gen_guard(state)}
    ])
  end

  # Generate a guard expression
  # Guards are restricted: comparisons, type checks, boolean ops
  defp gen_guard(_state) do
    StreamData.frequency([
      {4, gen_guard_comparison()},
      {3, gen_guard_type_check()},
      {2, gen_guard_boolean()}
    ])
  end

  # Generate comparison guard: x > 0, x == :ok, etc.
  defp gen_guard_comparison do
    comp_ops = [{:rel_op, :>}, {:rel_op, :<}, {:rel_op, :>=}, {:rel_op, :<=}, {:comp_op, :==}]

    StreamData.bind(StreamData.member_of(@identifiers), fn var ->
      StreamData.bind(StreamData.member_of(comp_ops), fn {op_kind, op} ->
        StreamData.bind(gen_simple_literal_value(), fn rhs ->
          guard = {:binary_op, {:identifier, var}, {:op_eol, {op_kind, op}, 0}, rhs}
          StreamData.constant(guard)
        end)
      end)
    end)
  end

  # Generate type check guard: is_integer(x), is_atom(x), etc.
  @type_checks ~w(is_integer is_atom is_binary is_list is_map is_nil is_boolean)a

  defp gen_guard_type_check do
    StreamData.bind(StreamData.member_of(@type_checks), fn check ->
      StreamData.bind(StreamData.member_of(@identifiers), fn var ->
        guard = {:call_parens, {:paren_identifier, check}, [{:identifier, var}]}
        StreamData.constant(guard)
      end)
    end)
  end

  # Generate simple boolean guard: x and true, not x
  defp gen_guard_boolean do
    StreamData.bind(StreamData.member_of(@identifiers), fn var ->
      StreamData.frequency([
        {2,
         StreamData.constant(
           {:binary_op, {:identifier, var}, {:op_eol, {:and_op, :and}, 0}, {:bool_lit, true}}
         )},
        {1, StreamData.constant({:unary_op, {:unary_op, :not}, {:identifier, var}})}
      ])
    end)
  end

  # Generate a simple literal value for guard RHS
  defp gen_simple_literal_value do
    StreamData.frequency([
      {3, StreamData.integer(0..100) |> StreamData.map(fn n -> {:int, n, :dec, Integer.to_charlist(n)} end)},
      {2, StreamData.member_of(@atoms) |> StreamData.map(fn a -> {:atom_lit, a} end)},
      {1, StreamData.constant({:bool_lit, true})},
      {1, StreamData.constant({:bool_lit, false})}
    ])
  end
end
