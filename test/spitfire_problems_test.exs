defmodule SpitfireProblemsTest do
  use ExUnit.Case, async: true

  defp spitfire_opts do
    [
      tokenizer: :toxic,
      literal_encoder: &__MODULE__.literal_encoder/2,
      columns: true,
      token_metadata: true,
      unescape: false,
      emit_warnings: false
    ]
  end

  defp code_opts do
    [
      columns: true,
      token_metadata: true,
      unescape: false,
      literal_encoder: &__MODULE__.literal_encoder/2
    ]
  end

  def literal_encoder(value, meta), do: {:ok, {:__block__, meta, [value]}}

  describe "problem 1 - AST metadata differences" do
    test "Spitfire preserves quoted atom escapes when unescape: false" do
      code = ~S(:"hello \" \t")

      {:ok, spitfire_ast, _comments} = Spitfire.parse_with_comments(code, spitfire_opts())
      {code_ast, _comments} = Code.string_to_quoted_with_comments!(code, code_opts())

      assert {:__block__, _, [code_atom]} = code_ast
      assert {:__block__, _, [spitfire_atom]} = spitfire_ast

      assert code_atom == :"hello \" \\t"
      assert spitfire_atom == code_atom
      assert spitfire_ast == code_ast
    end

    test "Keyword keys retain delimiter/format metadata" do
      code = ~S(["hello 🐈": 1])

      {:ok, {:__block__, _, [[{ {:__block__, spitfire_meta, _}, _value }]]}, _} =
        Spitfire.parse_with_comments(code, spitfire_opts())

      {{:__block__, _, [[{ {:__block__, code_meta, _}, _value }]]}, _comments} =
        Code.string_to_quoted_with_comments!(code, code_opts())

      assert Keyword.get(spitfire_meta, :delimiter) == "\""
      assert Keyword.get(spitfire_meta, :format) == :keyword
      assert Keyword.get(spitfire_meta, :delimiter) == Keyword.get(code_meta, :delimiter)
      assert Keyword.get(spitfire_meta, :format) == Keyword.get(code_meta, :format)
    end
  end

  test "Spitfire empty function" do
      code = ~S"""
      fn -> end
      """

      {:ok, spitfire_ast, _comments} = Spitfire.parse_with_comments(code, spitfire_opts())
      {code_ast, _comments} = Code.string_to_quoted_with_comments!(code, code_opts())

      assert spitfire_ast == code_ast
  end

  test "Spitfire empty function 1" do
      code = ~S"""
      fn x -> end
      """

      {:ok, spitfire_ast, _comments} = Spitfire.parse_with_comments(code, spitfire_opts())
      {code_ast, _comments} = Code.string_to_quoted_with_comments!(code, code_opts())

      assert spitfire_ast == code_ast
  end

#   describe "problem 2 – range invariants" do
#     test "Heredoc ranges start at column 1 regardless of indentation" do
#       code = ~S'''
#     """
#   hello
#   """
# '''

#       {:ok, {:__block__, meta, _}, _} = Spitfire.parse_with_comments(code, spitfire_opts())
#       {{:__block__, code_meta, _}, _comments} = Code.string_to_quoted_with_comments!(code, code_opts())

#       dbg(code_meta)

#       assert meta[:column] == 5
#       assert {{1, 1}, _} = meta[:range]
#     end
  # end
end
