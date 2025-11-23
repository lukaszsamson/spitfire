defmodule SpitfireRangesErrorTest do
  use ExUnit.Case, async: false

  setup do
    original_tokenizer = Application.get_env(:spitfire, :tokenizer)
    Application.put_env(:spitfire, :tokenizer, :toxic)
    Application.put_env(:spitfire, :strip_ranges, false)
    Application.put_env(:spitfire, :verify_range_order, true)

    on_exit(fn ->
      if original_tokenizer,
        do: Application.put_env(:spitfire, :tokenizer, original_tokenizer),
        else: Application.delete_env(:spitfire, :tokenizer)

      Application.put_env(:spitfire, :strip_ranges, true)
      Application.put_env(:spitfire, :verify_range_order, false)
    end)

    :ok
  end

  defp get_range({_form, meta, _args}) when is_list(meta), do: Keyword.get(meta, :range)
  defp get_range(_), do: nil

  defp test_encoder do
    fn lit, meta ->
      {:ok, {:__literal__, meta, [lit]}}
    end
  end

  defp parse(code) do
    case Spitfire.parse(code, literal_encoder: test_encoder()) do
      {:ok, ast} -> {ast, []}
      {:error, ast, errors} -> {ast, errors}
    end
  end

  test "unclosed list" do
    code = "[1, 2"
    {ast, errors} = parse(code)
    assert length(errors) == 1
    range = get_range(ast)
    assert range
    assert range == {{1, 1}, {1, 6}}
  end

  test "unclosed tuple" do
    code = "{1, 2"
    {ast, errors} = parse(code)
    assert length(errors) == 1
    range = get_range(ast)
    assert range
    assert range == {{1, 1}, {1, 6}}
  end

  test "unclosed map" do
    code = "%{a: 1"
    {ast, errors} = parse(code)
    assert length(errors) == 1
    range = get_range(ast)
    assert range
    assert range == {{1, 1}, {1, 7}}
  end

  test "unclosed do block" do
    code = "do\n  :ok"
    {ast, errors} = parse(code)
    assert length(errors) > 0
    range = get_range(ast)
    assert range
    assert range == {{1, 1}, {2, 6}}
  end

  test "incomplete binary op" do
    code = "1 +"
    {ast, errors} = parse(code)
    assert length(errors) == 1
    range = get_range(ast)
    assert range
    # 1 is 1:1. + is 1:3.
    # Missing RHS.
    # Range should cover 1 to + (1:4)
    assert range == {{1, 1}, {1, 4}}
  end
end
