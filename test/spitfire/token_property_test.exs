defmodule Spitfire.TokenPropertyTest do
  @moduledoc """
  Property tests for token-driven grammar trees.

  These tests generate random grammar trees, compile them to Toxic tokens,
  render to source code, and verify they round-trip through both the
  Elixir oracle (Code.string_to_quoted) and Spitfire.
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

  describe "increment 1: literals and identifiers" do
    @tag :property
    @tag timeout: 120_000
    property "grammar trees produce valid code" do
      accepted = :counters.new(1, [:atomics])
      rejected = :counters.new(1, [:atomics])

      check all(
              tree <- Gen.grammar(phase: 1, max_depth: 3, max_forms: 3),
              max_runs: 100,
              max_shrinks: 50
            ) do
        tokens = TokenCompiler.to_tokens(tree, phase: 1)
        code = Toxic.ToString.to_string(tokens)

        case Code.string_to_quoted(code, @oracle_opts) do
          {:ok, _oracle_ast} ->
            :counters.add(accepted, 1, 1)
            # For now, just verify it parses - AST comparison comes later
            :ok

          {:error, _} ->
            :counters.add(rejected, 1, 1)
            :ok
        end
      end

      # Acceptance guard from V7 Section 10
      acc = :counters.get(accepted, 1)
      rej = :counters.get(rejected, 1)

      assert acc > 0, "No samples were accepted by the oracle"

      if acc + rej > 0 do
        rejection_rate = rej / (acc + rej)

        assert rejection_rate < 0.7,
               "Rejection rate too high: #{Float.round(rejection_rate * 100, 1)}% (#{rej}/#{acc + rej})"
      end
    end

    @tag :property
    @tag timeout: 120_000
    property "grammar trees round-trip through Spitfire" do
      check all(
              tree <- Gen.grammar(phase: 1, max_depth: 3, max_forms: 15),
              max_runs: 5000,
              max_shrinks: 25
            ) do
        tokens = TokenCompiler.to_tokens(tree, phase: 1)
        code = Toxic.ToString.to_string(tokens)
        IO.puts("----\n"<>code)

        case Code.string_to_quoted(code, @oracle_opts) do
          {:ok, oracle_ast} ->
            # Parse with Spitfire
            assert {:ok, spitfire_ast} = Spitfire.parse(code)

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
  # AST Normalization (from V7 Section 10)
  # ===========================================================================

  @ignored_meta_keys [
    # :from_brackets,
    # :ambiguous_op,
    # :parens,
    # :format,
    # :closing,
    # :end_of_expression,
    :range,
    # :delimiter,
    # :indentation
  ]

  defp normalize_ast(ast) do
    Macro.postwalk(ast, fn
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
end
