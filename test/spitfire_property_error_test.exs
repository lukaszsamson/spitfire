defmodule SpitfirePropertyErrorTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Spitfire.Property.TokenIntrospection
  import Spitfire.Property, only: [touch_atom_pools: 0]

  @parser_opts [
    tokenizer: :toxic,
    columns: true,
    token_metadata: true,
    error_mode: :tolerant,
    insert_structural_closers: true,
    existing_atoms_only: true
  ]

  setup_all do
    touch_atom_pools()
    :ok
  end

  @tag :property_error
  @tag :skip
  @tag timeout: 15_000
  property "does not crash on arbitrary UTF-8" do
    check all(
            code <- string(:utf8, length: 0..120),
            max_runs: 5,
            max_size: 3
          ) do
      result =
        try do
          _ = Spitfire.parse(code, @parser_opts)
          :ok
        rescue
          exception ->
            {:raised, exception}
        catch
          kind, reason ->
            {:caught, {kind, reason}}
        end

      refute match?({:raised, _}, result)
      refute match?({:caught, _}, result)
    end
  end

  @tag :property_error
  @tag :skip
  @tag timeout: 15_000
  property "propagates Toxic errors for malformed programs" do
    check all(
            code <- malformed_code(),
            max_runs: 5,
            max_size: 3
          ) do
      stream =
        Toxic.new(code, 1, 1,
          error_mode: :tolerant,
          insert_structural_closers: true,
          existing_atoms_only: true
        )

      {errors, _} = Toxic.errors(stream)
      tokens = TokenIntrospection.collect_tokens(stream)

      has_error_token? =
        Enum.any?(tokens, fn
          {:error_token, _, _} -> true
          _ -> false
        end)

      assert errors != [] or has_error_token?,
             "Expected Toxic to surface an error token for malformed code"

      parse_result =
        try do
          Spitfire.parse(code, @parser_opts)
        rescue
          exception ->
            {:raised, exception}
        end

      assert match?({:error, _, _}, parse_result) or parse_result == {:error, :no_fuel_remaining}
    end
  end

  defp malformed_code do
    frequency([
      {3, map(string(:alphanumeric, length: 1..6), fn val -> "#{val}(" end)},
      {2, constant("(")},
      {2, constant("[1,")},
      {2, constant("<<1,")},
      {2, constant(~s("foo))},
      {2, constant(~s('bar))},
      {2, constant("fn ->")},
      {2, constant("case do")},
      {2, constant("if true do")},
      {2, constant(~s(foo \#{))},
      {1, constant("<<")},
      {1, constant("%{")},
      {1, constant("foo(")}
    ])
  end
end
