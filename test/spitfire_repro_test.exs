defmodule SpitfireReproTest do
  use ExUnit.Case, async: false
  import Spitfire.TestHelpers, except: [==: 2]

  setup do
    original = Application.get_env(:spitfire, :tokenizer, :legacy)
    Application.put_env(:spitfire, :tokenizer, :toxic)
    Application.put_env(:spitfire, :verify_range_order, true)

    on_exit(fn ->
      Application.put_env(:spitfire, :tokenizer, original)
      Application.put_env(:spitfire, :verify_range_order, false)
    end)
  end

  defp s2q(code, opts \\ []) do
    Code.string_to_quoted(
      code,
      Keyword.merge([columns: true, token_metadata: true, emit_warnings: false], opts)
    )
  end

  test "repro 1" do
    code = "&foo/1..0..case Foo.eggs() do\n  foo -> qux\n  _ -> ?a\nend//0"
    assert Spitfire.parse(code) == s2q(code)
  end

  # test "repro 2" do
  #   code = "@foo Foo.\"a\"(with ^delta <- beta do\n  ?y\nelse\n  _ -> 0.0\nend)"
  #   assert Spitfire.parse(code) == s2q(code)
  # end

  test "repro 2a" do
    code = "@foo Foo.a(try do\n :ok\nend)"
    assert Spitfire.parse(code) == s2q(code)

    code = "@foo Foo.\"a\"(try do\n :ok\nend)"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 3" do
    code = "Foo.foo() |> {foo..:ok..['two': :ok]//0, [['baz': spam]]}"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 4" do
    code = "{foo, Foo.foo()}..\"\" <> \"foo\#{%{\"K\" => Mod}}bar\""
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 5" do
    code = "foo() + 'W'..foo..0//0"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 6" do
    code = "foo..foo..fn -> :ok end//0"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 7" do
    code = "0 + 'A'..\"foo\#{foo}bar\" <> \"\"..%{label: &3}//0"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 8" do
    code = "+case -:ok do\n  18.0 -> 49.0\n  _ -> -7\nend + foo()"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 9a" do
    code = "not try do\n :ok\nend <= 1"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 10" do
    code = "[@spec foo() :: term(), with gamma <- beta do\n  Bar\nelse\n  _ -> 0\nend |> {-7, qux} + ~s\"\"\"\nfoo \#{0.0} bar\n\"\"\"]"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 10a" do
    code = "[@foobar foo() :: term(), with gamma <- beta do\n  Bar\nelse\n  _ -> 0\nend |> {-7, qux} + ~s\"\"\"\nfoo \#{0.0} bar\n\"\"\"]"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 11" do
    code = "['foo\#{%Foo{\"end\": 47.0}}bar' or foo |> baz..:error..gamma//2]"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 12" do
    code = "with [label: [\"baz\": ^bar]] <- @type baz :: any()..qux..22.0//1, do: \"\""
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 13" do
    code = "%{\"z9H\" => not 'foo\#{beta}bar'} |> \"foo\#{spam |> Context}bar\"..%Qux{\"one\": :one}..\"\" <> \"\"//1"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 14" do
    code = "{{[qux, :error, beta] - ?l..gamma, %Remote{'alice': \"foo\#{qux}bar\" <> \"\"}}, {%{\"N\" => 41.0 >>> ?m}, [Default |> ?k, ?i ** qux]}, \"foo\#{[\"two\": spam]}bar\"}"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 15" do
    code = "{11.0, [eggs, ?g, Qux] |> {:ok, 0}}..\"\" <> \"foo\#{['baz': :one]}bar\""
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 16" do
    code = "Foo.foo(\"foo\#{\"foo\#{[\"alice\": 0]}bar\"}bar\")"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 17" do
    code = "quote do: case \"foo\#{gamma}bar\" <> \"foo\#{14.0}bar\"..\"\" <> \"foo\#{eggs}bar\" do\n  ?t -> [opts: gamma]\n  _ -> %Baz{\"ok\": Bar}\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 18" do
    code = "'foo\#{@beta with Config <- :bar, do: :foo + [Baz]}bar'"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 19" do
    code = "@baz with Foo <- Context, do: ?x + &(@eggs %{label: alpha} + 1)"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 20" do
    code = "case <<[\"two\": case beta do\n  38.0 -> qux\n  _ -> ?d\nend]>> do\n  [\"three\": ?m] -> Bar.eggs()\n  _ -> 0.0\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 21" do
    code = "-quote do\n baz\nend ||| a"
    assert Spitfire.parse(code) == s2q(code)

    code = "+quote do\n baz\nend === a"
    assert Spitfire.parse(code) == s2q(code)

    code = "!quote do\n baz\nend != a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend == a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend or a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend = a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend && a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend &&& a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend and a"
    assert Spitfire.parse(code) == s2q(code)

    code = "not quote do\n baz\nend || a"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 22" do
    code = "case State.\"two\"(quote do\n  %Mod{'alice': :baz}\nend) do\n  ['three': :\"ok\"] -> %{\"end\": ?z} |> delta\n  _ -> %Foo{'error': %Foo{label: baz}}\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 23" do
    code = "@delta case Config.alpha(qux, beta) do\n  Context -> ?u\n  _ -> 3\nend..Foo"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 24a" do
    code = "@foo try do\n  1\nrescue\n_ -> 0\nend..1"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 24b" do
    code = "@foo try do\n  1\nend..1//2"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 25" do
    code = "not [?r]..29.0 ++ gamma |> [%Foo{label: eggs}, [\"end\": Bar]]"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 25a" do
    code = "not b |> a"
    assert Spitfire.parse(code) == s2q(code)

    code = "!b |> a"
    assert Spitfire.parse(code) == s2q(code)

    code = "+b |> a"
    assert Spitfire.parse(code) == s2q(code)

    code = "-b |> a"
    assert Spitfire.parse(code) == s2q(code)

    code = "^b |> a"
    assert Spitfire.parse(code) == s2q(code)
  end

  test "repro 26a" do
    code = "1..(&not/2)//0"
    assert Spitfire.parse(code) == s2q(code)
  end
end
