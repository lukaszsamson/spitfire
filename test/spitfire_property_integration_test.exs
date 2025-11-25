defmodule SpitfirePropertyIntegrationTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.Generators, as: Gen
  alias Spitfire.Property.TokenIntrospection
  import Spitfire.Property, only: [touch_atom_pools: 0]

  @oracle_opts [
    columns: true,
    token_metadata: true,
    emit_warnings: false,
    existing_atoms_only: true
  ]

  setup_all do
    touch_atom_pools()
    :ok
  end

  @tag :property_integration
  @tag :skip
  @tag timeout: 15_000
  property "oracle-accepted programs have no synthetic tokens" do
    check all(
            code <- Gen.program(max_forms: 2),
            max_runs: 5,
            max_size: 3
          ) do
      case Code.string_to_quoted(code, @oracle_opts) do
        {:ok, _} ->
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

          assert synthetic == [], "Synthetic tokens found: #{inspect(synthetic)}"

        {:error, _} ->
          :ok
      end
    end
  end
end
