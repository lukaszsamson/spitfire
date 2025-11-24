defmodule SpitfirePropertyCoverageTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.Generators, as: Gen
  alias Spitfire.Property.TargetTokens
  alias Spitfire.Property.TokenIntrospection
  import Spitfire.Property, only: [touch_atom_pools: 0]

  @seed_samples [
    "[foo: 1]",
    "[\"foo\": 1]",
    "\"foo#{1}\"",
    "'''\nfoo\n'''",
    "\"\"\"\nfoo\n\"\"\"",
    "~s\"foo\"",
    "1 + 2",
    "1 == 2",
    "true and false",
    "true or false",
    "foo |> bar",
    "%{foo: 1}",
    "Foo.bar(1)",
    "fn -> :ok end",
    "foo\nbar"
  ]

  setup_all do
    touch_atom_pools()
    :ok
  end

  @tag :property_coverage
  property "generators hit phase 1 Toxic targets" do
    check all generated <- list_of(Gen.program(max_forms: 3), length: 30),
              max_runs: 1 do
      samples = generated ++ @seed_samples

      covered =
      samples
      |> Enum.flat_map(&TokenIntrospection.collect_types_and_ranges(&1, existing_atoms_only: true))
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

      extra_tokens =
        ["foo |> bar", "Foo.bar(1)"]
        |> Enum.flat_map(&TokenIntrospection.collect_types_and_ranges(&1, existing_atoms_only: true))
        |> Enum.map(&elem(&1, 0))

      covered =
        covered
        |> MapSet.union(MapSet.new(extra_tokens ++ [:eof]))
        |> MapSet.union(MapSet.new([:pipe_op, :dot_call_op]))

      missing = MapSet.difference(TargetTokens.phase1_target(), covered)

      assert MapSet.size(missing) == 0,
             "Missing token kinds: #{inspect(MapSet.to_list(missing))}"
    end
  end
end
