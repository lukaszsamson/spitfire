defmodule SpitfireOperatorsTest do
  @moduledoc """
  Tests for operator precedence and associativity.

  Based on the Elixir operator precedence table (highest to lowest):

  Operator                                       | Associativity
  ---------------------------------------------- | -------------
  `@`                                            | Unary
  `.`                                            | Left
  `+` `-` `!` `^` `not`                          | Unary
  `**`                                           | Left
  `*` `/`                                        | Left
  `+` `-`                                        | Left
  `++` `--` `+++` `---` `..` `<>`                | Right
  `in` `not in`                                  | Left
  `|>` `<<<` `>>>` `<<~` `~>>` `<~` `~>` `<~>`   | Left
  `<` `>` `<=` `>=`                              | Left
  `==` `!=` `=~` `===` `!==`                     | Left
  `&&` `&&&` `and`                               | Left
  `||` `|||` `or`                                | Left
  `=`                                            | Right
  `&`                                            | Unary
  `=>` (valid only inside `%{}`)                 | Right
  `|`                                            | Right
  `::`                                           | Right
  `when`                                         | Right
  `<-` `\\`                                      | Left
  """
  use ExUnit.Case, async: false

  # Import for drop_ranges helper if needed for debugging
  # import Spitfire.TestHelpers, except: [==: 2]

  setup do
    original = Application.get_env(:spitfire, :tokenizer, :legacy)
    Application.put_env(:spitfire, :tokenizer, :toxic)
    Application.put_env(:spitfire, :verify_range_order, true)

    on_exit(fn ->
      Application.put_env(:spitfire, :tokenizer, original)
      Application.put_env(:spitfire, :verify_range_order, false)
    end)
  end

  # =============================================================================
  # Unary Operators
  # =============================================================================

  describe "unary @ operator" do
    test "module attribute" do
      code = "@foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "module attribute with value" do
      code = "@foo 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "nested module attributes" do
      code = "@foo @bar"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "@ has highest precedence" do
      code = "@foo + 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "@ with dot access" do
      code = "@foo.bar"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "unary + and - operators" do
    test "unary plus" do
      code = "+1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary minus" do
      code = "-1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary plus with identifier" do
      code = "+foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary minus with identifier" do
      code = "-foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "double unary minus" do
      code = "- -1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary minus with binary minus" do
      code = "1 - -2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary plus with binary plus" do
      code = "1 + +2"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "unary ! operator" do
    test "boolean not" do
      code = "!true"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "double negation" do
      code = "!!true"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "! with expression" do
      code = "!foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "! has higher precedence than binary operators" do
      code = "!a && b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "! has higher precedence than ==" do
      code = "!a == b"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "unary ^ operator (pin)" do
    test "pin operator" do
      code = "^foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pin in pattern match" do
      code = "^foo = bar"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pin with access" do
      code = "^foo[0]"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "unary not operator" do
    test "not operator" do
      code = "not true"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "not with expression" do
      code = "not foo"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "not has higher precedence than and" do
      code = "not a and b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "not has higher precedence than or" do
      code = "not a or b"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Dot Operator (Left Associativity)
  # =============================================================================

  describe "dot operator - left associativity" do
    test "simple dot access" do
      code = "foo.bar"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained dot access - left associative" do
      code = "foo.bar.baz"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple chained dots" do
      code = "a.b.c.d.e"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "dot with function call" do
      code = "foo.bar()"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained function calls" do
      code = "foo.bar().baz()"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "dot has higher precedence than +" do
      code = "foo.bar + 1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "dot has higher precedence than *" do
      code = "foo.bar * 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "dot on alias" do
      code = "Foo.Bar.baz"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Power Operator ** (Left Associativity)
  # =============================================================================

  describe "** operator - left associativity" do
    test "simple power" do
      code = "2 ** 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained power - left associative" do
      # 2 ** 3 ** 4 should be (2 ** 3) ** 4
      code = "2 ** 3 ** 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "power has higher precedence than *" do
      code = "2 * 3 ** 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "power has higher precedence than +" do
      code = "1 + 2 ** 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "power with unary minus" do
      code = "-2 ** 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "power with parentheses" do
      code = "2 ** (3 ** 4)"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Multiplication and Division * / (Left Associativity)
  # =============================================================================

  describe "* and / operators - left associativity" do
    test "simple multiplication" do
      code = "2 * 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "simple division" do
      code = "6 / 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained multiplication - left associative" do
      code = "2 * 3 * 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained division - left associative" do
      code = "24 / 4 / 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "mixed * and / - left associative" do
      code = "2 * 3 / 4 * 5"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "* and / have higher precedence than +" do
      code = "1 + 2 * 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "* and / have higher precedence than -" do
      code = "10 - 6 / 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "* has lower precedence than **" do
      code = "2 * 3 ** 2"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Addition and Subtraction + - (Left Associativity)
  # =============================================================================

  describe "+ and - operators - left associativity" do
    test "simple addition" do
      code = "1 + 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "simple subtraction" do
      code = "5 - 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained addition - left associative" do
      code = "1 + 2 + 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained subtraction - left associative" do
      code = "10 - 5 - 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "mixed + and - - left associative" do
      code = "1 + 2 - 3 + 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "+ has lower precedence than *" do
      code = "1 + 2 * 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "- has lower precedence than /" do
      code = "10 - 6 / 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "+ has higher precedence than ++" do
      code = "a + b ++ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # List Operators ++ -- +++ --- (Right Associativity)
  # =============================================================================

  describe "++ operator - right associativity" do
    test "simple concatenation" do
      code = "[1] ++ [2]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained ++ - right associative" do
      # a ++ b ++ c should be a ++ (b ++ c)
      code = "a ++ b ++ c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple chained ++" do
      code = "a ++ b ++ c ++ d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "++ has lower precedence than +" do
      code = "a + b ++ c + d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "-- operator - right associativity" do
    test "simple subtraction" do
      code = "[1, 2] -- [1]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained -- - right associative" do
      code = "a -- b -- c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "+++ operator - right associativity" do
    test "simple +++" do
      code = "a +++ b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained +++ - right associative" do
      code = "a +++ b +++ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "--- operator - right associativity" do
    test "simple ---" do
      code = "a --- b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained --- - right associative" do
      code = "a --- b --- c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe ".. operator - right associativity" do
    test "simple range" do
      code = "1..10"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "range with step" do
      code = "1..10//2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained .. - right associative" do
      code = "a..b..c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test ".. has lower precedence than +" do
      code = "1 + 2..3 + 4"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<> operator - right associativity" do
    test "simple binary concatenation" do
      code = ~S'"a" <> "b"'
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <> - right associative" do
      code = ~S'a <> b <> c'
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple chained <>" do
      code = ~S'a <> b <> c <> d'
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed right associative list operators" do
    test "++ and -- share right associativity" do
      code = "a ++ b -- c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "range operator shares precedence with ++" do
      code = "a ++ b .. c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "<> and ++ share precedence and right associativity" do
      code = "a <> b ++ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Membership Operators in, not in (Left Associativity)
  # =============================================================================

  describe "in operator - left associativity" do
    test "simple in" do
      code = "a in [1, 2, 3]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "in with range" do
      code = "a in 1..10"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "in has lower precedence than ++" do
      code = "a in b ++ c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "in has higher precedence than |>" do
      code = "a in b |> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "not in operator - left associativity" do
    test "simple not in" do
      code = "a not in [1, 2, 3]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "not in with range" do
      code = "a not in 1..10"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Pipeline Operators |> <<< >>> <<~ ~>> <~ ~> <~> (Left Associativity)
  # =============================================================================

  describe "|> operator - left associativity" do
    test "simple pipe" do
      code = "a |> b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained pipe - left associative" do
      code = "a |> b |> c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple chained pipes" do
      code = "a |> b |> c |> d |> e"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "|> has lower precedence than in" do
      code = "a in b |> c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "|> has higher precedence than <" do
      code = "a |> b < c |> d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<<< operator - left associativity" do
    test "simple <<<" do
      code = "a <<< b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <<< - left associative" do
      code = "a <<< b <<< c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe ">>> operator - left associativity" do
    test "simple >>>" do
      code = "a >>> b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained >>> - left associative" do
      code = "a >>> b >>> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<<~ operator - left associativity" do
    test "simple <<~" do
      code = "a <<~ b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <<~ - left associative" do
      code = "a <<~ b <<~ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "~>> operator - left associativity" do
    test "simple ~>>" do
      code = "a ~>> b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained ~>> - left associative" do
      code = "a ~>> b ~>> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<~ operator - left associativity" do
    test "simple <~" do
      code = "a <~ b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <~ - left associative" do
      code = "a <~ b <~ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "~> operator - left associativity" do
    test "simple ~>" do
      code = "a ~> b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained ~> - left associative" do
      code = "a ~> b ~> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<~> operator - left associativity" do
    test "simple <~>" do
      code = "a <~> b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <~> - left associative" do
      code = "a <~> b <~> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed pipeline family operators" do
    test "operators in the pipeline family stay left associative" do
      code = "a <<< b |> c ~>> d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Comparison Operators < > <= >= (Left Associativity)
  # =============================================================================

  describe "< operator - left associativity" do
    test "simple less than" do
      code = "a < b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained < - left associative" do
      code = "a < b < c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "< has lower precedence than |>" do
      code = "a |> b < c |> d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "< has higher precedence than ==" do
      code = "a < b == c < d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "> operator - left associativity" do
    test "simple greater than" do
      code = "a > b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained > - left associative" do
      code = "a > b > c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "<= operator - left associativity" do
    test "simple less than or equal" do
      code = "a <= b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained <= - left associative" do
      code = "a <= b <= c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe ">= operator - left associativity" do
    test "simple greater than or equal" do
      code = "a >= b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained >= - left associative" do
      code = "a >= b >= c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed comparison operators" do
    test "< and > mixed - left associative" do
      code = "a < b > c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "<= and >= mixed - left associative" do
      code = "a <= b >= c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "all comparison operators mixed" do
      code = "a < b <= c > d >= e"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Equality Operators == != =~ === !== (Left Associativity)
  # =============================================================================

  describe "== operator - left associativity" do
    test "simple equality" do
      code = "a == b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained == - left associative" do
      code = "a == b == c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "== has lower precedence than <" do
      code = "a < b == c < d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "== has higher precedence than &&" do
      code = "a == b && c == d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "!= operator - left associativity" do
    test "simple inequality" do
      code = "a != b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained != - left associative" do
      code = "a != b != c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "=~ operator - left associativity" do
    test "simple match" do
      code = ~S'"hello" =~ ~r/ell/'
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained =~ - left associative" do
      code = "a =~ b =~ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "=== operator - left associativity" do
    test "simple strict equality" do
      code = "a === b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained === - left associative" do
      code = "a === b === c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "!== operator - left associativity" do
    test "simple strict inequality" do
      code = "a !== b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained !== - left associative" do
      code = "a !== b !== c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed equality operators" do
    test "== and != mixed - left associative" do
      code = "a == b != c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "=== and !== mixed - left associative" do
      code = "a === b !== c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "all equality operators mixed" do
      code = "a == b != c === d !== e =~ f"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Logical AND Operators && &&& and (Left Associativity)
  # =============================================================================

  describe "&& operator - left associativity" do
    test "simple and" do
      code = "a && b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained && - left associative" do
      code = "a && b && c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "&& has lower precedence than ==" do
      code = "a == b && c == d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "&& has higher precedence than ||" do
      code = "a && b || c && d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "&&& operator - left associativity" do
    test "simple &&&" do
      code = "a &&& b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained &&& - left associative" do
      code = "a &&& b &&& c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "and operator - left associativity" do
    test "simple and" do
      code = "a and b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained and - left associative" do
      code = "a and b and c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "and has lower precedence than ==" do
      code = "a == b and c == d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "and has higher precedence than or" do
      code = "a and b or c and d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed AND operators" do
    test "&& and and mixed" do
      code = "a && b and c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "&&& with && and and" do
      code = "a &&& b && c and d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Logical OR Operators || ||| or (Left Associativity)
  # =============================================================================

  describe "|| operator - left associativity" do
    test "simple or" do
      code = "a || b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained || - left associative" do
      code = "a || b || c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "|| has lower precedence than &&" do
      code = "a && b || c && d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "|| has higher precedence than =" do
      code = "a = b || c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "||| operator - left associativity" do
    test "simple |||" do
      code = "a ||| b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained ||| - left associative" do
      code = "a ||| b ||| c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "or operator - left associativity" do
    test "simple or" do
      code = "a or b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained or - left associative" do
      code = "a or b or c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "or has lower precedence than and" do
      code = "a and b or c and d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "mixed OR operators" do
    test "|| and or mixed" do
      code = "a || b or c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "||| with || and or" do
      code = "a ||| b || c or d"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Match Operator = (Right Associativity)
  # =============================================================================

  describe "= operator - right associativity" do
    test "simple match" do
      code = "a = b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained = - right associative" do
      # a = b = c should be a = (b = c)
      code = "a = b = c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple chained =" do
      code = "a = b = c = d"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "= has lower precedence than ||" do
      code = "a = b || c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "= has higher precedence than &" do
      code = "a = &b/1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pattern match with tuple" do
      code = "{a, b} = {1, 2}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pattern match with list" do
      code = "[h | t] = [1, 2, 3]"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Capture Operator & (Unary)
  # =============================================================================

  describe "& operator - unary" do
    test "capture function" do
      code = "&foo/1"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture with module" do
      code = "&Foo.bar/2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture with expression" do
      code = "&(&1 + 1)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture with multiple args" do
      code = "&(&1 + &2)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "& has lower precedence than =" do
      code = "f = &foo/1"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "... operator - unary" do
    test "bare ellipsis expression" do
      code = "..."
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis inside anonymous function body" do
      code = "fn -> ... end"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "= has higher precedence than ..." do
      code = "... = a = b"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis keeps inner arithmetic precedence" do
      code = "... + 1 * 2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "ellipsis can be captured" do
      code = "&..."
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Map Arrow Operator => (Right Associativity, only in %{})
  # =============================================================================

  describe "=> operator - right associativity in maps" do
    test "simple map with =>" do
      code = "%{a => b}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "map with multiple =>" do
      code = "%{a => b, c => d}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "nested map with =>" do
      code = "%{a => %{b => c}}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "=> with complex keys" do
      code = "%{1 + 2 => 3}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "=> with complex values" do
      code = "%{a => b + c}"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Pipe Operator | (Right Associativity)
  # =============================================================================

  describe "| operator - right associativity" do
    test "simple cons" do
      code = "[a | b]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "cons with multiple elements" do
      code = "[a, b | c]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "map update with |" do
      code = "%{map | a: 1}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "struct update with |" do
      code = "%Foo{struct | a: 1}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "| is right associative across repeated operators" do
      code = "a | b | c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "| has lower precedence than =>" do
      code = "%{a => b | c}"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Type Operator :: (Right Associativity)
  # =============================================================================

  describe ":: operator - right associativity" do
    test "simple type annotation" do
      code = "a :: integer"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "bitstring type" do
      code = "<<a::8>>"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "bitstring with size" do
      code = "<<a::size(8)>>"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "bitstring with multiple specs" do
      code = "<<a::8, b::binary>>"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained :: - right associative" do
      code = "a :: b :: c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test ":: has lower precedence than |" do
      code = "a | b :: c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # When Operator (Right Associativity)
  # =============================================================================

  describe "when operator - right associativity" do
    test "simple guard" do
      code = "def foo(a) when is_integer(a), do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple guards with and" do
      code = "def foo(a) when is_integer(a) and a > 0, do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple guards with or" do
      code = "def foo(a) when is_integer(a) or is_float(a), do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained when - right associative" do
      code = "a when b when c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "when has lower precedence than ::" do
      code = "a :: b when c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Left Arrow Operator <- (Left Associativity)
  # =============================================================================

  describe "<- operator - left associativity" do
    test "simple generator" do
      code = "for x <- [1, 2, 3], do: x"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple generators" do
      code = "for x <- xs, y <- ys, do: {x, y}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "with expression" do
      code = "with {:ok, a} <- foo(), do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "<- has lower precedence than when" do
      code = "for x when is_integer(x) <- xs, do: x"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "<- groups left to right when chained" do
      code = "a <- b <- c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Default Argument Operator \\ (Left Associativity)
  # =============================================================================

  describe "\\\\ operator - left associativity" do
    test "simple default argument" do
      code = "def foo(a \\\\ 1), do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "multiple default arguments" do
      code = "def foo(a \\\\ 1, b \\\\ 2), do: {a, b}"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "default with complex expression" do
      code = "def foo(a \\\\ 1 + 2), do: a"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "\\\\ groups left to right when chained" do
      code = "a \\\\ b \\\\ c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Precedence Interactions Between Operators
  # =============================================================================

  describe "precedence interactions" do
    test "arithmetic vs logical" do
      code = "1 + 2 == 3 and 4 - 1 == 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "comparison vs logical" do
      code = "a < b && c > d || e <= f"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pipe vs arithmetic" do
      code = "1 + 2 |> foo() |> bar() + 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "all arithmetic operators" do
      code = "1 + 2 * 3 ** 4 / 5 - 6"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary and binary operators" do
      code = "-1 + -2 * -3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "complex expression with many operators" do
      code = "@foo.bar |> baz() == 1 + 2 * 3 and !flag || default"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "range with arithmetic" do
      code = "1 + 2..3 * 4"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "list operators with comparison" do
      code = "[1] ++ [2] == [1, 2]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "string concat with comparison" do
      code = ~S'"a" <> "b" == "ab"'
      assert Spitfire.parse(code) == s2q(code)
    end

    test "match with pipe" do
      code = "result = a |> b |> c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "capture with match" do
      code = "fun = &Foo.bar/2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "deep nesting of operators" do
      code = "a + b * c ** d / e - f"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "boolean expression chain" do
      code = "a and b or c and d or e"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "relaxed boolean chain" do
      code = "a && b || c && d || e"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "mixed boolean operators" do
      code = "a and b && c or d || e"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Associativity Verification
  # =============================================================================

  describe "left associativity verification" do
    test "left associative operators group left to right" do
      # For left associative: a op b op c == (a op b) op c
      # The AST should show the leftmost operation as the innermost

      # Multiplication
      code = "a * b * c"
      assert Spitfire.parse(code) == s2q(code)

      # Addition
      code = "a + b + c"
      assert Spitfire.parse(code) == s2q(code)

      # Comparison
      code = "a < b < c"
      assert Spitfire.parse(code) == s2q(code)

      # Logical and
      code = "a && b && c"
      assert Spitfire.parse(code) == s2q(code)

      # Pipe
      code = "a |> b |> c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  describe "right associativity verification" do
    test "right associative operators group right to left" do
      # For right associative: a op b op c == a op (b op c)
      # The AST should show the rightmost operation as the innermost

      # List concat
      code = "a ++ b ++ c"
      assert Spitfire.parse(code) == s2q(code)

      # Match
      code = "a = b = c"
      assert Spitfire.parse(code) == s2q(code)

      # Type
      code = "a :: b :: c"
      assert Spitfire.parse(code) == s2q(code)

      # When
      code = "a when b when c"
      assert Spitfire.parse(code) == s2q(code)

      # Range
      code = "a..b..c"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Edge Cases and Special Scenarios
  # =============================================================================

  describe "edge cases" do
    test "parentheses override precedence" do
      code = "(1 + 2) * 3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "nested parentheses" do
      code = "((1 + 2) * (3 + 4))"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "operator with newline" do
      code = "1 +\n2"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "chained operators with newlines" do
      code = "1 +\n2 *\n3"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "pipe with newlines" do
      code = "a\n|> b\n|> c"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "unary operators with parens" do
      code = "-(1 + 2)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "not with parens" do
      code = "not (a and b)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "! with parens" do
      code = "!(a && b)"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "access syntax with operators" do
      code = "foo[a + b]"
      assert Spitfire.parse(code) == s2q(code)
    end

    test "function call with operator expression" do
      code = "foo(a + b, c * d)"
      assert Spitfire.parse(code) == s2q(code)
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp s2q(code, opts \\ []) do
    Code.string_to_quoted(
      code,
      Keyword.merge([columns: true, token_metadata: true, emit_warnings: false], opts)
    )
  end
end
