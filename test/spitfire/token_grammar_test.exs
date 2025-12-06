defmodule Spitfire.TokenGrammarTest do
  @moduledoc """
  Deterministic "golden" tests for TokenCompiler.to_tokens/2.

  These tests verify that hand-crafted grammar trees compile to correct
  Toxic tokens and round-trip through Toxic.to_string/1 and Code.string_to_quoted/2.
  """
  use ExUnit.Case, async: true

  alias Spitfire.Property.TokenCompiler

  # Round-trip helper: compile to tokens, render to string, parse with oracle
  defp assert_roundtrip(tree, expected_code) do
    tokens = TokenCompiler.to_tokens(tree)
    code = Toxic.ToString.to_string(tokens)

    assert code == expected_code,
           "Expected code #{inspect(expected_code)}, got #{inspect(code)}\nTokens: #{inspect(tokens)}"

    case Code.string_to_quoted(code, columns: true, token_metadata: true) do
      {:ok, _ast} -> :ok
      {:error, error} -> flunk("Code.string_to_quoted failed: #{inspect(error)}")
    end
  end

  describe "literals: integers" do
    test "decimal integer" do
      tree = {:grammar, [{:int, 123, :dec, ~c"123"}]}
      assert_roundtrip(tree, "123")
    end

    test "negative decimal integer" do
      tree = {:grammar, [{:int, -42, :dec, ~c"-42"}]}
      assert_roundtrip(tree, "-42")
    end

    test "zero" do
      tree = {:grammar, [{:int, 0, :dec, ~c"0"}]}
      assert_roundtrip(tree, "0")
    end

    test "hexadecimal integer" do
      tree = {:grammar, [{:int, 255, :hex, ~c"0xFF"}]}
      assert_roundtrip(tree, "0xFF")
    end

    test "binary integer" do
      tree = {:grammar, [{:int, 10, :bin, ~c"0b1010"}]}
      assert_roundtrip(tree, "0b1010")
    end

    test "octal integer" do
      tree = {:grammar, [{:int, 63, :oct, ~c"0o77"}]}
      assert_roundtrip(tree, "0o77")
    end

    test "integer with underscores" do
      tree = {:grammar, [{:int, 1_000_000, :dec, ~c"1_000_000"}]}
      assert_roundtrip(tree, "1_000_000")
    end
  end

  describe "literals: floats" do
    test "simple float" do
      tree = {:grammar, [{:float, 1.5, ~c"1.5"}]}
      assert_roundtrip(tree, "1.5")
    end

    test "float with zero fraction" do
      tree = {:grammar, [{:float, 3.0, ~c"3.0"}]}
      assert_roundtrip(tree, "3.0")
    end

    test "float with exponent" do
      tree = {:grammar, [{:float, 1.0e10, ~c"1.0e10"}]}
      assert_roundtrip(tree, "1.0e10")
    end

    test "float with negative exponent" do
      tree = {:grammar, [{:float, 1.0e-5, ~c"1.0e-5"}]}
      assert_roundtrip(tree, "1.0e-5")
    end
  end

  describe "literals: chars" do
    test "simple char" do
      tree = {:grammar, [{:char, ?a, ~c"?a"}]}
      assert_roundtrip(tree, "?a")
    end

    test "escape char newline" do
      tree = {:grammar, [{:char, ?\n, ~c"?\\n"}]}
      assert_roundtrip(tree, "?\\n")
    end

    test "escape char tab" do
      tree = {:grammar, [{:char, ?\t, ~c"?\\t"}]}
      assert_roundtrip(tree, "?\\t")
    end

    test "escape char backslash" do
      tree = {:grammar, [{:char, ?\\, ~c"?\\\\"}]}
      assert_roundtrip(tree, "?\\\\")
    end
  end

  describe "literals: atoms" do
    test "simple atom" do
      tree = {:grammar, [{:atom_lit, :foo}]}
      assert_roundtrip(tree, ":foo")
    end

    test "atom with numbers" do
      tree = {:grammar, [{:atom_lit, :foo123}]}
      assert_roundtrip(tree, ":foo123")
    end

    test "common atoms" do
      for atom <- [:ok, :error] do
        tree = {:grammar, [{:atom_lit, atom}]}
        tokens = TokenCompiler.to_tokens(tree)
        code = Toxic.ToString.to_string(tokens)
        assert code == ":#{atom}"
      end
    end
  end

  describe "literals: booleans and nil" do
    test "true" do
      tree = {:grammar, [{:bool_lit, true}]}
      assert_roundtrip(tree, "true")
    end

    test "false" do
      tree = {:grammar, [{:bool_lit, false}]}
      assert_roundtrip(tree, "false")
    end

    test "nil" do
      tree = {:grammar, [:nil_lit]}
      assert_roundtrip(tree, "nil")
    end
  end

  describe "identifiers" do
    test "simple identifier" do
      tree = {:grammar, [{:identifier, :foo}]}
      assert_roundtrip(tree, "foo")
    end

    test "identifier with numbers" do
      tree = {:grammar, [{:identifier, :foo123}]}
      assert_roundtrip(tree, "foo123")
    end

    test "underscore identifier" do
      tree = {:grammar, [{:identifier, :_foo}]}
      assert_roundtrip(tree, "_foo")
    end
  end

  describe "aliases" do
    test "simple alias" do
      tree = {:grammar, [{:alias, :Foo}]}
      assert_roundtrip(tree, "Foo")
    end

    test "multi-part alias as single atom" do
      # Note: this is a single alias atom, not a dotted path
      tree = {:grammar, [{:alias, :MyApp}]}
      assert_roundtrip(tree, "MyApp")
    end
  end

  describe "multiple forms" do
    test "two literals on separate lines" do
      tree = {:grammar, [{:int, 1, :dec, ~c"1"}, {:int, 2, :dec, ~c"2"}]}
      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      # Should have EOL between forms
      assert code == "1\n2"

      # Verify both parse
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "three mixed literals" do
      tree =
        {:grammar,
         [
           {:atom_lit, :foo},
           {:int, 42, :dec, ~c"42"},
           {:bool_lit, true}
         ]}

      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      assert code == ":foo\n42\ntrue"
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "identifier and alias" do
      tree = {:grammar, [{:identifier, :foo}, {:alias, :Bar}]}
      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      assert code == "foo\nBar"
      assert {:ok, _} = Code.string_to_quoted(code)
    end
  end

  describe "binary operators" do
    test "simple addition" do
      tree =
        {:grammar,
         [
           {:binary_op, {:int, 1, :dec, ~c"1"}, {:op_eol, {:dual_op, :+}, 0}, {:int, 2, :dec, ~c"2"}}
         ]}

      assert_roundtrip(tree, "1 + 2")
    end

    test "simple subtraction" do
      tree =
        {:grammar,
         [
           {:binary_op, {:identifier, :a}, {:op_eol, {:dual_op, :-}, 0}, {:identifier, :b}}
         ]}

      assert_roundtrip(tree, "a - b")
    end

    test "multiplication" do
      tree =
        {:grammar,
         [
           {:binary_op, {:int, 3, :dec, ~c"3"}, {:op_eol, {:mult_op, :*}, 0}, {:int, 4, :dec, ~c"4"}}
         ]}

      assert_roundtrip(tree, "3 * 4")
    end

    test "comparison ==" do
      tree =
        {:grammar,
         [
           {:binary_op, {:identifier, :x}, {:op_eol, {:comp_op, :==}, 0}, {:int, 0, :dec, ~c"0"}}
         ]}

      assert_roundtrip(tree, "x == 0")
    end

    test "boolean and" do
      tree =
        {:grammar,
         [
           {:binary_op, {:bool_lit, true}, {:op_eol, {:and_op, :and}, 0}, {:bool_lit, false}}
         ]}

      assert_roundtrip(tree, "true and false")
    end

    test "pipe operator" do
      tree =
        {:grammar,
         [
           {:binary_op, {:identifier, :a}, {:op_eol, {:pipe_op, :|>}, 0}, {:identifier, :b}}
         ]}

      assert_roundtrip(tree, "a |> b")
    end

    test "binary operator with newline after (op_eol)" do
      # a +\n b
      tree =
        {:grammar,
         [
           {:binary_op, {:identifier, :a}, {:op_eol, {:dual_op, :+}, 1}, {:identifier, :b}}
         ]}

      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      assert code == "a +\nb"
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "nested binary operators" do
      # 1 + 2 * 3
      tree =
        {:grammar,
         [
           {:binary_op, {:int, 1, :dec, ~c"1"}, {:op_eol, {:dual_op, :+}, 0},
            {:binary_op, {:int, 2, :dec, ~c"2"}, {:op_eol, {:mult_op, :*}, 0},
             {:int, 3, :dec, ~c"3"}}}
         ]}

      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      assert code == "1 + 2 * 3"
      assert {:ok, _} = Code.string_to_quoted(code)
    end
  end

  describe "unary operators" do
    test "not operator" do
      tree = {:grammar, [{:unary_op, {:unary_op, :not}, {:bool_lit, true}}]}
      assert_roundtrip(tree, "not true")
    end

    test "bang operator" do
      tree = {:grammar, [{:unary_op, {:unary_op, :!}, {:identifier, :x}}]}
      assert_roundtrip(tree, "! x")
    end

    test "unary plus" do
      tree = {:grammar, [{:unary_op, {:dual_op, :+}, {:int, 5, :dec, ~c"5"}}]}
      assert_roundtrip(tree, "+ 5")
    end

    test "unary minus" do
      tree = {:grammar, [{:unary_op, {:dual_op, :-}, {:int, 5, :dec, ~c"5"}}]}
      assert_roundtrip(tree, "- 5")
    end

    test "unary with binary operator" do
      # not a and b
      tree =
        {:grammar,
         [
           {:binary_op, {:unary_op, {:unary_op, :not}, {:identifier, :a}},
            {:op_eol, {:and_op, :and}, 0}, {:identifier, :b}}
         ]}

      tokens = TokenCompiler.to_tokens(tree)
      code = Toxic.ToString.to_string(tokens)

      assert code == "not a and b"
      assert {:ok, _} = Code.string_to_quoted(code)
    end
  end

  describe "token structure verification" do
    test "integer token has correct structure" do
      tree = {:grammar, [{:int, 42, :dec, ~c"42"}]}
      tokens = TokenCompiler.to_tokens(tree)

      assert [{:int, meta, ~c"42"}] = tokens
      assert {{1, 1}, {1, 3}, 42} = meta
    end

    test "atom token has correct structure" do
      tree = {:grammar, [{:atom_lit, :foo}]}
      tokens = TokenCompiler.to_tokens(tree)

      assert [{:atom, meta, :foo}] = tokens
      assert {{1, 1}, {1, 5}, ~c"foo"} = meta
    end

    test "bool token has correct structure" do
      tree = {:grammar, [{:bool_lit, true}]}
      tokens = TokenCompiler.to_tokens(tree)

      assert [{true, meta}] = tokens
      assert {{1, 1}, {1, 5}, nil} = meta
    end

    test "identifier token has correct structure" do
      tree = {:grammar, [{:identifier, :foo}]}
      tokens = TokenCompiler.to_tokens(tree)

      assert [{:identifier, meta, :foo}] = tokens
      assert {{1, 1}, {1, 4}, ~c"foo"} = meta
    end

    test "EOL token between forms" do
      tree = {:grammar, [{:int, 1, :dec, ~c"1"}, {:int, 2, :dec, ~c"2"}]}
      tokens = TokenCompiler.to_tokens(tree)

      assert [{:int, _, ~c"1"}, {:eol, eol_meta}, {:int, _, ~c"2"}] = tokens
      # EOL meta should have newline count = 1 in extra field
      # Position spans from end of "1" to start of next line
      assert {{1, 2}, {2, 1}, 1} = eol_meta
    end
  end

  describe "capture_int" do
    test "capture &1" do
      tree = {:grammar, [{:capture_int, 1}]}
      assert_roundtrip(tree, "&1")
    end

    test "capture &10 (multi-digit with adhesion)" do
      tree = {:grammar, [{:capture_int, 10}]}
      assert_roundtrip(tree, "&10")
    end

    test "capture_int token structure (adhesion)" do
      tree = {:grammar, [{:capture_int, 5}]}
      tokens = TokenCompiler.to_tokens(tree)

      # Should have capture_op followed by int with no space between
      assert [{:capture_op, amp_meta, :&}, {:int, int_meta, ~c"5"}] = tokens

      # Verify adhesion: int starts right after &
      assert {{1, 1}, {1, 2}, nil} = amp_meta
      assert {{1, 2}, {1, 3}, 5} = int_meta
    end
  end

  describe "call_parens" do
    test "simple call foo()" do
      tree = {:grammar, [{:call_parens, {:paren_identifier, :foo}, []}]}
      assert_roundtrip(tree, "foo()")
    end

    test "call with one argument foo(1)" do
      tree = {:grammar, [{:call_parens, {:paren_identifier, :foo}, [{:int, 1, :dec, ~c"1"}]}]}
      assert_roundtrip(tree, "foo(1)")
    end

    test "call with two arguments foo(1, 2)" do
      tree =
        {:grammar,
         [
           {:call_parens, {:paren_identifier, :foo},
            [{:int, 1, :dec, ~c"1"}, {:int, 2, :dec, ~c"2"}]}
         ]}

      assert_roundtrip(tree, "foo(1, 2)")
    end

    test "call with three arguments foo(a, b, c)" do
      tree =
        {:grammar,
         [
           {:call_parens, {:paren_identifier, :foo},
            [{:identifier, :a}, {:identifier, :b}, {:identifier, :c}]}
         ]}

      assert_roundtrip(tree, "foo(a, b, c)")
    end

    test "call_parens token structure (adhesion)" do
      tree = {:grammar, [{:call_parens, {:paren_identifier, :foo}, [{:int, 1, :dec, ~c"1"}]}]}
      tokens = TokenCompiler.to_tokens(tree)

      # Should have: paren_identifier, (, int, )
      assert [{:paren_identifier, id_meta, :foo}, {:"(", open_meta}, {:int, _, _}, {:")", _}] =
               tokens

      # Verify adhesion: ( starts right after foo
      assert {{1, 1}, {1, 4}, ~c"foo"} = id_meta
      assert {{1, 4}, {1, 5}, nil} = open_meta
    end
  end

  describe "dot_call" do
    test "dot call foo.(1)" do
      tree =
        {:grammar, [{:call_parens, {:dot_call, {:identifier, :foo}}, [{:int, 1, :dec, ~c"1"}]}]}

      assert_roundtrip(tree, "foo.(1)")
    end

    test "dot call foo.()" do
      tree = {:grammar, [{:call_parens, {:dot_call, {:identifier, :foo}}, []}]}
      assert_roundtrip(tree, "foo.()")
    end

    test "dot call with multiple args foo.(a, b)" do
      tree =
        {:grammar,
         [{:call_parens, {:dot_call, {:identifier, :foo}}, [{:identifier, :a}, {:identifier, :b}]}]}

      assert_roundtrip(tree, "foo.(a, b)")
    end

    test "dot_call token structure (adhesion)" do
      tree = {:grammar, [{:call_parens, {:dot_call, {:identifier, :foo}}, []}]}
      tokens = TokenCompiler.to_tokens(tree)

      # Should have: identifier, ., (, )
      assert [{:identifier, id_meta, :foo}, {:., dot_meta}, {:"(", open_meta}, {:")", _}] = tokens

      # Verify adhesion: . starts right after foo, ( starts right after .
      assert {{1, 1}, {1, 4}, ~c"foo"} = id_meta
      assert {{1, 4}, {1, 5}, nil} = dot_meta
      assert {{1, 5}, {1, 6}, nil} = open_meta
    end
  end

  describe "call_no_parens_one" do
    test "simple no-parens call foo bar" do
      tree = {:grammar, [{:call_no_parens_one, {:identifier, :foo}, {:identifier, :bar}}]}
      assert_roundtrip(tree, "foo bar")
    end

    test "no-parens call with integer foo 42" do
      tree = {:grammar, [{:call_no_parens_one, {:identifier, :foo}, {:int, 42, :dec, ~c"42"}}]}
      assert_roundtrip(tree, "foo 42")
    end

    test "no-parens call with atom foo :bar" do
      tree = {:grammar, [{:call_no_parens_one, {:identifier, :foo}, {:atom_lit, :bar}}]}
      assert_roundtrip(tree, "foo :bar")
    end
  end

  describe "mixed calls" do
    test "capture in call foo(&1)" do
      tree = {:grammar, [{:call_parens, {:paren_identifier, :foo}, [{:capture_int, 1}]}]}
      assert_roundtrip(tree, "foo(&1)")
    end

    test "call as argument bar(foo(1))" do
      tree =
        {:grammar,
         [
           {:call_parens, {:paren_identifier, :bar},
            [{:call_parens, {:paren_identifier, :foo}, [{:int, 1, :dec, ~c"1"}]}]}
         ]}

      assert_roundtrip(tree, "bar(foo(1))")
    end
  end

  describe "fn_single" do
    test "fn with no arguments -> nil end" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, :empty, nil, :nil_lit}]}
         ]}

      assert_roundtrip(tree, "fn -> nil end")
    end

    test "fn with single identifier pattern -> body end" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, {:single, {:identifier, :x}}, nil, {:identifier, :x}}]}
         ]}

      assert_roundtrip(tree, "fn x -> x end")
    end

    test "fn with literal body" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, :empty, nil, {:int, 42, :dec, ~c"42"}}]}
         ]}

      assert_roundtrip(tree, "fn -> 42 end")
    end

    test "fn with atom body" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, :empty, nil, {:atom_lit, :ok}}]}
         ]}

      assert_roundtrip(tree, "fn -> :ok end")
    end

    test "fn with single pattern and expression body" do
      tree =
        {:grammar,
         [
           {:fn_single,
            [
              {:stab_clause, {:single, {:identifier, :a}}, nil,
               {:binary_op, {:identifier, :a}, {:op_eol, {:dual_op, :+}, 0},
                {:int, 1, :dec, ~c"1"}}}
            ]}
         ]}

      assert_roundtrip(tree, "fn a -> a + 1 end")
    end

    test "fn_single token structure" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, :empty, nil, :nil_lit}]}
         ]}

      tokens = TokenCompiler.to_tokens(tree)

      # Should have: fn, ->, nil, end
      assert [{:fn, fn_meta}, {:stab_op, stab_meta, :->}, {nil, nil_meta}, {:end, end_meta}] =
               tokens

      # Verify positions
      assert {{1, 1}, {1, 3}, nil} = fn_meta
      assert {{1, 4}, {1, 6}, nil} = stab_meta
      assert {{1, 7}, {1, 10}, nil} = nil_meta
      assert {{1, 11}, {1, 14}, nil} = end_meta
    end

    test "fn with pattern token structure" do
      tree =
        {:grammar,
         [
           {:fn_single, [{:stab_clause, {:single, {:identifier, :x}}, nil, {:identifier, :x}}]}
         ]}

      tokens = TokenCompiler.to_tokens(tree)

      # Should have: fn, x, ->, x, end
      assert [
               {:fn, _},
               {:identifier, _, :x},
               {:stab_op, _, :->},
               {:identifier, _, :x},
               {:end, _}
             ] = tokens
    end
  end

  describe "fn_single in expressions" do
    test "fn as call argument" do
      tree =
        {:grammar,
         [
           {:call_parens, {:paren_identifier, :foo},
            [{:fn_single, [{:stab_clause, :empty, nil, :nil_lit}]}]}
         ]}

      assert_roundtrip(tree, "foo(fn -> nil end)")
    end

    test "fn with call in body" do
      tree =
        {:grammar,
         [
           {:fn_single,
            [
              {:stab_clause, {:single, {:identifier, :x}}, nil,
               {:call_parens, {:paren_identifier, :foo}, [{:identifier, :x}]}}
            ]}
         ]}

      assert_roundtrip(tree, "fn x -> foo(x) end")
    end
  end
end
