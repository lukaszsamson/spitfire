defmodule SpitfireRangesTest do
  use ExUnit.Case, async: false

  setup do
    # Enable ranges for these tests (disabled globally in test_helper.exs)
    Application.put_env(:spitfire, :strip_ranges, false)
    on_exit(fn -> Application.put_env(:spitfire, :strip_ranges, true) end)
    :ok
  end

  # Helper to extract range from AST metadata
  defp get_range({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :range)
  end

  defp get_range(_), do: nil

  # Helper to assert a range matches expected coordinates
  defp assert_range(ast, expected_range) do
    actual_range = get_range(ast)
    assert actual_range == expected_range,
           "Expected range #{inspect(expected_range)}, got #{inspect(actual_range)}"
  end

  # Helper for position comparison
  defp pos_leq?({l1, c1}, {l2, c2}), do: l1 < l2 or (l1 == l2 and c1 <= c2)

  # Test encoder that captures literal metadata
  defp test_encoder do
    fn lit, meta ->
      send(self(), {:lit_meta, lit, meta})
      {:ok, {:__literal__, meta, [lit]}}
    end
  end

  describe "Basic Literal Ranges" do
    test "integer literal" do
      code = "123"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, 123, meta}
      assert meta[:range] == {{1, 1}, {1, 4}}
      assert_range(ast, {{1, 1}, {1, 4}})
    end

    test "float literal" do
      code = "1.5"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, 1.5, meta}
      assert meta[:range] == {{1, 1}, {1, 4}}
      assert_range(ast, {{1, 1}, {1, 4}})
    end

    test "atom literal" do
      code = ":foo"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, :foo, meta}
      assert meta[:range] == {{1, 1}, {1, 5}}
      assert_range(ast, {{1, 1}, {1, 5}})
    end

    test "string literal" do
      code = ~S("hello")
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, "hello", meta}
      assert meta[:range] == {{1, 1}, {1, 8}}
      assert_range(ast, {{1, 1}, {1, 8}})
    end

    test "charlist literal" do
      code = ~S('hello')
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, ~c"hello", meta}
      assert meta[:range] == {{1, 1}, {1, 8}}
      assert_range(ast, {{1, 1}, {1, 8}})
    end

    test "boolean true literal" do
      code = "true"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, true, meta}
      assert meta[:range] == {{1, 1}, {1, 5}}
      assert_range(ast, {{1, 1}, {1, 5}})
    end

    test "boolean false literal" do
      code = "false"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, false, meta}
      assert meta[:range] == {{1, 1}, {1, 6}}
      assert_range(ast, {{1, 1}, {1, 6}})
    end

    test "nil literal" do
      code = "nil"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, nil, meta}
      assert meta[:range] == {{1, 1}, {1, 4}}
      assert_range(ast, {{1, 1}, {1, 4}})
    end
  end

  describe "Container Literal Ranges" do
    test "empty list" do
      code = "[]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, [], list_meta}
      assert list_meta[:range] == {{1, 1}, {1, 3}}
      assert_range(ast, {{1, 1}, {1, 3}})
    end

    test "list with elements" do
      code = "[1, 23]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Should receive meta for elements first
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:range] == {{1, 2}, {1, 3}}

      assert_received {:lit_meta, 23, meta2}
      assert meta2[:range] == {{1, 5}, {1, 7}}

      # Then the container
      assert_received {:lit_meta, [_, _], list_meta}
      assert list_meta[:range] == {{1, 1}, {1, 8}}
      assert_range(ast, {{1, 1}, {1, 8}})
    end

    test "empty tuple (2-element path)" do
      code = "{}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Empty tuples don't go through literal encoder in the 2-tuple path
      assert_range(ast, {{1, 1}, {1, 3}})
    end

    test "2-tuple with elements" do
      code = "{1, 2}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Elements
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:range] == {{1, 2}, {1, 3}}

      assert_received {:lit_meta, 2, meta2}
      assert meta2[:range] == {{1, 5}, {1, 6}}

      # Container (2-tuples use literal encoder)
      assert_received {:lit_meta, {_, _}, tuple_meta}
      assert tuple_meta[:range] == {{1, 1}, {1, 7}}
      assert_range(ast, {{1, 1}, {1, 7}})
    end

    test "3-tuple with elements (structural form)" do
      code = "{1, 2, 3}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Elements are still encoded
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:range] == {{1, 2}, {1, 3}}

      assert_received {:lit_meta, 2, meta2}
      assert meta2[:range] == {{1, 5}, {1, 6}}

      assert_received {:lit_meta, 3, meta3}
      assert meta3[:range] == {{1, 8}, {1, 9}}

      # Container uses structural :{} form, should still have range
      assert_range(ast, {{1, 1}, {1, 10}})
    end

    test "empty map" do
      code = "%{}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 4}})
    end

    test "map with elements" do
      code = "%{a: 1}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Key and value
      assert_received {:lit_meta, :a, key_meta}
      assert key_meta[:range] == {{1, 3}, {1, 5}}

      assert_received {:lit_meta, 1, val_meta}
      assert val_meta[:range] == {{1, 6}, {1, 7}}

      # Container
      assert_range(ast, {{1, 1}, {1, 8}})
    end

    test "empty struct" do
      code = "%Foo{}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Struct node should have range
      assert_range(ast, {{1, 1}, {1, 7}})

      # Inner map should also have range
      {:%, _meta, [_type, inner_map]} = ast
      assert_range(inner_map, {{1, 5}, {1, 7}})
    end

    test "struct with elements" do
      code = "%Foo{a: 1}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Key and value
      assert_received {:lit_meta, :a, key_meta}
      assert key_meta[:range] == {{1, 6}, {1, 8}}

      assert_received {:lit_meta, 1, val_meta}
      assert val_meta[:range] == {{1, 9}, {1, 10}}

      # Struct node
      assert_range(ast, {{1, 1}, {1, 11}})

      # Inner map
      {:%, _meta, [_type, inner_map]} = ast
      assert_range(inner_map, {{1, 5}, {1, 11}})
    end

    test "empty bitstring" do
      code = "<<>>"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 5}})
    end

    test "bitstring with elements" do
      code = "<<1, 2>>"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Elements
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:range] == {{1, 3}, {1, 4}}

      assert_received {:lit_meta, 2, meta2}
      assert meta2[:range] == {{1, 6}, {1, 7}}

      # Container
      assert_range(ast, {{1, 1}, {1, 9}})
    end

    test "nested containers" do
      code = "[{1, 2}]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Inner tuple elements
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:range] == {{1, 3}, {1, 4}}

      assert_received {:lit_meta, 2, meta2}
      assert meta2[:range] == {{1, 6}, {1, 7}}

      # Inner tuple
      assert_received {:lit_meta, {_, _}, tuple_meta}
      assert tuple_meta[:range] == {{1, 2}, {1, 8}}

      # Outer list
      assert_received {:lit_meta, [_], list_meta}
      assert list_meta[:range] == {{1, 1}, {1, 9}}
      assert_range(ast, {{1, 1}, {1, 9}})
    end
  end

  describe "Keyword key ranges include colon" do
    test "map keyword key includes colon" do
      code = "%{a: 1}"
      {:ok, _ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, :a, meta}
      assert meta[:range] == {{1, 3}, {1, 5}}
    end

    test "bracketless keyword key includes colon" do
      code = "a: 1"
      {:ok, _ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, :a, meta}
      assert meta[:range] == {{1, 1}, {1, 3}}
    end
  end

  describe "Non-Literal Leaf Ranges" do
    test "identifier" do
      code = "foo"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 4}})
    end

    test "simple alias" do
      code = "Foo"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 4}})
    end

    test "multi-segment alias" do
      code = "Foo.Bar"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # The full alias should span the entire range
      assert_range(ast, {{1, 1}, {1, 8}})
    end
  end

  describe "Operator Ranges" do
    test "binary operator" do
      code = "1 + 23"

      {:ok, {:+, meta, [lhs, rhs]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert meta[:range] == {{1, 1}, {1, 7}}
      assert_range(lhs, {{1, 1}, {1, 2}})
      assert_range(rhs, {{1, 5}, {1, 7}})
    end

    test "unary operator" do
      code = "-1"

      {:ok, {:-, meta, [operand]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert meta[:range] == {{1, 1}, {1, 3}}
      assert_range(operand, {{1, 2}, {1, 3}})
    end

    test "range operator with step" do
      code = "1..2//3"

      {:ok, {:..//, meta, [lhs, mid, rhs]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert meta[:range] == {{1, 1}, {1, 8}}
      assert_range(lhs, {{1, 1}, {1, 2}})
      assert_range(mid, {{1, 4}, {1, 5}})
      assert_range(rhs, {{1, 7}, {1, 8}})
    end

    test "pipe operator" do
      code = "1 |> foo"

      {:ok, {:|>, meta, [lhs, rhs_like]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      rhs =
        case rhs_like do
          [inner | _] -> inner
          other -> other
        end

      assert meta[:range] == {{1, 1}, {1, 9}}
      assert_range(lhs, {{1, 1}, {1, 2}})
      assert_range(rhs, {{1, 6}, {1, 9}})
    end

    test "assoc operator metadata" do
      code = "%{1 => 2}"

      {:ok, {:%{}, _meta, [{key, value}]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(key, {{1, 3}, {1, 4}})
      assert_range(value, {{1, 8}, {1, 9}})

      {:assoc, assoc_meta} = Enum.find(elem(key, 1), fn {k, _} -> k == :assoc end)
      assert Keyword.get(assoc_meta, :range) == {{1, 3}, {1, 9}}
    end

    test "nested binary operator range" do
      code = "1 + 2 + 3"
      {:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Outer +: (1 + 2) + 3
      assert meta[:range] == {{1, 1}, {1, 10}}
      assert get_range(rhs) == {{1, 9}, {1, 10}} # 3

      # Inner +: 1 + 2
      {:+, inner_meta, [inner_lhs, inner_rhs]} = lhs
      assert inner_meta[:range] == {{1, 1}, {1, 6}}
      assert get_range(inner_lhs) == {{1, 1}, {1, 2}} # 1
      assert get_range(inner_rhs) == {{1, 5}, {1, 6}} # 2
    end

    test "range operator range" do
      code = "1..2"
      {:ok, {:.., meta, [lhs, rhs]}} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert meta[:range] == {{1, 1}, {1, 5}}
      assert get_range(lhs) == {{1, 1}, {1, 2}}
      assert get_range(rhs) == {{1, 4}, {1, 5}}
    end

    test "not in operator range" do
      code = "1 not in [2]"
      {:ok, {:not, not_meta, [{:in, in_meta, [lhs, rhs]}]}} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert not_meta[:range] == {{1, 1}, {1, 13}}
      # The inner :in node covers the full expression "1 ... [2]" because it has lhs and rhs as children
      assert in_meta[:range] == {{1, 1}, {1, 13}}
      assert in_meta[:line] == 1
      assert in_meta[:column] == 7 # Points to "in"
      assert get_range(lhs) == {{1, 1}, {1, 2}}
      assert get_range(rhs) == {{1, 10}, {1, 13}}
    end
  end

  describe "Range Invariants" do
    # Helper to walk AST and validate range invariants
    defp assert_range_invariants(ast, parent_range \\ nil) do
      case ast do
        {_form, meta, args} when is_list(meta) and is_list(args) ->
          range = Keyword.get(meta, :range)

          # Some internal nodes (like Kernel.to_string calls in interpolations) may not have ranges
          # Only check parent containment and sibling relationships if this node has a range
          if range do
            # Parent containment: parent range should contain child range
            if parent_range do
              {p_start, p_end} = parent_range
              {c_start, c_end} = range
              assert pos_leq?(p_start, c_start),
                     "Parent start #{inspect(p_start)} > child start #{inspect(c_start)}"
              assert pos_leq?(c_end, p_end),
                     "Child end #{inspect(c_end)} > parent end #{inspect(p_end)}"
            end

            # Get child ranges
            child_ranges =
              args
              |> Enum.map(&assert_range_invariants(&1, range))
              |> Enum.filter(& &1)

            # Sibling non-overlap: adjacent siblings shouldn't overlap
            child_ranges
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.each(fn [r1, r2] ->
              {_s1, e1} = r1
              {s2, _e2} = r2
              assert pos_leq?(e1, s2),
                     "Sibling ranges overlap: #{inspect(r1)} and #{inspect(r2)}"
            end)
          else
            # Node without range - still check children but don't enforce containment
            args
            |> Enum.map(&assert_range_invariants(&1, parent_range))
            |> Enum.filter(& &1)
          end

          range

        list when is_list(list) ->
          Enum.each(list, &assert_range_invariants(&1, parent_range))
          nil

        _ ->
          nil
      end
    end

    test "single expression respects invariants" do
      code = "1 + 2"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range_invariants(ast)
    end

    test "nested expression respects invariants" do
      code = "[1, {2, 3}]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range_invariants(ast)
    end

    test "complex nested structure respects invariants" do
      code = "%Foo{bar: [1, {2, 3}]}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range_invariants(ast)
    end

    test "multi-line code respects invariants" do
      code = """
      [
        1,
        2
      ]
      """
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range_invariants(ast)
    end

    test "full module structure respects invariants" do
      code = """
      defmodule Foo do
        def bar(a, b) do
          if a + b > 10 do
            "result: \#{a + b}"
          else
            :error
          end
        end
      end
      """
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert_range_invariants(ast)
    end

    test "root node spans entire document" do
      code = "1 + 2\n"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should start at {1,1} and end at EOF
      assert_range(ast, {{1, 1}, {2, 1}})
    end

    test "empty source still has start range" do
      {:ok, ast} = Spitfire.parse("", tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 1}})
      assert_range_invariants(ast)
    end

    test "comment-only source still has start range" do
      code = "# comment"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # TODO: should it span a full document?
      assert_range(ast, {{1, 1}, {1, 1}})
      assert_range_invariants(ast)
    end
  end

  describe "Edge Cases" do
    test "malformed list with missing closer" do
      code = "[1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Should still have a range even with error recovery
      range = get_range(ast)
      assert range != nil

      # Should still respect invariants
      assert_range_invariants(ast)
    end

    test "malformed tuple with missing closer" do
      code = "{1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      range = get_range(ast)
      assert range != nil
      assert_range_invariants(ast)
    end

    test "malformed map with missing closer" do
      code = "%{a: 1"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      range = get_range(ast)
      assert range != nil
      assert_range_invariants(ast)
    end

    test "malformed bitstring with missing closer" do
      code = "<<1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      range = get_range(ast)
      assert range != nil
      assert_range_invariants(ast)
    end

    test "deeply nested structures respect invariants" do
      code = "[[1, 2], [3, 4]]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Deeply nested structures should still have ranges and respect invariants
      range = get_range(ast)
      assert range != nil
      assert_range_invariants(ast)
    end

    test "mixed valid and invalid constructs" do
      code = "[1, 2] + {3, 4"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Valid part and invalid part should both have ranges
      range = get_range(ast)
      assert range != nil
      assert_range_invariants(ast)
    end

    test "deeply nested valid code respects invariants" do
      code = "[[[[1, 2]]]]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      range = get_range(ast)
      assert range == {{1, 1}, {1, 13}}
      assert_range_invariants(ast)
    end

    test "root coverage for invalid code" do
      code = "[1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should have a range even with errors (if parser can provide it)
      range = get_range(ast)
      if range do
        {{start_line, start_col}, {end_line, _end_col}} = range
        assert start_line == 1
        assert start_col == 1
        # EOF should be tracked properly
        assert end_line >= 1
        assert_range_invariants(ast)
      end
    end

    test "literal at different starting position" do
      code = "  123"
      {:ok, _ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_received {:lit_meta, 123, meta}
      assert meta[:range] == {{1, 3}, {1, 6}}
    end

    test "multi-line literal" do
      code = """
      [
        1,
        2
      ]
      """
      {:ok, _ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Elements on different lines
      assert_received {:lit_meta, 1, meta1}
      assert meta1[:line] == 2

      assert_received {:lit_meta, 2, meta2}
      assert meta2[:line] == 3

      # Container spans multiple lines
      assert_received {:lit_meta, [_, _], list_meta}
      {{start_line, _}, {end_line, _}} = list_meta[:range]
      assert start_line == 1
      assert end_line == 4
    end

    test "literal with whitespace" do
      code = "[ 1 , 2 ]"
      {:ok, _ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Container should span including brackets
      assert_received {:lit_meta, [_, _], list_meta}
      assert list_meta[:range] == {{1, 1}, {1, 10}}
    end
  end

  describe "Operator Edge Cases" do
    test "grouped expression range includes parentheses" do
      code = "(1 + 2)"
      {:ok, {:+, meta, [lhs, rhs]}} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range({:+, meta, [lhs, rhs]}, {{1, 1}, {1, 8}})
      assert_range(lhs, {{1, 2}, {1, 3}})
      assert_range(rhs, {{1, 6}, {1, 7}})
    end

    test "do block range spans do...end" do
      code = "foo do :ok end"
      {:ok, {:foo, meta, [_clauses]} = ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(ast, {{1, 1}, {1, 15}})
      assert get_range({:foo, meta, []}) == {{1, 1}, {1, 15}}
    end

    test "anonymous function range spans fn...end" do
      code = "fn x -> x end"
      {:ok, {:fn, meta, _clauses} = ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(ast, {{1, 1}, {1, 14}})
      assert meta[:range] == {{1, 1}, {1, 14}}
    end

    test "__block__ range derives from children" do
      code = "1\n2"
      {:ok, {:__block__, meta, [one, two]} = ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(ast, {{1, 1}, {2, 2}})
      assert_range(one, {{1, 1}, {1, 2}})
      assert_range(two, {{2, 1}, {2, 2}})
      assert meta[:range] == {{1, 1}, {2, 2}}
    end

    test "paren call range includes callee, args, and parens" do
      code = "foo(1,23)"

      {:ok, {:foo, meta, [arg1, arg2]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range({:foo, meta, [arg1, arg2]}, {{1, 1}, {1, 10}})
      assert_range(arg1, {{1, 5}, {1, 6}})
      assert_range(arg2, {{1, 7}, {1, 9}})
    end

    test "no-parens call range spans callee and trailing args" do
      code = "foo 1, 23"

      {:ok, {:foo, meta, [arg1, arg2]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range({:foo, meta, [arg1, arg2]}, {{1, 1}, {1, 10}})
      assert_range(arg1, {{1, 5}, {1, 6}})
      assert_range(arg2, {{1, 8}, {1, 10}})
    end

    test "remote paren call range" do
      code = "Foo.bar(1)"

      {:ok, {{:., _dot_meta, [alias_ast, :bar]} = callee, call_meta, [arg]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(callee, {{1, 1}, {1, 11}})
      assert_range({callee, call_meta, [arg]}, {{1, 1}, {1, 11}})
      assert_range(alias_ast, {{1, 1}, {1, 4}})
      assert_range(arg, {{1, 9}, {1, 10}})
    end

    test "dot call operator range" do
      code = "foo.(1)"

      {:ok, {{:., dot_meta, [_lhs]}, call_meta, [arg]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range({:., dot_meta, []}, {{1, 1}, {1, 8}})
      assert_range({{:., dot_meta, []}, call_meta, [arg]}, {{1, 1}, {1, 8}})
      assert_range(arg, {{1, 6}, {1, 7}})
    end

    test "access expression range" do
      code = "foo[:bar]"

      {:ok, {{:., meta, [Access, :get]} = callee, _meta2, [lhs, rhs]}} =
        Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range({callee, meta, [lhs, rhs]}, {{1, 1}, {1, 10}})
      assert_range(lhs, {{1, 1}, {1, 4}})
      assert_range(rhs, {{1, 5}, {1, 9}})
    end

    test "nested binary operators with precedence" do
      code = "1 + 2 * 3"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should be + operator
      assert {:+, _meta, [lhs, rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 10}})

      # lhs is literal 1
      assert lhs == 1

      # rhs is * operator
      assert {:*, _mul_meta, [_mul_lhs, _mul_rhs]} = rhs
      # The * operator range should exist
      assert get_range(rhs) != nil

      # Verify invariants hold
      assert_range_invariants(ast)
    end

    test "grouped expression with operators" do
      code = "(1 + 2) * 3"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should be * operator
      assert {:*, _meta, [lhs, _rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 12}})

      # lhs is grouped + expression
      assert {:+, _plus_meta, _} = lhs
      assert get_range(lhs) != nil

      # Verify invariants hold
      assert_range_invariants(ast)
    end

    test "chained operators of same precedence" do
      code = "1 + 2 + 3 + 4"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should be nested + operators
      assert {:+, _meta, _args} = ast
      assert_range(ast, {{1, 1}, {1, 14}})

      # Verify invariants hold
      assert_range_invariants(ast)
    end

    test "chained pipe operators" do
      code = "a |> b |> c"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should be nested |> operators
      assert {:|>, _meta, _args} = ast
      assert_range(ast, {{1, 1}, {1, 12}})

      # Verify invariants hold
      assert_range_invariants(ast)
    end

    test "chained pipes with function calls" do
      code = "1 |> foo() |> bar()"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should be pipe
      assert {:|>, _meta, _args} = ast
      assert_range(ast, {{1, 1}, {1, 20}})

      # Note: Function call ranges will be added in Phase 4
      # For now, just verify the pipe operators have ranges
      assert get_range(ast) != nil
    end

    test "range expression with identifiers" do
      code = "a..b"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should be range operator
      assert {:.., _meta, [_lhs, _rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 5}})

      # Verify invariants hold
      assert_range_invariants(ast)
    end

    test "incomplete binary operation" do
      code = "1 + "
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range even with error
      # Note: Error blocks may not have ranges until Phase 5 is implemented
      _range = get_range(ast)

      # The operator node itself should have a range
      assert {:+, meta, _} = ast
      assert meta[:range] != nil
    end

    test "incomplete unary operation" do
      code = "- "
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # The operator node should have a range
      # Note: Error blocks may not have ranges until Phase 5 is implemented
      assert {:-, meta, _} = ast
      assert meta[:range] != nil
    end

    test "incomplete pipe operation" do
      code = "1 |> "
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # The pipe operator should have a range
      # Note: Error blocks may not have ranges until Phase 5 is implemented
      assert {:|>, meta, _} = ast
      assert meta[:range] != nil
    end

    test "unary and binary operators combined" do
      code = "-1 + 2"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root is + operator
      assert {:+, _meta, [lhs, _rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 7}})

      # lhs is unary - operator
      assert {:-, _neg_meta, [_operand]} = lhs
      assert get_range(lhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "module attribute with binary operator" do
      code = "@foo + 1"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root is + operator
      assert {:+, _meta, [lhs, _rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 9}})

      # lhs is @ operator
      assert {:@, _attr_meta, _} = lhs
      assert get_range(lhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "capture operators with binary operator" do
      code = "&1 + &2"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root is + operator
      assert {:+, _meta, [lhs, rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 8}})

      # Both operands are captures
      assert {:&, _, _} = lhs
      assert {:&, _, _} = rhs
      assert get_range(lhs) != nil
      assert get_range(rhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "match operator with arithmetic" do
      code = "a = b + c"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root is = operator
      assert {:=, _meta, [_lhs, rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 10}})

      # rhs is + operator
      assert {:+, _plus_meta, _} = rhs
      assert get_range(rhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "boolean operator precedence" do
      code = "a or b and c"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should respect precedence (and binds tighter than or)
      assert {:or, _meta, [_lhs, rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 13}})

      # rhs should be 'and' expression
      assert {:and, _and_meta, _} = rhs
      assert get_range(rhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "comparison with boolean operators" do
      code = "1 < 2 and 3 > 4"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root is 'and' operator
      assert {:and, _meta, [lhs, rhs]} = ast
      assert_range(ast, {{1, 1}, {1, 16}})

      # Both operands are comparison operators
      assert {:<, _lt_meta, _} = lhs
      assert {:>, _gt_meta, _} = rhs
      assert get_range(lhs) != nil
      assert get_range(rhs) != nil

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "operator split across lines" do
      code = "1 +\n  2"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should be + operator
      assert {:+, _meta, [_lhs, _rhs]} = ast

      # Range should span both lines
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 2

      # Verify invariants
      assert_range_invariants(ast)
    end

    test "pipe split across lines" do
      code = "a\n|> b"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should be pipe operator
      assert {:|>, _meta, _args} = ast

      # Range should span both lines
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 2

      # Verify invariants
      assert_range_invariants(ast)
    end
  end

  describe "Call and Container Edge Cases" do
    test "nested calls" do
      code = "foo(bar(baz()))"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Outer call
      assert_range(ast, {{1, 1}, {1, 16}})

      # Should have nested structure
      assert_range_invariants(ast)
    end

    test "calls with keyword arguments" do
      code = "foo(a: 1, b: 2)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Call should span entire expression
      assert_range(ast, {{1, 1}, {1, 16}})
      assert_range_invariants(ast)
    end

    test "remote call with multiple arguments" do
      code = "Foo.bar(1, 2, 3)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span from Foo to closing paren
      assert_range(ast, {{1, 1}, {1, 17}})
      assert_range_invariants(ast)
    end

    test "chained dot access" do
      code = "a.b.c.d()"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span entire chain
      assert_range(ast, {{1, 1}, {1, 10}})
      assert_range_invariants(ast)
    end

    test "access with multiple keys" do
      code = "foo[a][b][c]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span entire access chain
      assert_range(ast, {{1, 1}, {1, 13}})
      assert_range_invariants(ast)
    end

    test "nested containers" do
      code = "[%{a: {1, 2}}]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Outer list
      assert_received {:lit_meta, [_], list_meta}
      assert list_meta[:range] == {{1, 1}, {1, 15}}

      # Should have proper nesting
      assert_range_invariants(ast)
    end

    test "containers in call arguments" do
      code = "foo([1, 2], %{a: 3})"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Call should span everything
      assert_range(ast, {{1, 1}, {1, 21}})

      # Verify nested containers have ranges
      assert_range_invariants(ast)
    end

    test "multi-line container" do
      code = """
      [
        1,
        2,
        3
      ]
      """
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Should span from line 1 to line 6 (heredoc adds trailing newline)
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 6

      assert_range_invariants(ast)
    end

    test "call with trailing do-block (no parens)" do
      code = "if true do\n  1\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span from 'if' to 'end'
      {{start_line, start_col}, {end_line, _end_col}} = get_range(ast)
      assert start_line == 1
      assert start_col == 1
      assert end_line == 3

      assert_range_invariants(ast)
    end

    test "incomplete call" do
      code = "foo("
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "missing dot rhs" do
      code = "foo."
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "unclosed access bracket" do
      code = "foo["
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "remote call with no args" do
      code = "Foo.bar()"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 10}})
      assert_range_invariants(ast)
    end

    test "local call with no args" do
      code = "foo()"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 6}})
      assert_range_invariants(ast)
    end

    test "no-parens call with single arg" do
      code = "foo 1"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 6}})
      assert_range_invariants(ast)
    end

    test "no-parens call with multiple args" do
      code = "foo 1, 2, 3"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 12}})
      assert_range_invariants(ast)
    end

    test "access with keyword list" do
      code = "foo[bar: 1, baz: 2]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 20}})
      assert_range_invariants(ast)
    end

    test "deeply nested containers" do
      code = "[[[1]]]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(ast, {{1, 1}, {1, 8}})
      assert_range_invariants(ast)
    end

    test "mixed container types" do
      code = "{[1, 2], %{a: 3}, <<4>>}"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert_range(ast, {{1, 1}, {1, 25}})
      assert_range_invariants(ast)
    end
  end

  describe "Calls and Blocks Ranges" do
    test "paren call range" do
      code = "foo(1, 2)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end

    test "no-paren call range" do
      code = "foo 1, 2"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end

    test "dot call range" do
      code = "Mod.fun(1)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end

    test "do block range" do
      code = "if true do :ok end"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end

    test "anon function range" do
      code = "fn -> :ok end"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end

    test "grouped expression range" do
      code = "(1 + 2)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)
      assert get_range(ast) != nil
    end
  end

  describe "Block and Special Form Edge Cases" do
    test "multi-line __block__ derives range from children" do
      code = "1\n2\n3"
      {:ok, {:__block__, _meta, [one, two, three]} = ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Block should span all three lines
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 3

      # Children should have correct ranges
      assert_range(one, {{1, 1}, {1, 2}})
      assert_range(two, {{2, 1}, {2, 2}})
      assert_range(three, {{3, 1}, {3, 2}})

      assert_range_invariants(ast)
    end

    test "nested parentheses" do
      code = "((1 + 2))"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Outer parens should span entire expression
      assert_range(ast, {{1, 1}, {1, 10}})
      assert_range_invariants(ast)
    end

    test "empty parentheses" do
      code = "()"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should have range even though empty
      assert get_range(ast) != nil
      assert_range_invariants(ast)
    end

    test "multi-line grouped expression" do
      code = "(\n  1 + 2\n)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span all three lines
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 3

      assert_range_invariants(ast)
    end

    test "case with multiple clauses" do
      code = "case x do\n  1 -> :a\n  2 -> :b\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span from 'case' to 'end'
      {{start_line, start_col}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert start_col == 1
      assert end_line == 4

      assert_range_invariants(ast)
    end

    test "nested do-blocks" do
      code = "if a do\n  if b do\n    c\n  end\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Outer if should span all lines
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 5

      assert_range_invariants(ast)
    end

    test "do-block with else clause" do
      code = "if true do\n  :ok\nelse\n  :error\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span entire construct
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 5

      assert_range_invariants(ast)
    end

    test "anonymous function with multiple clauses" do
      code = "fn\n  1 -> :a\n  2 -> :b\nend"
      {:ok, {:fn, _meta, _clauses} = ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Should span from 'fn' to 'end'
      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 4

      assert_range_invariants(ast)
    end

    test "anonymous function with pattern matching" do
      code = "fn {a, b} -> a + b end"
      {:ok, {:fn, _meta, _clauses} = ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 23}})
      assert_range_invariants(ast)
    end

    test "nested anonymous functions" do
      code = "fn -> fn -> :ok end end"
      {:ok, {:fn, _meta, _clauses} = ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 24}})
      assert_range_invariants(ast)
    end

    test "multi-line anonymous function" do
      code = "fn x ->\n  x + 1\nend"
      {:ok, {:fn, _meta, _clauses} = ast} = Spitfire.parse(code, tokenizer: :toxic)

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 3

      assert_range_invariants(ast)
    end

    test "do-block with multiple expression types" do
      code = "if true do\n  a = 1\n  b = 2\n  a + b\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 5

      assert_range_invariants(ast)
    end

    test "try-rescue block" do
      code = "try do\n  :ok\nrescue\n  _ -> :error\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 5

      assert_range_invariants(ast)
    end

    test "cond with multiple clauses" do
      code = "cond do\n  true -> :a\n  false -> :b\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 4

      assert_range_invariants(ast)
    end

    test "missing end keyword" do
      code = "fn -> :ok"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "missing closing paren" do
      code = "(1 + 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "incomplete do-block" do
      code = "if true do\n  :ok"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have range
      assert get_range(ast) != nil
    end

    test "single-line do-block" do
      code = "if true, do: :ok, else: :error"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert_range(ast, {{1, 1}, {1, 31}})
      assert_range_invariants(ast)
    end

    test "for comprehension with do-block" do
      code = "for x <- [1, 2, 3] do\n  x * 2\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 3

      assert_range_invariants(ast)
    end

    test "with statement" do
      code = "with {:ok, x} <- foo() do\n  x\nend"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      {{start_line, _}, {end_line, _}} = get_range(ast)
      assert start_line == 1
      assert end_line == 3

      assert_range_invariants(ast)
    end
  end

  describe "Interpolation Ranges" do
    test "string interpolation range" do
      code = "\"a\#{1}b\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert {:<<>>, meta, args} = ast
      assert meta[:range] == {{1, 1}, {1, 9}}

      assert [frag1, interp, frag2] = args
      assert frag1 == "a"
      assert frag2 == "b"

      assert {:"::", interp_meta, _} = interp
      assert interp_meta[:range] == {{1, 3}, {1, 7}}
    end

    test "heredoc interpolation range" do
      code = "\"\"\"\n\#{1}\n\"\"\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert {:<<>>, meta, args} = ast
      assert meta[:range] == {{1, 1}, {3, 4}}

      interp = Enum.find(args, fn
        {:"::", _, _} -> true
        _ -> false
      end)

      assert {:"::", interp_meta, _} = interp
      assert interp_meta[:range] == {{2, 1}, {2, 5}}
    end

    test "charlist interpolation range" do
      code = "'a\#{1}b'"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      # Charlist interpolation creates a list with fragments and interpolations
      assert get_range(ast) == {{1, 1}, {1, 9}}

      # Verify invariants hold - charlist structure may vary but ranges should be correct
      assert_range_invariants(ast)
    end

    test "atom interpolation range" do
      code = ":\"a\#{1}b\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Atom with interpolation
      assert get_range(ast) == {{1, 1}, {1, 10}}

      # Verify invariants hold - atom structure may vary but ranges should be correct
      assert_range_invariants(ast)
    end

    test "unsafe atom interpolation nodes include ranges" do
      code = ~S|foo(:"a#{1}b")|
      {:ok, {:foo, _meta, [atom_expr]}} = Spitfire.parse(code, tokenizer: :toxic)

      {{:., _dot_meta, [:erlang, :binary_to_atom]}, atom_meta, [binary_ast, :utf8]} =
        atom_expr

      expected_range = {{1, 5}, {1, 14}}
      assert atom_meta[:range] == expected_range
      assert get_range(binary_ast) == expected_range

      # The binary and call nodes both respect the invariants
      assert_range_invariants(binary_ast)
    end

    test "sigil interpolation range" do
      code = "~s(a\#{1}b)"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Sigil wraps the interpolated binary
      assert get_range(ast) == {{1, 1}, {1, 11}}

      # Verify invariants hold (the inner structure may vary but ranges should be correct)
      # Note: we don't assert specific AST structure as sigils have complex nesting
      assert_range_invariants(ast)
    end

    test "multiple interpolations in string" do
      code = "\"\#{1} and \#{2}\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert {:<<>>, meta, args} = ast
      assert meta[:range] == {{1, 1}, {1, 16}}

      # Extract interpolation nodes
      interps =
        Enum.filter(args, fn
          {:"::", _, _} -> true
          _ -> false
        end)

      assert length(interps) == 2
      [interp1, interp2] = interps

      # First interpolation
      assert {:"::", meta1, _} = interp1
      assert meta1[:range] == {{1, 2}, {1, 6}}

      # Second interpolation
      assert {:"::", meta2, _} = interp2
      assert meta2[:range] == {{1, 11}, {1, 15}}

      # Verify non-overlap
      {_, {_, end1}} = meta1[:range]
      {{_, start2}, _} = meta2[:range]
      assert end1 <= start2

      assert_range_invariants(ast)
    end

    test "empty interpolation" do
      code = "\"a\#{}b\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert {:<<>>, meta, args} = ast
      assert meta[:range] == {{1, 1}, {1, 8}}

      # Find interpolation
      interp =
        Enum.find(args, fn
          {:"::", _, _} -> true
          _ -> false
        end)

      assert {:"::", interp_meta, _} = interp
      # Empty interpolation still has a range
      assert interp_meta[:range] != nil
      assert_range_invariants(ast)
    end

    test "complex expression in interpolation" do
      code = "\"\#{1 + 2 * 3}\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic, literal_encoder: test_encoder())

      assert {:<<>>, meta, _args} = ast
      assert meta[:range] == {{1, 1}, {1, 15}}

      # Verify invariants hold for complex expressions in interpolation
      assert_range_invariants(ast)
    end

    test "malformed interpolation with missing closer" do
      code = "\"\#{1\""
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Even with error, AST should have ranges
      assert get_range(ast) != nil

      # Invariants should still hold due to Toxic's structural token synthesis
      assert_range_invariants(ast)
    end

    test "interpolation with nested structure" do
      code = "\"\#{foo(1, 2)}\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert {:<<>>, meta, _args} = ast
      assert meta[:range] == {{1, 1}, {1, 15}}
      assert_range_invariants(ast)
    end

    test "string interpolation respects invariants" do
      code = "\"hello \#{name}, you are \#{age} years old\""
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      assert {:<<>>, meta, _args} = ast
      assert meta[:range] == {{1, 1}, {1, 42}}
      assert_range_invariants(ast)
    end
  end

  describe "Legacy Mode Compatibility" do
    test "no range metadata in legacy mode" do
      code = "[1, 2]"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :elixir)

      # Should not have :range in legacy mode
      range = get_range(ast)
      assert range == nil
    end
  end
end
