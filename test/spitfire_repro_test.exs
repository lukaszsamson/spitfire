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
    code = "!case 1 do\n  18.0 -> 49.0\nend * foo"
    assert Spitfire.parse(code) == s2q(code)

    code = "not case 1 do\n  18.0 -> 49.0\nend * foo"
    assert Spitfire.parse(code) == s2q(code)

    code = "-case 1 do\n  18.0 -> 49.0\nend * foo"
    assert Spitfire.parse(code) == s2q(code)

    code = "+case 1 do\n  18.0 -> 49.0\nend - foo"
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

  test "repro 25a1" do
    code = "not a..2//3 - gamma"
    assert Spitfire.parse(code) == s2q(code)

    code = "not a..2 ++ gamma"
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

  @tag :skip
  test "repro 27" do
    code = "fn ['end': baz], ^qux -> &({-5, foo} + 1) in Remote.\"three\"(\"foo\#{foo}bar\", not spam) end"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 28" do
    code = "<<:'ok' + %{\"A\" => delta}>> |> not 0 |> [\"bar\": Foo] + ['bob': foo] + :ok"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 29" do
    code = "&('''\nfoo \#{%{'ok': alpha}} bar\n''' + 1)..0.0"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 30" do
    code = "\"foo\#{[{:alice, :alice}]}bar\" + not %{'ok': -1} |> quote do: :ok"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 31" do
    code = "case \"\" <> \"foo\#{9.0}bar\"..['do': \"\"\"\nfoo \#{spam} bar\n\"\"\"] do\n  <<:\"bar\">> -> ~S/\#{spam}/i\n  _ -> <<?a..foo>>\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 32" do
    code = "&(['one': :ok] + 1) |> Foo.foo()"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 33" do
    code = "{:ok, <<+quote do\n  spam\nend, with ^eggs <- :bob do\n  ?p\nelse\n  _ -> 0\nend>>}"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 34" do
    code = "not \"\" <> \"\""
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 35" do
    code = "&(&(%Qux{label: ['alice': foo]} + 1) + 1)"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 36" do
    code = "Foo.foo('M' |> %Baz{\"ok\": \"\"\"\nfoo \#{alpha} bar\n\"\"\"})"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 37" do
    code = "~s\"\"\"\nfoo \#{&(&(0 + 1) + 1)} bar\n\"\"\""
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 38" do
    code = "not ~s'\#{?a}' |> %{\"k\" => 5} < @qux 0"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 39" do
    code = "not foo |> foo |> foo < '''\nfoo \#{0.0 |> foo} bar\n'''"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 40" do
    code = "0 |> not \"\"\"\nfoo \#{foo} bar\n\"\"\" + \"\"\"\nfoo \#{{foo, foo}} bar\n\"\"\""
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 41" do
    code = "case not \"foo\#{:do}bar\" <> \"foo\#{State}bar\" do\n  {alpha, ^alpha} -> \"\"\"\nfoo \#{baz} bar\n\"\"\"\n  _ -> foo()\nend |> \"\"\"\nfoo \#{foo + Foo |> +delta} bar\n\"\"\""
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 42" do
    code = "'foo\#{&(0 |> Foo + 1) |> %{label: [Config, ?o, Qux]}}bar'"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 43" do
    code = "&('foo\#{Context |> 22.0}bar' + 1) in fn -> with ^spam <- bar do\n  Bar\nelse\n  _ -> gamma\nend end |> quote do\n  20.0\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 44" do
    code = "+case {delta, -4} do\n  foo -> gamma\n  _ -> :error\nend |> :alice ** foo >>> %Default{\"bar\": alpha}"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 45" do
    code = "Context.foo(%{\"v\" => &(?h + 1) !== \"Tsyh\"})"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 46" do
    code = "+with ?p <- :three do\n  beta\nelse\n  _ -> foo\nend..Schema//2"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 47" do
    code = "fn gamma -> Context end &&& &(gamma + 1) |> %Baz{metadata: :'alice'} |> Config"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 48" do
    code = "not gamma |> :foo > [\"alice\": alpha] |> case &1 do\n  ^delta -> ?v\n  _ -> delta\nend"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 49" do
    code = "&(not \"foo\#{-3}bar\" <> \"foo\#{eggs}bar\" + 1)"
    assert Spitfire.parse(code) == s2q(code)
  end

  @tag :skip
  test "repro 50" do
    code = "&(%{\"three\": beta |> 0} + 1) ++ State.\"foo\"(bar)"
    assert Spitfire.parse(code) == s2q(code)
  end
end
