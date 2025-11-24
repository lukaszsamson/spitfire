defmodule SpitfirePropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Spitfire.Property, only: [normalize_ast: 1, touch_atom_pools: 0]
  alias Spitfire.Property.Generators, as: Gen
  alias Spitfire.Property.TokenIntrospection

  setup do
    touch_atom_pools()

    original_tokenizer = Application.get_env(:spitfire, :tokenizer, :legacy)
    original_verify_order = Application.get_env(:spitfire, :verify_range_order, false)

    Application.put_env(:spitfire, :tokenizer, :toxic)
    Application.put_env(:spitfire, :verify_range_order, true)

    on_exit(fn ->
      Application.put_env(:spitfire, :tokenizer, original_tokenizer)
      Application.put_env(:spitfire, :verify_range_order, original_verify_order)
    end)
  end

  property "parses oracle-accepted programs with Toxic" do
    oracle_opts = [columns: true, token_metadata: true, emit_warnings: false, existing_atoms_only: true]
    parser_opts = [tokenizer: :toxic, columns: true, token_metadata: true, existing_atoms_only: true]

    check all code <- Gen.program(max_forms: 3),
              max_runs: 30 do
      case Code.string_to_quoted(code, oracle_opts) do
        {:ok, oracle_ast} ->
          assert {:ok, spitfire_ast} = Spitfire.parse(code, parser_opts)
          assert normalize_ast(spitfire_ast) == normalize_ast(oracle_ast)

          assert_no_toxic_errors(code)
          assert_no_synthetic_tokens(code)

        {:error, _reason} ->
          :ok
      end
    end
  end

  defp assert_no_toxic_errors(code) do
    error_stream =
      Toxic.new(code, 1, 1,
        error_mode: :tolerant,
        insert_structural_closers: true,
        existing_atoms_only: true
      )

    {errors, _} = Toxic.errors(error_stream)

    assert errors == []

    tokens =
      code
      |> Toxic.new(1, 1,
        error_mode: :tolerant,
        insert_structural_closers: true,
        existing_atoms_only: true
      )
      |> TokenIntrospection.collect_tokens()

    refute Enum.any?(tokens, fn
             {:error_token, _, _} -> true
             _ -> false
           end)
  end

  defp assert_no_synthetic_tokens(code) do
    stream =
      Toxic.new(code, 1, 1,
        error_mode: :tolerant,
        insert_structural_closers: true,
        existing_atoms_only: true
      )

    tokens = TokenIntrospection.collect_tokens(stream)

    synthetic =
      Enum.filter(tokens, fn
        {:eof, _} ->
          false

        {_kind, {{sl, sc}, {el, ec}, _extra}, _} ->
          sl == el and sc == ec

        {_kind, {{sl, sc}, {el, ec}, _extra}} ->
          sl == el and sc == ec

        _ ->
          false
      end)

    assert synthetic == []
  end
end
