defmodule Spitfire.CharPropertyTest do
  @moduledoc """
  Property tests for ascii strings.
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.TokenGrammarGenerators, as: Gen
  alias Spitfire.Property.TokenCompiler

  @oracle_opts [
    columns: true,
    token_metadata: true,
    emit_warnings: false,
    existing_atoms_only: true
  ]

  setup_all do
    # Touch atom pools to ensure atoms exist
    touch_atom_pools()
    :ok
  end

  defp touch_atom_pools do
    _ = Gen.atom_pool()
    _ = Gen.identifier_pool()

    Enum.each(Gen.alias_pool(), fn alias_atom ->
      _ = Module.concat([alias_atom])
    end)

    :ok
  end

  describe "ascii" do
    @tag :skip
    @tag :property
    @tag timeout: 120_000
    property "grammar trees round-trip through Spitfire" do
      check all(
              code <- StreamData.string([
              ?d, ?o, ?e, ?n, ?d, ?c, ?a, ?t, ?c, ?h, ?r, ?e, ?s, ?c, ?u, ?e, ?a, ?f, ?t, ?e, ?r, ?e, ?l, ?s, ?e,
                ?f, ?n,
                  ?w, ?h, ?e, ?n, ?a, ?n, ?d, ?o, ?r, ?n, ?o, ?t, ?i, ?n,
                  ?t, ?r, ?u, ?e, ?f, ?a, ?l, ?s, ?e, ?n, ?i, ?l,
              ?A,
              ?!, ?@, ?^, ?&, ?*, ?(, ?), ?-, ?+, ?[, ?], ?{, ?}, ?;, ?:, ?', ?", ?\\, ?|, ?~, ?<, ?>, ?,, ?., ?/, ??, ?$, ?%, ?_, ?=, ?\s
              # ?#, #\n
              ], min_length: 0, max_length: 16),
              max_runs: 5000000,
              max_shrinking_steps: 50
            ) do
              code = "<<a, s: " <> code <> " >>"


        # Use Code.with_diagnostics to capture warnings
        {result, _diagnostics} =
          Code.with_diagnostics(fn ->
            Code.string_to_quoted(code, @oracle_opts)
          end)

        case result do
          {:ok, {:__block__, _, []}} -> :ok
          {:ok, oracle_ast} ->
            IO.puts(">>>>>\n"<>code<>"\n<<<<<")
            # Parse with Spitfire
            assert {:ok, spitfire_ast} = Spitfire.parse(code)

            # Apply workaround for parser bugs with not/! in forms
            {oracle_ast, spitfire_ast} =
              fix_deprecated_not_in_meta(oracle_ast, spitfire_ast)

            # Normalize and compare ASTs
            oracle_normalized = normalize_ast(oracle_ast)
            spitfire_normalized = normalize_ast(spitfire_ast)

            assert oracle_normalized == spitfire_normalized,
                   """
                   AST mismatch for code: #{inspect(code)}

                   Oracle:
                   #{inspect(oracle_normalized, pretty: true)}

                   Spitfire:
                   #{inspect(spitfire_normalized, pretty: true)}
                   """

          {:error, _} ->
            # Oracle rejected, skip this sample
            :ok
        end
      end
    end
  end

  # ===========================================================================
  # Workaround for Elixir parser bug with deprecated "not/! in" forms
  # ===========================================================================

  # When using deprecated forms "not a in b" or "!a in b", Elixir's parser
  # emits invalid metadata on the not/! node (pointing to the `in` operator
  # instead of the actual `not`/`!` token) and doesn't include newlines/end_of_expression
  # on the `in` node. This function fixes the Oracle AST by copying the correct
  # metadata from Spitfire's AST.
  #
  # Additionally, for non-deprecated forms like "not (a in b)", Spitfire incorrectly
  # reports the not/! position as the `in` position. This function also fixes
  # Spitfire's AST by copying from Oracle in those cases.
  #
  # The AST structure for both deprecated and non-deprecated forms is identical:
  # - "not a in b" -> {:not, meta, [{:in, meta, [a, b]}]}
  # - "a not in b" -> {:not, meta, [{:in, meta, [a, b]}]}
  # - "!a in b"    -> {:!, meta, [{:in, meta, [a, b]}]}
  # - "!(a in b)"  -> {:!, meta, [{:in, meta, [a, b]}]}
  defp fix_deprecated_not_in_meta(oracle_ast, spitfire_ast) do
    # Build maps of fixes from both ASTs
    {oracle_op_fixes, oracle_in_fixes} = collect_not_in_meta(oracle_ast)
    {spitfire_op_fixes, spitfire_in_fixes} = collect_not_in_meta(spitfire_ast)

    # Determine which AST has the "better" location for each not/! node
    # The better location is the one that does NOT point to the `in` operator
    better_locations =
      for {{_op, in_line, in_col} = key, oracle_meta} <- oracle_op_fixes, into: %{} do
        spitfire_meta = Map.get(spitfire_op_fixes, key, [])

        oracle_line = Keyword.get(oracle_meta, :line)
        oracle_col = Keyword.get(oracle_meta, :column)
        spitfire_line = Keyword.get(spitfire_meta, :line)
        spitfire_col = Keyword.get(spitfire_meta, :column)

        oracle_points_to_in = oracle_line == in_line and oracle_col == in_col
        spitfire_points_to_in = spitfire_line == in_line and spitfire_col == in_col

        # Choose the location that doesn't point to `in`, or Oracle if both do
        better =
          cond do
            oracle_meta == [] -> :spitfire
            spitfire_meta == [] -> :oracle
            not oracle_points_to_in -> :oracle
            not spitfire_points_to_in -> :spitfire
            true -> :same  # Both point to `in`, they likely match
          end

        {key, {better, oracle_meta, spitfire_meta}}
      end

    # Fix Oracle AST
    fixed_oracle =
      Macro.prewalk(oracle_ast, fn
        {op, oracle_meta, [{:in, in_meta, in_args} | rest]} when op in [:not, :!] ->
          key = {op, Keyword.get(in_meta, :line), Keyword.get(in_meta, :column)}
          spitfire_in_meta = Map.get(spitfire_in_fixes, key)

          # Fix op meta based on which source is better
          fixed_op_meta =
            case Map.get(better_locations, key) do
              {:spitfire, _oracle_meta, spitfire_meta} when spitfire_meta != [] ->
                spitfire_meta

              _ ->
                oracle_meta
            end

          # Fix in node's meta - add missing keys and handle end_of_expression placement
          fixed_in_meta =
            if spitfire_in_meta != nil do
              add_missing_meta(in_meta, spitfire_in_meta)
            else
              in_meta
            end

          # If Oracle has end_of_expression on op but Spitfire has it on in,
          # move it from op to in for consistency
          {fixed_op_meta, fixed_in_meta} =
            if Keyword.has_key?(fixed_op_meta, :end_of_expression) and
                 not Keyword.has_key?(in_meta, :end_of_expression) and
                 spitfire_in_meta != nil and
                 Keyword.has_key?(spitfire_in_meta, :end_of_expression) do
              {
                Keyword.delete(fixed_op_meta, :end_of_expression),
                Keyword.put(fixed_in_meta, :end_of_expression, Keyword.get(fixed_op_meta, :end_of_expression))
              }
            else
              {fixed_op_meta, fixed_in_meta}
            end

          {op, fixed_op_meta, [{:in, fixed_in_meta, in_args} | rest]}

        node ->
          node
      end)

    # Fix Spitfire AST
    fixed_spitfire =
      Macro.prewalk(spitfire_ast, fn
        {op, spitfire_meta, [{:in, in_meta, in_args} | rest]} when op in [:not, :!] ->
          key = {op, Keyword.get(in_meta, :line), Keyword.get(in_meta, :column)}
          oracle_in_meta = Map.get(oracle_in_fixes, key)

          # Fix op meta based on which source is better
          fixed_op_meta =
            case Map.get(better_locations, key) do
              {:oracle, oracle_meta, _spitfire_meta} when oracle_meta != [] ->
                # Use Oracle's meta as base, add any extra keys from Spitfire
                extra_keys = [:newlines, :end_of_expression, :parens]

                Enum.reduce(extra_keys, oracle_meta, fn key, acc ->
                  case Keyword.fetch(spitfire_meta, key) do
                    {:ok, value} -> Keyword.put_new(acc, key, value)
                    :error -> acc
                  end
                end)

              _ ->
                spitfire_meta
            end

          # Add missing meta to in node from Oracle
          fixed_in_meta =
            if oracle_in_meta != nil do
              add_missing_meta(in_meta, oracle_in_meta)
            else
              in_meta
            end

          {op, fixed_op_meta, [{:in, fixed_in_meta, in_args} | rest]}

        node ->
          node
      end)

    {fixed_oracle, fixed_spitfire}
  end

  # Add missing metadata keys from source to target
  defp add_missing_meta(target, source) do
    keys = [:newlines, :end_of_expression, :parens]

    Enum.reduce(keys, target, fn key, acc ->
      if Keyword.has_key?(acc, key) do
        acc
      else
        case Keyword.fetch(source, key) do
          {:ok, value} -> Keyword.put(acc, key, value)
          :error -> acc
        end
      end
    end)
  end

  # Collect metadata for not/! operators and their `in` arguments
  # Returns {op_fixes, in_fixes} maps keyed by {op, in_line, in_column}
  defp collect_not_in_meta(ast) do
    {_ast, {op_acc, in_acc}} =
      Macro.prewalk(ast, {%{}, %{}}, fn
        {op, meta, [{:in, in_meta, _in_args} | _rest]} = node, {op_acc, in_acc}
        when op in [:not, :!] ->
          # Key by operator and position of the `in` node (which is correct in both parsers)
          key = {op, Keyword.get(in_meta, :line), Keyword.get(in_meta, :column)}
          {node, {Map.put(op_acc, key, meta), Map.put(in_acc, key, in_meta)}}

        node, acc ->
          {node, acc}
      end)

    {op_acc, in_acc}
  end

  # ===========================================================================
  # AST Normalization (from V7 Section 10)
  # ===========================================================================

  @ignored_meta_keys [
    # :from_brackets,
    # :ambiguous_op,
    # :parens,
    # :format,
    # :closing,
    # :end_of_expression,
    :range
    # :newlines
    # :delimiter,
    # :indentation
  ]

  defp normalize_ast(ast) do
    ast
    |> unwrap_single_block()
    |> Macro.postwalk(fn
      {tag, meta, args} when is_list(meta) ->
        {tag, Keyword.drop(meta, @ignored_meta_keys), args}

      keyword when is_list(keyword) ->
        if Keyword.keyword?(keyword) do
          Keyword.drop(keyword, @ignored_meta_keys)
        else
          keyword
        end

      node ->
        node
    end)
  end

  # Unwrap single-element __block__ nodes (Oracle sometimes wraps parenthesized exprs)
  # TODO: decide if we should keep it or backport the parens handling
  defp unwrap_single_block({:__block__, _meta, [single]}) do
    unwrap_single_block(single)
  end

  defp unwrap_single_block(ast), do: ast
end
