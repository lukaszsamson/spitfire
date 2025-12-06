defmodule Spitfire.TestHelpers do
  @moduledoc false
  defmacro lhs == rhs do
    quote do
      import Kernel
      import unquote(__MODULE__), except: [==: 2]

      lhs = Spitfire.TestHelpers.drop_ranges(unquote(lhs))
      rhs = Spitfire.TestHelpers.drop_ranges(unquote(rhs))

      assert lhs == rhs
    end
  end

  def drop_ranges(ast) do
    Macro.postwalk(ast, fn
      {t, meta, args} when is_list(meta) ->
        {t, Keyword.delete(meta, :range), args}

      list when is_list(list) ->
        if Keyword.keyword?(list), do: Keyword.delete(list, :range), else: list

      node ->
        node
    end)
  end

  def parity_encoder do
    fn literal, meta ->
      meta = Keyword.delete(meta, :range)
      {:ok, {:__literal__, meta, [literal]}}
    end
  end
end

Application.put_env(:spitfire, :strip_ranges, true)

Code.require_file("spitfire/property_generators.exs", __DIR__)
Code.require_file("spitfire/property.exs", __DIR__)
Code.require_file("spitfire/property/token_grammar_generators.exs", __DIR__)

ExUnit.start(exclude: [:skip, :skip_errors, :skip_comments, :skip_cursor])
