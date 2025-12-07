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
  # Per elixir_parser.yrl matched_op_expr rules (lines 187-204)
  @binary_ops [
    # match_op (=)
    {:match_op, :=},
    # Arithmetic (dual_op)
    {:dual_op, :+},
    {:dual_op, :-},
    {:mult_op, :*},
    {:mult_op, :/},
    # power_op (**)
    {:power_op, :**},
    # concat_op (++, --, <>, +++, ---)
    {:concat_op, :++},
    {:concat_op, :--},
    {:concat_op, :<>},
    {:concat_op, :+++},
    {:concat_op, :---},
    # range_op (..) as binary
    {:range_op, :..},
    # Note: ternary_op (//) omitted - only valid immediately after .. (e.g., 1..10//2)
    # xor_op (^^^)
    {:xor_op, :"^^^"},
    # Comparison (comp_op)
    {:comp_op, :==},
    {:comp_op, :!=},
    {:comp_op, :===},
    {:comp_op, :!==},
    {:comp_op, :=~},
    # Relational (rel_op)
    {:rel_op, :<},
    {:rel_op, :>},
    {:rel_op, :<=},
    {:rel_op, :>=},
    # Boolean (and_op, or_op)
    {:and_op, :and},
    {:and_op, :&&},
    {:and_op, :&&&},
    {:or_op, :or},
    {:or_op, :||},
    {:or_op, :|||},
    # in_op (in)
    {:in_op, :in},
    # in_match_op (<-, \\)
    {:in_match_op, :<-},
    {:in_match_op, :\\},
    # type_op (::)
    {:type_op, :"::"},
    # when_op (when)
    {:when_op, :when},
    # arrow_op (<<<, >>>, <~, ~>, <<~, ~>>, <~>, <|>)
    {:arrow_op, :<<<},
    {:arrow_op, :>>>},
    {:arrow_op, :<~},
    {:arrow_op, :~>},
    {:arrow_op, :<<~},
    {:arrow_op, :~>>},
    {:arrow_op, :<~>},
    {:arrow_op, :"<|>"},
    # pipe_op (|>, |)
    {:pipe_op, :|>},
    {:pipe_op, :|}
  ]

  # Unary operators: {token_kind, operator_atom}
  # Per elixir_parser.yrl unary_op_eol rules (lines 402-407)
  # and Code.Identifier.unary_op (line 21): :!, :^, :not, :+, :-, :~~~
  # Note: ternary_op (//) omitted - semantically only valid after .. (e.g., 1..10//2)
  @unary_ops [
    {:unary_op, :not},
    {:unary_op, :!},
    {:unary_op, :^},
    {:unary_op, :"~~~"},
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
  Generate a grammar tree using category-aware generators.

  Models all grammar variants per elixir_parser.yrl:
  - `grammar -> expr_list` (no leading/trailing eoe)
  - `grammar -> expr_list eoe` (trailing eoe)
  - `grammar -> eoe expr_list` (leading eoe)
  - `grammar -> eoe expr_list eoe` (both)
  - `grammar -> eoe` (just eoe, empty program)
  - `grammar -> '$empty'` (completely empty)

  Uses `{:grammar_v2, leading_eoe, [{expr, eoe|nil}], trailing_eoe}` format.

  ## Options

  - `:phase` - Phase level (1-5), default 1
  - `:max_depth` - Maximum expression depth, default 4
  - `:max_nodes` - Maximum nodes in the tree, default 100
  - `:max_forms` - Maximum top-level expressions, default 3
  """
  @spec grammar(keyword()) :: StreamData.t(GrammarTree.t())
  def grammar(opts \\ []) do
    phase = Keyword.get(opts, :phase, 1)
    max_depth = Keyword.get(opts, :max_depth, 4)
    max_nodes = Keyword.get(opts, :max_nodes, 100)
    max_forms = Keyword.get(opts, :max_forms, 3)

    # Set allow_unmatched: true for top-level context
    context = %{GrammarTree.phase1_context() | allow_unmatched: true, phase: phase}
    state = %{budget: GrammarTree.initial_budget(max_depth, max_nodes), context: context}

    # Generate all grammar variants with appropriate frequencies
    StreamData.frequency([
      # grammar -> expr_list (most common)
      {5, gen_grammar_expr_list(state, max_forms)},
      # grammar -> expr_list eoe (trailing newline - common)
      {3, gen_grammar_expr_list_eoe(state, max_forms)},
      # grammar -> eoe expr_list (leading newline - less common)
      {1, gen_grammar_eoe_expr_list(state, max_forms)},
      # grammar -> eoe expr_list eoe (both - rare)
      {1, gen_grammar_eoe_expr_list_eoe(state, max_forms)}
      # Note: grammar -> eoe and grammar -> '$empty' omitted (edge cases)
    ])
  end

  # grammar -> expr_list : build_block(reverse('$1')).
  defp gen_grammar_expr_list(state, max_forms) do
    StreamData.bind(StreamData.integer(1..max_forms), fn count ->
      gen_expr_list(state, count)
    end)
    |> StreamData.map(fn exprs -> {:grammar_v2, nil, exprs, nil} end)
  end

  # grammar -> expr_list eoe : build_block(reverse(annotate_eoe('$2', '$1'))).
  defp gen_grammar_expr_list_eoe(state, max_forms) do
    StreamData.bind(StreamData.integer(1..max_forms), fn count ->
      StreamData.bind(gen_expr_list(state, count), fn exprs ->
        StreamData.bind(gen_eoe(), fn trailing_eoe ->
          StreamData.constant({:grammar_v2, nil, exprs, trailing_eoe})
        end)
      end)
    end)
  end

  # grammar -> eoe expr_list : build_block(reverse('$2')).
  defp gen_grammar_eoe_expr_list(state, max_forms) do
    StreamData.bind(gen_eoe(), fn leading_eoe ->
      StreamData.bind(StreamData.integer(1..max_forms), fn count ->
        gen_expr_list(state, count)
      end)
      |> StreamData.map(fn exprs -> {:grammar_v2, leading_eoe, exprs, nil} end)
    end)
  end

  # grammar -> eoe expr_list eoe : build_block(reverse(annotate_eoe('$3', '$2'))).
  defp gen_grammar_eoe_expr_list_eoe(state, max_forms) do
    StreamData.bind(gen_eoe(), fn leading_eoe ->
      StreamData.bind(StreamData.integer(1..max_forms), fn count ->
        StreamData.bind(gen_expr_list(state, count), fn exprs ->
          StreamData.bind(gen_eoe(), fn trailing_eoe ->
            StreamData.constant({:grammar_v2, leading_eoe, exprs, trailing_eoe})
          end)
        end)
      end)
    end)
  end

  @doc """
  Generate a grammar tree using legacy format.

  Uses `{:grammar, [expr]}` format for backward compatibility with existing tests.
  Does not use category-aware generators.
  """
  @spec grammar_legacy(keyword()) :: StreamData.t(GrammarTree.t())
  def grammar_legacy(opts \\ []) do
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
  # Generator: expr_list (expressions with eoe markers)
  # ===========================================================================

  # Per grammar rules:
  #   expr_list -> expr : ['$1'].
  #   expr_list -> expr_list eoe expr : ['$3' | annotate_eoe('$2', '$1')].
  #
  # The eoe goes BETWEEN expressions, not after the last one.
  # Returns list of {expr, eoe | nil} tuples where last has nil.

  defp gen_expr_list(_state, count) when count <= 0 do
    StreamData.constant([])
  end

  defp gen_expr_list(state, 1) do
    # Single expression, NO eoe (per: expr_list -> expr)
    StreamData.bind(gen_expr(state), fn expr ->
      StreamData.constant([{expr, nil}])
    end)
  end

  defp gen_expr_list(state, count) when count > 1 do
    # First expr has eoe after it (between this and next)
    StreamData.bind(gen_expr(state), fn expr ->
      StreamData.bind(gen_eoe(), fn eoe ->
        StreamData.bind(gen_expr_list(GrammarTree.decr_nodes(state), count - 1), fn rest ->
          StreamData.constant([{expr, eoe} | rest])
        end)
      end)
    end)
  end

  # ===========================================================================
  # Generator: expressions
  # ===========================================================================

  # Generate expression based on context.
  # Per grammar rule: expr -> matched_expr | no_parens_expr | unmatched_expr
  defp gen_expr(state) do
    if GrammarTree.budget_exhausted?(state) do
      # Literal is a matched_expr
      gen_fallback_literal()
    else
      if state.context.allow_unmatched do
        # Top-level context: can generate any expression type
        StreamData.frequency([
          {6, gen_matched_expr(state)},
          {3, gen_unmatched_expr(state)}
          # no_parens_expr deferred to Phase 3+
        ])
      else
        # Restricted context (e.g., operand position): only matched
        gen_matched_expr(state)
      end
    end
  end

  # Legacy gen_expr for backward compatibility (used by gen_fn_single, etc.)
  defp gen_expr_legacy(state) do
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

  # ===========================================================================
  # Generator: eoe (end-of-expression)
  # ===========================================================================

  @doc """
  Generate end-of-expression marker.

  Per grammar rules 331-333:
  - `:eol` - newline only
  - `:semi` - semicolon only
  - `:eol_semi` - newline followed by semicolon
  """
  def gen_eoe do
    StreamData.frequency([
      {7, StreamData.constant(:eol)},
      {2, StreamData.constant(:semi)},
      {1, StreamData.constant(:eol_semi)}
    ])
  end

  # ===========================================================================
  # Category-Aware Generators (per grammar alignment)
  # ===========================================================================

  @doc """
  Generate a matched expression (safe as operands).

  Per grammar lines 155-161, matched expressions include:
  - matched_expr matched_op_expr (binary ops)
  - unary_op_eol matched_expr (unary ops)
  - at_op_eol matched_expr (@foo)
  - capture_op_eol matched_expr (&expr)
  - ellipsis_op matched_expr (...expr)
  - no_parens_one_expr
  - sub_matched_expr
  """
  def gen_matched_expr(state) do
    if GrammarTree.budget_exhausted?(state) do
      gen_sub_matched_expr(state)
    else
      StreamData.frequency([
        {4, gen_sub_matched_expr(state)},
        {3, gen_matched_op(state)},
        {2, gen_matched_unary(state)},
        {1, gen_at_op(state)},
        {1, gen_capture_op(state)},
        {1, gen_ellipsis_prefix(state)},
        {1, gen_call_no_parens_one(state)}
      ])
    end
  end

  @doc """
  Generate an unmatched expression (has trailing do block).

  Per grammar lines 163-171, unmatched expressions include:
  - call_do (if, unless, case, try, etc.)
  - unmatched_op (binary op with unmatched right operand)
  """
  def gen_unmatched_expr(state) do
    if GrammarTree.budget_exhausted?(state) do
      # Fallback to simple call_do when budget exhausted
      gen_simple_call_do(state)
    else
      StreamData.frequency([
        {5, gen_call_do(state)},
        {3, gen_unmatched_op(state)}
      ])
    end
  end

  @doc """
  Generate a sub-matched expression (atomic/access expressions).

  Per grammar lines 263-267, includes:
  - access_expr (literals, identifiers, fn, calls, etc.)
  - Nullary range_op (..)
  - Nullary ellipsis_op (...)
  """
  def gen_sub_matched_expr(state) do
    StreamData.frequency([
      {10, gen_access_expr(state)},
      {1, gen_nullary_range()},
      {1, gen_nullary_ellipsis()}
    ])
  end

  @doc """
  Generate an access expression (leaf nodes).

  Per grammar lines 273-301, includes:
  - Literals (int, float, char, atom, bool, nil)
  - Identifiers and aliases
  - fn expressions
  - Parenthesized calls
  - Captures
  - Parenthesized expressions
  """
  def gen_access_expr(state) do
    if GrammarTree.budget_exhausted?(state) do
      gen_fallback_literal()
    else
      StreamData.frequency([
        {5, gen_literal()},
        {3, gen_identifier()},
        {2, gen_alias()},
        {2, gen_fn_single(state)},
        {2, gen_call_parens(state)},
        {1, gen_capture_int()},
        {1, gen_paren_expr(state)}
      ])
    end
  end

  # ===========================================================================
  # Category-Aware: Matched Operators
  # ===========================================================================

  # Generate matched binary operator: left op right (both matched)
  # Per grammar: matched_expr -> matched_expr matched_op_expr
  defp gen_matched_op(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    StreamData.bind(operand_gen, fn left ->
      StreamData.bind(gen_op_eol(), fn op_eol ->
        StreamData.bind(operand_gen, fn right ->
          StreamData.constant({:matched_op, left, op_eol, right})
        end)
      end)
    end)
  end

  # Generate matched unary operator: op operand (operand matched)
  # Per grammar: matched_expr -> unary_op_eol matched_expr
  # unary_op_eol -> unary_op | unary_op eol
  defp gen_matched_unary(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    StreamData.bind(StreamData.member_of(@unary_ops), fn {op_kind, op} ->
      StreamData.bind(gen_newlines(), fn newlines ->
        StreamData.bind(operand_gen, fn operand ->
          StreamData.constant({:matched_unary, {op_kind, op}, newlines, operand})
        end)
      end)
    end)
  end

  # Generate at_op expression: @foo, @spec, etc.
  # Per grammar: matched_expr -> at_op_eol matched_expr
  # at_op_eol -> at_op | at_op eol
  defp gen_at_op(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    StreamData.bind(gen_newlines(), fn newlines ->
      StreamData.bind(operand_gen, fn operand ->
        StreamData.constant({:at_op, newlines, operand})
      end)
    end)
  end

  # Generate capture_op expression: &expr, &Mod.fun/1, &(&1 + &2)
  # Per grammar: matched_expr -> capture_op_eol matched_expr
  # capture_op_eol -> capture_op | capture_op eol
  defp gen_capture_op(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    StreamData.bind(gen_newlines(), fn newlines ->
      StreamData.bind(operand_gen, fn operand ->
        StreamData.constant({:capture_op, newlines, operand})
      end)
    end)
  end

  # Generate ellipsis as prefix operator: ...expr
  # Per grammar: matched_expr -> ellipsis_op matched_expr
  defp gen_ellipsis_prefix(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    operand_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    StreamData.bind(operand_gen, fn operand ->
      StreamData.constant({:ellipsis_prefix, operand})
    end)
  end

  # ===========================================================================
  # Category-Aware: Unmatched Operators
  # ===========================================================================

  # Generate unmatched binary operator: left op right (right is unmatched)
  # Per grammar: unmatched_expr -> matched_expr unmatched_op_expr
  defp gen_unmatched_op(state) do
    child_state = GrammarTree.decr_depth(state)
    restricted_state = restrict_unmatched(child_state)

    left_gen =
      if child_state.budget.depth <= 1 do
        gen_sub_matched_expr(restricted_state)
      else
        gen_matched_expr(restricted_state)
      end

    right_gen =
      if child_state.budget.depth <= 1 do
        gen_simple_call_do(child_state)
      else
        gen_unmatched_expr(child_state)
      end

    StreamData.bind(left_gen, fn left ->
      StreamData.bind(gen_op_eol(), fn op_eol ->
        StreamData.bind(right_gen, fn right ->
          StreamData.constant({:unmatched_op, left, op_eol, right})
        end)
      end)
    end)
  end

  # Generate a simple call_do when depth is limited
  defp gen_simple_call_do(_state) do
    StreamData.bind(gen_do_condition(), fn cond ->
      body = [{:atom_lit, :ok}]
      do_block = {:do_block, body, []}
      StreamData.constant({:call_do, {:identifier, :if}, [cond], do_block})
    end)
  end

  # ===========================================================================
  # Category-Aware: Nullary Operators
  # ===========================================================================

  @doc "Generate nullary range operator (..)"
  def gen_nullary_range do
    StreamData.constant({:nullary_range, nil})
  end

  @doc "Generate nullary ellipsis operator (...)"
  def gen_nullary_ellipsis do
    StreamData.constant({:nullary_ellipsis, nil})
  end

  # ===========================================================================
  # Category-Aware: Parenthesized Expressions
  # ===========================================================================

  # Generate parenthesized expression: (expr)
  defp gen_paren_expr(state) do
    child_state = GrammarTree.decr_depth(state)

    expr_gen =
      if child_state.budget.depth <= 1 do
        gen_simple_expr()
      else
        gen_matched_expr(child_state)
      end

    StreamData.map(expr_gen, fn expr -> {:paren_expr, expr} end)
  end

  @doc "Generate empty parentheses: ()"
  def gen_empty_paren do
    StreamData.constant({:empty_paren, nil})
  end

  # ===========================================================================
  # Context Helpers
  # ===========================================================================

  # Restrict context to disallow unmatched expressions
  defp restrict_unmatched(state) do
    %{state | context: %{state.context | allow_unmatched: false}}
  end
end
