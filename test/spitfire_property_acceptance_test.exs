defmodule SpitfirePropertyAcceptanceTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.Generators, as: Gen
  import Spitfire.Property, only: [touch_atom_pools: 0]

  @oracle_opts [columns: true, token_metadata: true, emit_warnings: false, existing_atoms_only: true]

  setup_all do
    touch_atom_pools()
    :ok
  end

  property "generator acceptance rate stays healthy" do
    check all codes <- list_of(Gen.program(max_forms: 3), length: 30),
              max_runs: 1 do
      accepted =
        Enum.count(codes, fn code ->
          case Code.string_to_quoted(code, @oracle_opts) do
            {:ok, _} -> true
            {:error, _} -> false
          end
        end)

      rate = accepted / max(length(codes), 1)

      assert rate >= 0.7, "Acceptance rate too low: #{rate}"
    end
  end
end
