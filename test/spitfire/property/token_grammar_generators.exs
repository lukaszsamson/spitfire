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
      # Increment 1-3: literals, identifiers, operators, and calls
      StreamData.frequency([
        {5, gen_literal()},
        {3, gen_identifier()},
        {2, gen_alias()},
        {3, gen_binary_op(state)},
        {2, gen_unary_op(state)},
        {3, gen_call_parens(state)},
        {2, gen_call_no_parens_one(state)},
        {2, gen_capture_int()}
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
end
