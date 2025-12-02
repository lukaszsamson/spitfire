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
      # match_op_eol matched_expr
      code = "1 = 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 =\n2"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol matched_expr
      code = "1 + 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 +\n2"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol matched_expr
      code = "1 * 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 *\n2"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol matched_expr
      code = "1 ** 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 **\n2"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol matched_expr
      code = "1 <> 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <>\n2"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol matched_expr
      code = "1 .. 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ..\n2"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol matched_expr
      code = "1 // 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 //\n2"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol matched_expr
      code = "1 ^^^ 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ^^^\n2"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol matched_expr
      code = "1 && 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 &&\n2"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol matched_expr
      code = "1 || 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ||\n2"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol matched_expr
      code = "1 in 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 in\n2"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol matched_expr
      code = "1 <- 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <-\n2"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol matched_expr
      code = "1 :: 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ::\n2"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol matched_expr
      code = "1 when 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 when\n2"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol matched_expr
      code = "1 | 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 |\n2"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol matched_expr
      code = "1 == 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ==\n2"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol matched_expr
      code = "1 < 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <\n2"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol matched_expr
      code = "1 <~> 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <~>\n2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "matched_expr matched_op_expr - arrow_op_eol no_parens_one_expr" do
      # no_parens_one_expr -> dot_op_identifier call_args_no_parens_one
      # no_parens_one_expr -> dot_identifier call_args_no_parens_one
      # call_args_no_parens_one -> call_args_no_parens_kw
      # call_args_no_parens_one -> matched_expr
      # dot_identifier -> identifier
      # dot_identifier -> matched_expr dot_op identifier
      # dot_op_identifier -> op_identifier
      # dot_op_identifier -> matched_expr dot_op op_identifier
      # call_args_no_parens_kw -> call_args_no_parens_kw_expr
      # call_args_no_parens_kw -> call_args_no_parens_kw_expr ',' call_args_no_parens_kw
      # call_args_no_parens_kw_expr -> kw_eol matched_expr
      # call_args_no_parens_kw_expr -> kw_eol no_parens_expr

      # identifier matched_expr
      code = "1 |> a 2"
      assert Spitfire.parse(code) == s2q(code)

      # op_identifier matched_expr
      code = "1 |> a -2"
      assert Spitfire.parse(code) == s2q(code)

      # identifier call_args_no_parens_kw
      code = "1 |> a x: 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier matched_expr
      code = "1 |> a.b 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op op_identifier matched_expr
      code = "1 |> a.b -2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier call_args_no_parens_kw
      code = "1 |> a.b x: 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol matched_expr" do
      # unary_op
      code = "!true"
      assert Spitfire.parse(code) == s2q(code)
      code = "!\ntrue"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op
      code = "-true"
      assert Spitfire.parse(code) == s2q(code)
      code = "-\ntrue"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op
      code = "//true"
      assert Spitfire.parse(code) == s2q(code)
      code = "//\ntrue"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "at_op_eol matched_expr" do
      code = "@foo"
      assert Spitfire.parse(code) == s2q(code)
      code = "@\nfoo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture_op_eol matched_expr" do
      code = "&foo"
      assert Spitfire.parse(code) == s2q(code)
      code = "&\nfoo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis_op matched_expr" do
      code = "...foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_one_expr" do
      # identifier matched_expr
      code = "a 2"
      assert Spitfire.parse(code) == s2q(code)

      # op_identifier matched_expr
      code = "a -2"
      assert Spitfire.parse(code) == s2q(code)

      # identifier call_args_no_parens_kw
      code = "a x: 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier matched_expr
      code = "a.b 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op op_identifier matched_expr
      code = "a.b -2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier call_args_no_parens_kw
      code = "a.b x: 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (no_parens_zero_expr)" do
      # dot_do_identifier
      code = "foo do\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar do\nend"
      assert Spitfire.parse(code) == s2q(code)
      # dot_identifier
      code = "foo"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (range_op)" do
      code = ".."
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (ellipsis_op)" do
      code = "..."
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (access_expr)" do
      code = "foo[:bar]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "sub_matched_expr (access_expr kw_identifier)" do
      code = "foo[bar: :baz]"
      assert Spitfire.parse(code) == s2q(code)
    end

    # sub_matched_expr (access_expr) tests
    test "bracket_expr" do
      code = "foo[:bar]"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar[:baz]"
      assert Spitfire.parse(code) == s2q(code)

      code = "foo[:bar][baz]"
      assert Spitfire.parse(code) == s2q(code)

      code = "foo[:bar,]"
      assert Spitfire.parse(code) == s2q(code)
    end

      test "bracket_at_expr" do
        code = "@foo[1]"
        assert Spitfire.parse(code) == s2q(code)
        code = "@\nfoo[1]"
        assert Spitfire.parse(code) == s2q(code)

        code = "@foo.bar[1]"
        assert Spitfire.parse(code) == s2q(code)
        code = "@\nfoo.bar[1]"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "capture_int int" do
        code = "&1"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "fn_eoe stab_eoe 'end'" do
        code = "fn -> :ok end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn; -> :ok end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn\n-> :ok end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn\n;-> :ok end"
        assert Spitfire.parse(code) == s2q(code)

        code = "fn x -> x end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn x -> x; end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn x -> x\nend"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn x -> x\n;end"
        assert Spitfire.parse(code) == s2q(code)

        code = "fn x -> x; y -> y end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn x -> x\ny -> y end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn x -> x\n;y -> y end"
        assert Spitfire.parse(code) == s2q(code)

        code = "fn -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn ->\nend"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn ->\n1 end"
        assert Spitfire.parse(code) == s2q(code)

        code = "fn () -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn () when 1 -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn (1, 2) -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn (3, 2) when 1 -> end"
        assert Spitfire.parse(code) == s2q(code)

        code = "fn a -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn a, b -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn a b -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn a b, c -> end"
        assert Spitfire.parse(code) == s2q(code)
        code = "fn a b c -> end"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "open_paren stab_eoe ')'" do
        code = "(1)"
        assert Spitfire.parse(code) == s2q(code)

        code = "(->)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(\n->)"
        assert Spitfire.parse(code) == s2q(code)

        code = "(1 -> 2)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(1 -> 2;)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(1 -> 2\n)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(1 -> 2\n;)"
        assert Spitfire.parse(code) == s2q(code)

        code = "(a, b -> 2)"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "open_paren ';' stab_eoe ')'" do
        code = "(;1 -> 2)"
        assert Spitfire.parse(code) == s2q(code)

        code = "(\n;1 -> 2)"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "open_paren ';' close_paren" do
        code = "(;)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(\n;)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(;\n)"
        assert Spitfire.parse(code) == s2q(code)
        code = "(\n;\n)"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "empty_paren" do
        code = "()"
        assert Spitfire.parse(code) == s2q(code)
        code = "(\n)"
        assert Spitfire.parse(code) == s2q(code)
      end

      test "literals" do
        assert Spitfire.parse("1") == s2q("1")
        assert Spitfire.parse("1.0") == s2q("1.0")
        assert Spitfire.parse("?a") == s2q("?a")
        assert Spitfire.parse("[1, 2]") == s2q("[1, 2]")
        assert Spitfire.parse("%{a: 1}") == s2q("%{a: 1}")
        assert Spitfire.parse("{1, 2}") == s2q("{1, 2}")
        assert Spitfire.parse("{1, 2, 3}") == s2q("{1, 2, 3}")
        assert Spitfire.parse("true") == s2q("true")
        assert Spitfire.parse("false") == s2q("false")
        assert Spitfire.parse("nil") == s2q("nil")
        assert Spitfire.parse(":foo") == s2q(":foo")
        assert Spitfire.parse(":\"foo\"") == s2q(":\"foo\"")
      end

      test "strings and sigils" do
        assert Spitfire.parse("\"foo\"") == s2q("\"foo\"")
        assert Spitfire.parse("'foo'") == s2q("'foo'")
        assert Spitfire.parse("\"\"\"\nfoo\n\"\"\"") == s2q("\"\"\"\nfoo\n\"\"\"")
        assert Spitfire.parse("'''\nfoo\n'''") == s2q("'''\nfoo\n'''")
        assert Spitfire.parse("<<1>>") == s2q("<<1>>")
        assert Spitfire.parse("~s(foo)") == s2q("~s(foo)")
      end

      test "dot_alias" do
        assert Spitfire.parse("Foo") == s2q("Foo")
        assert Spitfire.parse("foo.Bar") == s2q("foo.Bar")
        assert Spitfire.parse("foo.{}") == s2q("foo.{}")
        assert Spitfire.parse("foo.{\n}") == s2q("foo.{\n}")
        assert Spitfire.parse("foo.{A}") == s2q("foo.{A}")
      end

      test "parens_call" do
        assert Spitfire.parse("foo()") == s2q("foo()")
        assert Spitfire.parse("foo(1)") == s2q("foo(1)")
        assert Spitfire.parse("foo.bar()") == s2q("foo.bar()")
      end
  end

  describe "unmatched_expr" do
    test "matched_expr unmatched_op_expr" do
      # match_op_eol unmatched_op_expr
      code = "1 = if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 =\n if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol unmatched_op_expr
      code = "1 + if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 +\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol unmatched_op_expr
      code = "1 * if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 *\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol unmatched_op_expr
      code = "1 ** if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 **\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol unmatched_op_expr
      code = "1 <> if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <>\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol unmatched_op_expr
      code = "1 .. if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ..\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol unmatched_op_expr
      code = "1 // if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 //\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol unmatched_op_expr
      code = "1 ^^^ if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ^^^\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol unmatched_op_expr
      code = "1 && if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 &&\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol unmatched_op_expr
      code = "1 || if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ||\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol unmatched_op_expr
      code = "1 in if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 in\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol unmatched_op_expr
      code = "1 <- if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <-\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol unmatched_op_expr
      code = "1 :: if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ::\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol unmatched_op_expr
      code = "1 when if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 when\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol unmatched_op_expr
      code = "1 | if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 |\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol unmatched_op_expr
      code = "1 == if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ==\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol unmatched_op_expr
      code = "1 < if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol unmatched_op_expr
      code = "1 <~> if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <~>\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr matched_op_expr" do
      # match_op_eol matched_expr
      code = "if true do\n:ok\nend = 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend =\n2"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol matched_expr
      code = "if true do\n:ok\nend + 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend +\n2"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol matched_expr
      code = "if true do\n:ok\nend * 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend *\n2"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol matched_expr
      code = "if true do\n:ok\nend ** 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend **\n2"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol matched_expr
      code = "if true do\n:ok\nend <> 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <>\n2"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol matched_expr
      code = "if true do\n:ok\nend .. 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ..\n2"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol matched_expr
      code = "if true do\n:ok\nend // 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend //\n2"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol matched_expr
      code = "if true do\n:ok\nend ^^^ 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ^^^\n2"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol matched_expr
      code = "if true do\n:ok\nend && 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend &&\n2"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol matched_expr
      code = "if true do\n:ok\nend || 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ||\n2"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol matched_expr
      code = "if true do\n:ok\nend in 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend in\n2"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol matched_expr
      code = "if true do\n:ok\nend <- 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <-\n2"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol matched_expr
      code = "if true do\n:ok\nend :: 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ::\n2"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol matched_expr
      code = "if true do\n:ok\nend when 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend when\n2"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol matched_expr
      code = "if true do\n:ok\nend | 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend |\n2"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol matched_expr
      code = "if true do\n:ok\nend == 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ==\n2"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol matched_expr
      code = "if true do\n:ok\nend < 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <\n2"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol matched_expr
      code = "if true do\n:ok\nend <~> 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <~>\n2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr matched_op_expr - arrow_op_eol no_parens_one_expr" do
      # identifier matched_expr
      code = "if true do\n:ok\nend |> a 2"
      assert Spitfire.parse(code) == s2q(code)

      # op_identifier matched_expr
      code = "if true do\n:ok\nend |> a -2"
      assert Spitfire.parse(code) == s2q(code)

      # identifier call_args_no_parens_kw
      code = "if true do\n:ok\nend |> a x: 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier matched_expr
      code = "if true do\n:ok\nend |> a.b 2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op op_identifier matched_expr
      code = "if true do\n:ok\nend |> a.b -2"
      assert Spitfire.parse(code) == s2q(code)

      # matched_expr dot_op identifier call_args_no_parens_kw
      code = "if true do\n:ok\nend |> a.b x: 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr unmatched_op_expr" do
      # match_op_eol matched_expr
      code = "if true do\n:ok\nend = unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend =\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol matched_expr
      code = "if true do\n:ok\nend + unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend +\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol matched_expr
      code = "if true do\n:ok\nend * unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend *\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol matched_expr
      code = "if true do\n:ok\nend ** unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend **\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol matched_expr
      code = "if true do\n:ok\nend <> unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <>\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol matched_expr
      code = "if true do\n:ok\nend .. unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ..\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol matched_expr
      code = "if true do\n:ok\nend // unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend //\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol matched_expr
      code = "if true do\n:ok\nend ^^^ unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ^^^\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol matched_expr
      code = "if true do\n:ok\nend && unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend &&\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol matched_expr
      code = "if true do\n:ok\nend || unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ||\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol matched_expr
      code = "if true do\n:ok\nend in unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend in\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol matched_expr
      code = "if true do\n:ok\nend <- unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <-\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol matched_expr
      code = "if true do\n:ok\nend :: unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ::\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol matched_expr
      code = "if true do\n:ok\nend when unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend when\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol matched_expr
      code = "if true do\n:ok\nend | unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend |\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol matched_expr
      code = "if true do\n:ok\nend == unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ==\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol matched_expr
      code = "if true do\n:ok\nend < unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol matched_expr
      code = "if true do\n:ok\nend <~> unless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <~>\nunless false do\n:error\nend"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr no_parens_op_expr" do
      # match_op_eol matched_expr
      code = "if true do\n:ok\nend = foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend =\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol matched_expr
      code = "if true do\n:ok\nend + foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend +\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol matched_expr
      code = "if true do\n:ok\nend * foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend *\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol matched_expr
      code = "if true do\n:ok\nend ** foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend **\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol matched_expr
      code = "if true do\n:ok\nend <> foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <>\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol matched_expr
      code = "if true do\n:ok\nend .. foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ..\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol matched_expr
      code = "if true do\n:ok\nend // foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend //\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol matched_expr
      code = "if true do\n:ok\nend ^^^ foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ^^^\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol matched_expr
      code = "if true do\n:ok\nend && foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend &&\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol matched_expr
      code = "if true do\n:ok\nend || foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ||\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol matched_expr
      code = "if true do\n:ok\nend in foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend in\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol matched_expr
      code = "if true do\n:ok\nend <- foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <-\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol matched_expr
      code = "if true do\n:ok\nend :: foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ::\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol matched_expr
      code = "if true do\n:ok\nend when foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend when\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol matched_expr
      code = "if true do\n:ok\nend | foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend |\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol matched_expr
      code = "if true do\n:ok\nend == foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend ==\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol matched_expr
      code = "if true do\n:ok\nend < foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol matched_expr
      code = "if true do\n:ok\nend <~> foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend <~>\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unmatched_expr no_parens_op_expr - when_op_eol call_args_no_parens_kw" do
      code = "if true do\n:ok\nend when foo: 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "if true do\n:ok\nend when\nfoo: 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol expr" do
      # unmatched_expr
      code = "!if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "!\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "!foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "!\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)

      # unmatched_expr
      code = "-if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "-\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "-foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "-\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)

      # unmatched_expr
      code = "//if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "//\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "//foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "//\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "at_op_eol expr" do
      # unmatched_expr
      code = "@if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "@\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "@foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "@\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture_op_eol expr" do
      # unmatched_expr
      code = "&if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      code = "&\nif true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "&foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "&\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis_op expr" do
      # unmatched_expr
      code = "...if true do\n:ok\nend"
      assert Spitfire.parse(code) == s2q(code)
      # no_parens_expr
      code = "...foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "block_expr (dot_do_identifier do_block)" do
      # TODO
      code = "foo do end"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "block_expr (dot_identifier call_args_no_parens_all do_block)" do
      # TODO
      code = "foo 1 do end"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "block_expr (dot_call_identifier call_args_parens do_block)" do
      # TODO
      code = "foo() do end"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "block_expr (dot_call_identifier call_args_parens call_args_parens do_block)" do
      # TODO
      code = "foo()() do end"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "no_parens_expr" do
    test "matched_expr no_parens_op_expr" do
      # match_op_eol matched_expr
      code = "1 = foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 =\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # dual_op_eol matched_expr
      code = "1 + foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 +\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # mult_op_eol matched_expr
      code = "1 * foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 *\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # power_op_eol matched_expr
      code = "1 ** foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 **\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # concat_op_eol matched_expr
      code = "1 <> foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <>\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # range_op_eol matched_expr
      code = "1 .. foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ..\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # ternary_op_eol matched_expr
      code = "1 // foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 //\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # xor_op_eol matched_expr
      code = "1 ^^^ foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ^^^\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # and_op_eol matched_expr
      code = "1 && foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 &&\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # or_op_eol matched_expr
      code = "1 || foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ||\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # in_op_eol matched_expr
      code = "1 in foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 in\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # in_match_op_eol matched_expr
      code = "1 <- foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <-\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # type_op_eol matched_expr
      code = "1 :: foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ::\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # when_op_eol matched_expr
      code = "1 when foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 when\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # pipe_op_eol matched_expr
      code = "1 | foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 |\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # comp_op_eol matched_expr
      code = "1 == foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 ==\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # rel_op_eol matched_expr
      code = "1 < foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      # arrow_op_eol matched_expr
      code = "1 <~> foo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 <~>\nfoo 3, 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "matched_expr no_parens_op_expr - when_op_eol call_args_no_parens_kw" do
      code = "1 when foo: 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "1 when\nfoo: 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary_op_eol no_parens_expr" do
      code = "!foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "!\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)

      code = "-foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "-\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)

      code = "//foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "//\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "at_op_eol no_parens_expr" do
      code = "@foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "@\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture_op_eol no_parens_expr" do
      code = "&foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "&\nfoo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis_op_eol no_parens_expr" do
      code = "...foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_one_ambig_expr" do
      # dot_identifier call_args_no_parens_ambig
      code = "foo bar 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.baz bar 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      # dot_op_identifier call_args_no_parens_ambig
      code = "foo -bar 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.baz -bar 1, 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "no_parens_many_expr" do
      code = "foo 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo 1, 2, 3"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar 1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar 1, 2, 3"
      assert Spitfire.parse(code) == s2q(code)

      code = "foo -1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo -1, 2, 3"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar -1, 2"
      assert Spitfire.parse(code) == s2q(code)
      code = "foo.bar -1, 2, 3"
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
