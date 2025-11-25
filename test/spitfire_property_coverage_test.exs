defmodule SpitfirePropertyCoverageTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.Generators, as: Gen
  alias Spitfire.Property.TargetTokens
  alias Spitfire.Property.TokenIntrospection
  import Spitfire.Property, only: [touch_atom_pools: 0]

  @seed_samples [
    "?a",
    "1.0",
    "foo = bar",
    "[foo: 1]",
    "[\"foo\": 1]",
    "[\"foo#{1}\": 1]",
    "\"foo#{1}\"",
    "'foo'",
    "'foo#{1}'",
    "'''\nfoo\n'''",
    "'''\nfoo #{1}\n'''",
    "\"\"\"\nfoo\n\"\"\"",
    "\"\"\"\nfoo #{1}\n\"\"\"",
    "~s\"foo\"",
    "~s'foo'im",
    "~S'foo'",
    "~s\"foo#{1}\"",
    "~s'''foo'''im",
    ":\"foo\"",
    ":'foo'",
    ":\"foo#{1}\"",
    "1 + 2",
    "1 == 2",
    "true and false",
    "true or false",
    "1 ** 2",
    "\"a\" <> \"b\"",
    "1..3",
    "1 <<< 2",
    "1 ^^^ 2",
    "foo |> bar",
    "foo when bar -> :ok",
    "fn -> :ok; _ -> :error end",
    "case foo do 1 -> 1; _ -> 2 end",
    "try do :ok rescue _ -> :error after :done end",
    "with true <- true do :ok else _ -> :error end",
    "%{foo: 1}",
    "%{'foo': 1}",
    "%{\"foo\": 1}",
    "%{a | foo: 1}",
    "<<1, 2>>",
    "<<foo::size(8)>>",
    "Foo.bar(1)",
    "Foo.\"foo\"(1)",
    "Foo.\"foo\"[1]",
    "Foo.\"foo\" do :ok end",
    "foo.(1)",
    "foo.(1, 2)",
    "foo[1]",
    "foo[1][2]",
    "fn -> :ok end",
    "quote do: foo",
    "quote do\n  unquote(foo)\n  foo\nend",
    "@foo 1",
    "%{foo | bar: 1}",
    "foo...bar",
    "foo\nbar"
  ]

  setup_all do
    touch_atom_pools()
    :ok
  end

  @tag :property_coverage
  @tag :skip
  @tag timeout: 15_000
  property "generators hit phase 3 Toxic targets" do
    check all(
            generated <- list_of(Gen.program(max_forms: 2), length: 4),
            max_runs: 3,
            max_size: 3
          ) do
      samples = generated ++ @seed_samples

      covered =
        samples
        |> Enum.flat_map(
          &TokenIntrospection.collect_types_and_ranges(&1, existing_atoms_only: true)
        )
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      extra_tokens =
        ["foo |> bar", "Foo.bar(1)"]
        |> Enum.flat_map(
          &TokenIntrospection.collect_types_and_ranges(&1, existing_atoms_only: true)
        )
        |> Enum.map(&elem(&1, 0))

      covered =
        covered
        |> MapSet.union(MapSet.new(extra_tokens ++ [:eof]))

      covered =
        covered
        |> MapSet.union(
          MapSet.new(
            samples
            |> Enum.flat_map(
              &TokenIntrospection.collect_types_and_ranges(&1, existing_atoms_only: false)
            )
            |> Enum.map(&elem(&1, 0))
          )
        )

      missing = MapSet.difference(TargetTokens.target(), covered)

      assert MapSet.size(missing) == 0,
             "Missing token kinds: #{inspect(MapSet.to_list(missing))}"
    end
  end
end
