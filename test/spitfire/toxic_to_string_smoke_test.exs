defmodule Spitfire.ToxicToStringSmokeTest do
  @moduledoc """
  Step 0 verification tests for Toxic.to_string/1.

  These tests verify the token format and behavior of Toxic before building
  any generators. Per V7 Section 1, this must pass before any property fuzzing.
  """
  use ExUnit.Case, async: true

  # Helper to create ranged meta: {{start_line, start_col}, {end_line, end_col}, extra}
  defp meta(sl, sc, el, ec, extra \\ nil), do: {{sl, sc}, {el, ec}, extra}

  # Round-trip test: construct tokens, render to string, parse with oracle
  defp assert_roundtrip(tokens, expected_code) do
    code = Toxic.ToString.to_string(tokens)
    assert code == expected_code, "Expected #{inspect(expected_code)}, got #{inspect(code)}"

    # Verify it parses successfully
    case Code.string_to_quoted(code, columns: true, token_metadata: true) do
      {:ok, _ast} -> :ok
      {:error, error} -> flunk("Code.string_to_quoted failed: #{inspect(error)}")
    end
  end

  describe "meta format verification" do
    test "ranged meta format: {{sl, sc}, {el, ec}, extra}" do
      # Verify the expected meta format
      tokens = [
        {:int, meta(1, 1, 1, 2, 1), ~c"1"}
      ]

      code = Toxic.ToString.to_string(tokens)
      assert code == "1"
    end

    test "extra field for :eol tokens is newline count" do
      tokens = [
        {:identifier, meta(1, 1, 1, 4, ~c"foo"), :foo},
        {:eol, meta(1, 4, 2, 1, 2)}
      ]

      code = Toxic.ToString.to_string(tokens)
      # 2 newlines from :eol extra
      assert code == "foo\n\n"
    end

    test "extra field for atoms is original charlist" do
      tokens = [
        {:atom, meta(1, 1, 1, 5, ~c"foo"), :foo}
      ]

      code = Toxic.ToString.to_string(tokens)
      assert code == ":foo"
    end

    test "extra field for identifiers is original charlist" do
      tokens = [
        {:identifier, meta(1, 1, 1, 4, ~c"foo"), :foo}
      ]

      code = Toxic.ToString.to_string(tokens)
      assert code == "foo"
    end

    test "operators extra is nil - newlines come from :eol tokens" do
      # Operator followed by :eol token for newline
      tokens = [
        {:identifier, meta(1, 1, 1, 2, ~c"a"), :a},
        {:dual_op, meta(1, 3, 1, 4, nil), :+},
        {:eol, meta(1, 4, 2, 1, 1)},
        {:identifier, meta(2, 1, 2, 2, ~c"b"), :b}
      ]

      code = Toxic.ToString.to_string(tokens)
      assert code == "a +\nb"
    end
  end

  describe "literals and numeric formats" do
    test "simple integer" do
      assert_roundtrip(
        [{:int, meta(1, 1, 1, 4, 123), ~c"123"}],
        "123"
      )
    end

    test "integer with underscores" do
      assert_roundtrip(
        [{:int, meta(1, 1, 1, 10, 1_000_000), ~c"1_000_000"}],
        "1_000_000"
      )
    end

    test "hexadecimal integer" do
      assert_roundtrip(
        [{:int, meta(1, 1, 1, 5, 0x1F), ~c"0x1F"}],
        "0x1F"
      )
    end

    test "binary integer" do
      assert_roundtrip(
        [{:int, meta(1, 1, 1, 8, 0b1010), ~c"0b10_10"}],
        "0b10_10"
      )
    end

    test "octal integer" do
      assert_roundtrip(
        [{:int, meta(1, 1, 1, 8, 0o777), ~c"0o7_7_7"}],
        "0o7_7_7"
      )
    end

    test "simple float" do
      assert_roundtrip(
        [{:flt, meta(1, 1, 1, 4, 1.0), ~c"1.0"}],
        "1.0"
      )
    end

    test "float with exponent" do
      assert_roundtrip(
        [{:flt, meta(1, 1, 1, 8, 1.0e-10), ~c"1.0e-10"}],
        "1.0e-10"
      )
    end

    test "char literal" do
      # ?a - the extra field contains the original char form
      assert_roundtrip(
        [{:char, meta(1, 1, 1, 3, ~c"?a"), ?a}],
        "?a"
      )
    end

    test "char literal with escape" do
      assert_roundtrip(
        [{:char, meta(1, 1, 1, 3, ~c"?\\n"), ?\n}],
        "?\\n"
      )
    end
  end

  describe "atoms" do
    test "simple atom" do
      assert_roundtrip(
        [{:atom, meta(1, 1, 1, 5, ~c"foo"), :foo}],
        ":foo"
      )
    end

    test "boolean true" do
      assert_roundtrip(
        [{true, meta(1, 1, 1, 5)}],
        "true"
      )
    end

    test "boolean false" do
      assert_roundtrip(
        [{false, meta(1, 1, 1, 6)}],
        "false"
      )
    end

    test "nil" do
      assert_roundtrip(
        [{nil, meta(1, 1, 1, 4)}],
        "nil"
      )
    end

    test "quoted atom with double quotes" do
      # :"foo bar" using linearized tokens
      assert_roundtrip(
        [
          {:atom_safe_start, meta(1, 1, 1, 3, nil), ?"},
          {:string_fragment, meta(1, 3, 1, 10, nil), "foo bar"},
          {:atom_safe_end, meta(1, 10, 1, 11, nil), ?"}
        ],
        ":\"foo bar\""
      )
    end
  end

  describe "identifiers and aliases" do
    test "simple identifier" do
      assert_roundtrip(
        [{:identifier, meta(1, 1, 1, 4, ~c"foo"), :foo}],
        "foo"
      )
    end

    test "alias" do
      assert_roundtrip(
        [{:alias, meta(1, 1, 1, 4, ~c"Foo"), :Foo}],
        "Foo"
      )
    end

    test "multi-part alias" do
      # MyApp.Context
      assert_roundtrip(
        [
          {:alias, meta(1, 1, 1, 6, ~c"MyApp"), :MyApp},
          {:., meta(1, 6, 1, 7)},
          {:alias, meta(1, 7, 1, 14, ~c"Context"), :Context}
        ],
        "MyApp.Context"
      )
    end
  end

  describe "operators" do
    test "binary operator" do
      # 1 + 2
      assert_roundtrip(
        [
          {:int, meta(1, 1, 1, 2, 1), ~c"1"},
          {:dual_op, meta(1, 3, 1, 4, nil), :+},
          {:int, meta(1, 5, 1, 6, 2), ~c"2"}
        ],
        "1 + 2"
      )
    end

    test "binary operator with newline (op_eol pattern)" do
      # a +\n 1 - operator followed by :eol token
      assert_roundtrip(
        [
          {:identifier, meta(1, 1, 1, 2, ~c"a"), :a},
          {:dual_op, meta(1, 3, 1, 4, nil), :+},
          {:eol, meta(1, 4, 2, 1, 1)},
          {:int, meta(2, 2, 2, 3, 1), ~c"1"}
        ],
        "a +\n 1"
      )
    end

    test "pipe operator" do
      # a |> b
      assert_roundtrip(
        [
          {:identifier, meta(1, 1, 1, 2, ~c"a"), :a},
          {:pipe_op, meta(1, 3, 1, 5, nil), :|>},
          {:identifier, meta(1, 6, 1, 7, ~c"b"), :b}
        ],
        "a |> b"
      )
    end

    test "comparison operator" do
      # a == b
      assert_roundtrip(
        [
          {:identifier, meta(1, 1, 1, 2, ~c"a"), :a},
          {:comp_op, meta(1, 3, 1, 5, nil), :==},
          {:identifier, meta(1, 6, 1, 7, ~c"b"), :b}
        ],
        "a == b"
      )
    end

    test "unary operator" do
      # not a
      assert_roundtrip(
        [
          {:unary_op, meta(1, 1, 1, 4, nil), :not},
          {:identifier, meta(1, 5, 1, 6, ~c"a"), :a}
        ],
        "not a"
      )
    end
  end

  describe "adhesion cases" do
    test "map literal %{a: 1} - dual %{ tokens" do
      # %{} token followed immediately by { for map
      assert_roundtrip(
        [
          {:%{}, meta(1, 1, 1, 2, nil)},
          {:"{", meta(1, 2, 1, 3, nil)},
          {:kw_identifier, meta(1, 3, 1, 4, ~c"a"), :a},
          {:int, meta(1, 6, 1, 7, 1), ~c"1"},
          {:"}", meta(1, 7, 1, 8, nil)}
        ],
        "%{a: 1}"
      )
    end

    test "capture_int &10 - adhesion between & and integer" do
      # &10 - no space between & and 10
      assert_roundtrip(
        [
          {:capture_int, meta(1, 1, 1, 2, nil), :&},
          {:int, meta(1, 2, 1, 4, 10), ~c"10"}
        ],
        "&10"
      )
    end

    test "dot-call foo.(1) - adhesion between . and (" do
      # foo.(1)
      assert_roundtrip(
        [
          {:identifier, meta(1, 1, 1, 4, ~c"foo"), :foo},
          {:dot_call_op, meta(1, 4, 1, 5, nil), :.},
          {:"(", meta(1, 5, 1, 6, nil)},
          {:int, meta(1, 6, 1, 7, 1), ~c"1"},
          {:")", meta(1, 7, 1, 8, nil)}
        ],
        "foo.(1)"
      )
    end

    test "parens call foo(1, 2)" do
      assert_roundtrip(
        [
          {:paren_identifier, meta(1, 1, 1, 4, ~c"foo"), :foo},
          {:"(", meta(1, 4, 1, 5, nil)},
          {:int, meta(1, 5, 1, 6, 1), ~c"1"},
          {:",", meta(1, 6, 1, 7, nil)},
          {:int, meta(1, 8, 1, 9, 2), ~c"2"},
          {:")", meta(1, 9, 1, 10, nil)}
        ],
        "foo(1, 2)"
      )
    end

    test "range 1..10" do
      assert_roundtrip(
        [
          {:int, meta(1, 1, 1, 2, 1), ~c"1"},
          {:range_op, meta(1, 2, 1, 4, nil), :..},
          {:int, meta(1, 4, 1, 6, 10), ~c"10"}
        ],
        "1..10"
      )
    end

    test "range with step 1..10//2" do
      assert_roundtrip(
        [
          {:int, meta(1, 1, 1, 2, 1), ~c"1"},
          {:range_op, meta(1, 2, 1, 4, nil), :..},
          {:int, meta(1, 4, 1, 6, 10), ~c"10"},
          {:ternary_op, meta(1, 6, 1, 8, nil), :"//"},
          {:int, meta(1, 8, 1, 9, 2), ~c"2"}
        ],
        "1..10//2"
      )
    end
  end

  describe "fn expressions" do
    test "simple fn -> nil end" do
      assert_roundtrip(
        [
          {:fn, meta(1, 1, 1, 3, nil)},
          {:stab_op, meta(1, 4, 1, 6, nil), :->},
          {nil, meta(1, 7, 1, 10)},
          {:end, meta(1, 11, 1, 14, nil)}
        ],
        "fn -> nil end"
      )
    end

    test "fn x -> x end" do
      assert_roundtrip(
        [
          {:fn, meta(1, 1, 1, 3, nil)},
          {:identifier, meta(1, 4, 1, 5, ~c"x"), :x},
          {:stab_op, meta(1, 6, 1, 8, nil), :->},
          {:identifier, meta(1, 9, 1, 10, ~c"x"), :x},
          {:end, meta(1, 11, 1, 14, nil)}
        ],
        "fn x -> x end"
      )
    end
  end

  describe "blocks and keywords" do
    test "do ... end block" do
      # if true do 1 end
      assert_roundtrip(
        [
          {:do_identifier, meta(1, 1, 1, 3, ~c"if"), :if},
          {true, meta(1, 4, 1, 8)},
          {:do, meta(1, 9, 1, 11, nil)},
          {:int, meta(1, 12, 1, 13, 1), ~c"1"},
          {:end, meta(1, 14, 1, 17, nil)}
        ],
        "if true do 1 end"
      )
    end

    test "do ... else ... end block" do
      # if true do 1 else 2 end
      assert_roundtrip(
        [
          {:do_identifier, meta(1, 1, 1, 3, ~c"if"), :if},
          {true, meta(1, 4, 1, 8)},
          {:do, meta(1, 9, 1, 11, nil)},
          {:int, meta(1, 12, 1, 13, 1), ~c"1"},
          {:block_identifier, meta(1, 14, 1, 18, nil), :else},
          {:int, meta(1, 19, 1, 20, 2), ~c"2"},
          {:end, meta(1, 21, 1, 24, nil)}
        ],
        "if true do 1 else 2 end"
      )
    end
  end

  describe "guards" do
    test "case with when guard" do
      # case x do\n  y when is_atom(y) -> y\nend
      assert_roundtrip(
        [
          {:do_identifier, meta(1, 1, 1, 5, ~c"case"), :case},
          {:identifier, meta(1, 6, 1, 7, ~c"x"), :x},
          {:do, meta(1, 8, 1, 10, nil)},
          {:eol, meta(1, 10, 2, 1, 1)},
          {:identifier, meta(2, 3, 2, 4, ~c"y"), :y},
          {:when_op, meta(2, 5, 2, 9, nil), :when},
          {:paren_identifier, meta(2, 10, 2, 17, ~c"is_atom"), :is_atom},
          {:"(", meta(2, 17, 2, 18, nil)},
          {:identifier, meta(2, 18, 2, 19, ~c"y"), :y},
          {:")", meta(2, 19, 2, 20, nil)},
          {:stab_op, meta(2, 21, 2, 23, nil), :->},
          {:identifier, meta(2, 24, 2, 25, ~c"y"), :y},
          {:eol, meta(2, 25, 3, 1, 1)},
          {:end, meta(3, 1, 3, 4, nil)}
        ],
        "case x do\n  y when is_atom(y) -> y\nend"
      )
    end
  end

  describe "strings and interpolation" do
    test "simple string" do
      assert_roundtrip(
        [
          {:bin_string_start, meta(1, 1, 1, 2, nil), ?"},
          {:string_fragment, meta(1, 2, 1, 7, nil), "hello"},
          {:bin_string_end, meta(1, 7, 1, 8, nil), ?"}
        ],
        "\"hello\""
      )
    end

    test "string with interpolation" do
      # "hello #{world}"
      assert_roundtrip(
        [
          {:bin_string_start, meta(1, 1, 1, 2, nil), ?"},
          {:string_fragment, meta(1, 2, 1, 8, nil), "hello "},
          {:begin_interpolation, meta(1, 8, 1, 10, nil), nil},
          {:identifier, meta(1, 10, 1, 15, ~c"world"), :world},
          {:end_interpolation, meta(1, 15, 1, 16, nil), nil},
          {:bin_string_end, meta(1, 16, 1, 17, nil), ?"}
        ],
        "\"hello \#{world}\""
      )
    end
  end

  describe "heredocs" do
    test "simple heredoc" do
      # Check heredoc closing delimiter position
      # """
      # hello
      # """
      # indent = 0, closing at col 1
      assert_roundtrip(
        [
          {:bin_heredoc_start, meta(1, 1, 1, 4, nil), nil},
          {:string_fragment, meta(2, 1, 2, 6, nil), "hello\n"},
          {:bin_heredoc_end, meta(3, 1, 3, 4, nil), nil, 0}
        ],
        "\"\"\"\nhello\n\"\"\""
      )
    end

    test "heredoc with indentation - closing at column indent + 1" do
      # """
      #   hello
      #   """ (2 space indent)
      # indent = 2 -> closing at col 3
      assert_roundtrip(
        [
          {:bin_heredoc_start, meta(1, 1, 1, 4, nil), nil},
          {:string_fragment, meta(2, 1, 2, 8, nil), "  hello\n"},
          {:bin_heredoc_end, meta(3, 3, 3, 6, nil), nil, 2}
        ],
        "\"\"\"\n  hello\n  \"\"\""
      )
    end
  end

  describe "sigils" do
    test "simple sigil ~r/foo/" do
      assert_roundtrip(
        [
          {:sigil_start, meta(1, 1, 1, 4, nil), :sigil_r, ?/},
          {:string_fragment, meta(1, 4, 1, 7, nil), "foo"},
          {:sigil_end, meta(1, 7, 1, 8, nil), ?/, 0}
        ],
        "~r/foo/"
      )
    end

    test "sigil with modifiers ~r/foo/iu" do
      assert_roundtrip(
        [
          {:sigil_start, meta(1, 1, 1, 4, nil), :sigil_r, ?/},
          {:string_fragment, meta(1, 4, 1, 7, nil), "foo"},
          {:sigil_end, meta(1, 7, 1, 8, nil), ?/, 0},
          {:sigil_modifiers, meta(1, 8, 1, 10, nil), ~c"iu"}
        ],
        "~r/foo/iu"
      )
    end
  end

  describe "EOL behavior verification" do
    test "only :eol tokens render newlines, not operator extra" do
      # This verifies V7 Section 2: operators never render newlines from extra
      # Construct tokens where operator has extra but :eol provides newlines
      tokens = [
        {:identifier, meta(1, 1, 1, 2, ~c"a"), :a},
        {:dual_op, meta(1, 3, 1, 4, 0), :+},
        # The :eol token carries the actual newline count
        {:eol, meta(1, 4, 2, 1, 1)},
        {:identifier, meta(2, 1, 2, 2, ~c"b"), :b}
      ]

      code = Toxic.ToString.to_string(tokens)
      # Should have exactly one newline
      assert code == "a +\nb"
    end
  end
end
