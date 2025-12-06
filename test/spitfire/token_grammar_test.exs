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
end
