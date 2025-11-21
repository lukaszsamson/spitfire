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
      assert key_meta[:range] == {{1, 3}, {1, 4}}

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
      assert key_meta[:range] == {{1, 6}, {1, 7}}

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

  describe "Range Invariants" do
    # Helper to walk AST and validate range invariants
    defp assert_range_invariants(ast, parent_range \\ nil) do
      case ast do
        {_form, meta, args} when is_list(meta) and is_list(args) ->
          range = Keyword.get(meta, :range)

          # All nodes should have a range in Toxic mode
          assert range != nil, "Node missing range: #{inspect(ast)}"

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

    test "root node spans entire document" do
      code = "1 + 2\n"
      {:ok, ast} = Spitfire.parse(code, tokenizer: :toxic)

      # Root should start at {1,1} and end at EOF
      assert_range(ast, {{1, 1}, {2, 1}})
    end
  end

  describe "Edge Cases" do
    test "malformed list with missing closer" do
      code = "[1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

      # Should still have a range even with error recovery
      range = get_range(ast)
      assert range != nil

      # Should still respect invariants
      assert_range_invariants(ast)
    end

    test "malformed tuple with missing closer" do
      code = "{1, 2"
      {:error, ast, _errors} = Spitfire.parse(code, tokenizer: :toxic)

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
