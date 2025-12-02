defmodule SpitfireGrammarTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:spitfire, :tokenizer, :legacy)
    Application.put_env(:spitfire, :tokenizer, :toxic)
    Application.put_env(:spitfire, :verify_range_order, true)

    on_exit(fn ->
      Application.put_env(:spitfire, :tokenizer, original)
      Application.put_env(:spitfire, :verify_range_order, false)
    end)
  end

  describe "MAIN FLOW OF EXPRESSIONS" do
    test "grammar -> eoe" do
      code = ";"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n;"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "grammar -> expr_list" do
      code = "1"
      assert Spitfire.parse(code) == s2q(code)

      code = "1;2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n;2"
      assert Spitfire.parse(code) == s2q(code)

      code = "1;2;3"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n2\n3"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n;2\n;3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "grammar -> eoe expr_list" do
      code = "; 1"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n1"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n;1"
      assert Spitfire.parse(code) == s2q(code)

      code = ";1;2"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n1\n2"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n;1\n;2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "grammar -> expr_list eoe" do
      code = "1;"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n"
      assert Spitfire.parse(code) == s2q(code)
      code = "1\n;"
      assert Spitfire.parse(code) == s2q(code)

      code = "2;1;"
      assert Spitfire.parse(code) == s2q(code)
      code = "2\n1\n"
      assert Spitfire.parse(code) == s2q(code)
      code = "2\n;1\n;"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "grammar -> eoe expr_list eoe" do
      code = ";1;"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n1\n"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n;1\n;"
      assert Spitfire.parse(code) == s2q(code)

      code = ";1;2;"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n1\n2\n"
      assert Spitfire.parse(code) == s2q(code)
      code = "\n;1\n;2\n;"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "grammar -> $empty" do
      code = ""
      assert {:ok, {:__block__, _, []}} = Spitfire.parse(code)
    end
  end

  describe "expr" do
    test "matched_expr" do
      code = "1 + 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_expr" do
      code = "foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr" do
      code = "foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "matched_expr" do
    test "matched_expr matched_op_expr" do
      code = "1 + 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol matched_expr" do
      code = "!true"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "at_op_eol matched_expr" do
      code = "@foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture_op_eol matched_expr" do
      code = "& &1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_one_expr" do
      code = "foo(1)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (access_expr)" do
      code = "foo[1]"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "unmatched_expr" do
    test "matched_expr unmatched_op_expr" do
      code = "a = 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr matched_op_expr" do
      code = "a = 1 + 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr unmatched_op_expr" do
      code = "a = b = 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr no_parens_op_expr" do
      code = "a = foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol expr" do
      # This is tricky. unmatched_expr -> unary_op_eol expr
      # `! a = 1` -> `!(a = 1)`
      code = "! a = 1"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "no_parens_expr" do
    test "matched_expr no_parens_op_expr" do
      code = "1 + foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol no_parens_expr" do
      code = "! foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "at_op_eol no_parens_expr" do
      code = "@foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_one_ambig_expr" do
      code = "foo bar 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_many_expr" do
      code = "foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  defp s2q(code, opts \\ []) do
    Code.string_to_quoted(
      code,
      Keyword.merge([columns: true, token_metadata: true, emit_warnings: false], opts)
    )
  end
end
