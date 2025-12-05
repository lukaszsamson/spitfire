defmodule SpitfireSystematicOperatorsTest do
  use ExUnit.Case, async: true

  # Define operators by precedence group (roughly) or just a flat list
  # We want to test combinations.

  @unary_ops ~w(@ + - ! ^ not & ...)a
  @binary_ops [
    :.,
    :**,
    :*, :/,
    :+, :-,
    :++, :--, :+++, :---, :.., :<>,
    :in, :"not in",
    :|>, :<<<, :>>>, :<<~, :~>>, :<~, :~>, :<~>,
    :<, :>, :<=, :>=,
    :==, :!=, :=~, :===, :!==,
    :&&, :&&&, :and,
    :||, :|||, :or,
    :=,
    :|,
    :"::",
    :when,
    :<-, :\\
  ]

  # Helper to convert atom to string representation
  defp op_to_string(:"not in"), do: "not in"
  defp op_to_string(op), do: Atom.to_string(op)

  defp s2q(code) do
    Code.string_to_quoted(code, columns: true, token_metadata: true)
  end

  # We will generate tests dynamically
  # 1. Unary + Binary (e.g. !a + b)
  # 2. Binary + Unary (e.g. a + !b)
  # 3. Binary + Binary (e.g. a + b * c)

  describe "systematic operator combinations" do
    # We use a loop to generate assertions.
    # Since there are many, we might want to group them or just run them in one test.
    # But one test with 2000 assertions is hard to debug.
    # Maybe we can use `unquote` to generate multiple tests?
    # Or just iterate in one test and print the failing one.

    test "binary - binary combinations (a op1 b op2 c)" do
      vars = ["a", "b", "c"]

      # We pick a subset of operators to keep it reasonable if needed,
      # but 40*40 = 1600 is fast enough for Elixir.

      failures =
        for op1 <- @binary_ops, op2 <- @binary_ops do
          s_op1 = op_to_string(op1)
          s_op2 = op_to_string(op2)

          code = "a #{s_op1} b #{s_op2} c"

          # Some combinations might be syntax errors for Code.string_to_quoted
          # e.g. "a . b" requires b to be atom/alias if it's a call?
          # "a . b" is valid if b is variable? No. "a.b"
          # If op is ".", we need to be careful about spacing. "a . b" is valid?
          # iex> Code.string_to_quoted("a . b")
          # {:ok, {{:., [line: 1], [{:a, [line: 1], nil}, :b]}, [line: 1], []}}
          # It parses as field access.

          case s2q(code) do
            {:ok, expected} ->
              case Spitfire.parse(code) do
                {:ok, actual} ->
                  if actual != expected do
                    {code, expected, actual}
                  else
                    nil
                  end
                {:error, _} ->
                  # If Spitfire fails but Code succeeds, that's a failure
                  {code, expected, :error}
              end
            {:error, _} ->
              # If Code fails, we skip (or we could assert Spitfire also fails or recovers gracefully)
              # For now we focus on valid precedence.
              nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert failures == [], "Failed combinations: #{inspect(failures, pretty: true, limit: :infinity)}"
    end

    test "unary - binary combinations (op1 a op2 b)" do
      failures =
        for op1 <- @unary_ops, op2 <- @binary_ops do
          s_op1 = op_to_string(op1)
          s_op2 = op_to_string(op2)

          code = "#{s_op1} a #{s_op2} b"

          case s2q(code) do
            {:ok, expected} ->
              case Spitfire.parse(code) do
                {:ok, actual} ->
                  if actual != expected, do: {code, expected, actual}, else: nil
                {:error, _} -> {code, expected, :error}
              end
            {:error, _} -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert failures == [], "Failed combinations: #{inspect(failures, pretty: true, limit: :infinity)}"
    end

    test "binary - unary combinations (a op1 op2 b)" do
      failures =
        for op1 <- @binary_ops, op2 <- @unary_ops do
          s_op1 = op_to_string(op1)
          s_op2 = op_to_string(op2)

          code = "a #{s_op1} #{s_op2} b"

          case s2q(code) do
            {:ok, expected} ->
              case Spitfire.parse(code) do
                {:ok, actual} ->
                  if actual != expected, do: {code, expected, actual}, else: nil
                {:error, _} -> {code, expected, :error}
              end
            {:error, _} -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert failures == [], "Failed combinations: #{inspect(failures, pretty: true, limit: :infinity)}"
    end

    test "ternary range (a..b//c) combinations" do
       # a op b..c//d
       # a..b//c op d

       failures =
        for op <- @binary_ops do
          s_op = op_to_string(op)

          code1 = "a #{s_op} b..c//d"
          code2 = "a..b//c #{s_op} d"

          [
            check(code1),
            check(code2)
          ]
        end
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

       assert failures == [], "Failed combinations: #{inspect(failures, pretty: true, limit: :infinity)}"
    end

    test "ternary range with unary operators" do
       # op a..b//c
       # a..op b//c
       # a..b//op c
       
       failures = 
        for op <- @unary_ops do
          s_op = op_to_string(op)
          
          [
            check("#{s_op} a..b//c"),
            check("a..#{s_op} b//c"),
            check("a..b//#{s_op} c")
          ]
        end
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        
       assert failures == [], "Failed combinations: #{inspect(failures, pretty: true, limit: :infinity)}"
    end

    test "map update (op a | b => c) combinations" do
       # This is tricky because | and => are operators too.
       # %{map | key => val}
       # We want to test if operators inside/outside bind correctly.
       # e.g. %{a | b => c + d}
       # e.g. %{a | b + c => d}
       # e.g. %{a + b | c => d}
       # e.g. %{a | b => c} + d

       # Base cases
       base_failures = 
         [
           check("%{a | b => c}"),
           check("%{a | b :: c => d}"),
           check("%{a | b => c :: d}"),
           check("%{a | b => c} + d"),
           check("d + %{a | b => c}")
         ]
         |> Enum.reject(&is_nil/1)

       failures =
        for op <- @binary_ops do
          s_op = op_to_string(op)
          
          # Inside values
          code1 = "%{a | b => c #{s_op} d}"
          # Inside keys
          code2 = "%{a | b #{s_op} c => d}"
          # Inside struct
          code3 = "%{a #{s_op} b | c => d}"
          # Outside
          code4 = "%{a | b => c} #{s_op} d"
          
          [
            check(code1),
            check(code2),
            check(code3),
            check(code4)
          ]
        end
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        
       all_failures = base_failures ++ failures
       assert all_failures == [], "Failed combinations: #{inspect(all_failures, pretty: true, limit: :infinity)}"
    end

  end

  defp check(code) do
    case s2q(code) do
      {:ok, expected} ->
        case Spitfire.parse(code) do
          {:ok, actual} ->
            if actual != expected, do: {code, expected, actual}, else: nil
          {:error, _} -> {code, expected, :error}
        end
      {:error, _} -> nil
    end
  end
end
