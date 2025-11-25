defmodule Spitfire.Property.Generators do
  @moduledoc false

  use ExUnitProperties

  @identifiers ~w(foo bar baz qux spam eggs alpha beta gamma delta)a
  @aliases ~w(Foo Bar Baz Qux Remote Mod State Schema Context Config Default)a
  @atoms ~w(ok error foo bar baz one two three alice bob do end)a
  @kw_keys ~w(label count opts config metadata)a
  @operator_atoms ~w(+ - * == != < > <= >= and or not when in |> <<< >>> &&& ||| ^^^)a

  @max_expr_depth 3
  @max_interp_depth 2
  @max_block_depth 2

  def atom_pool, do: @atoms
  def keyword_pool, do: @kw_keys
  def operator_atoms, do: @operator_atoms

  def program(opts \\ []) do
    max_forms = Keyword.get(opts, :max_forms, 4)
    expr_depth = Keyword.get(opts, :expr_depth, @max_expr_depth)
    interp_depth = Keyword.get(opts, :interp_depth, @max_interp_depth)
    block_depth = Keyword.get(opts, :block_depth, @max_block_depth)

    list_of(form(expr_depth, interp_depth, block_depth), length: 1..max_forms)
    |> map(fn forms -> Enum.join(forms, "\n") end)
  end

  def form(expr_depth \\ @max_expr_depth, interp_depth \\ @max_interp_depth, block_depth \\ @max_block_depth) do
    expr(:expr, expr_depth, interp_depth, block_depth)
  end

  def expr(_context, 0, _interp_depth, _block_depth) do
    one_of([literal(), variable()])
  end

  def expr(context, depth, interp_depth, block_depth) do
    frequency([
      {5, literal()},
      {3, quoted_atom()},
      {4, variable()},
      {4, string_like(:binary, depth, interp_depth)},
      {3, string_like(:charlist, depth, interp_depth)},
      {3, heredoc(:binary, depth, interp_depth)},
      {2, heredoc(:charlist, depth, interp_depth)},
      {4, keyword_list(depth - 1, interp_depth, block_depth)},
      {4, map_expr(depth - 1, interp_depth, block_depth)},
      {4, list_expr(depth - 1, interp_depth, block_depth)},
      {4, tuple_expr(depth - 1, interp_depth, block_depth)},
      {4, call_expr(depth - 1, interp_depth, block_depth)},
      {3, dot_call(depth - 1, interp_depth, block_depth)},
      {3, capture(depth - 1, interp_depth, block_depth)},
      {3, sigil(depth - 1, interp_depth)},
      {2, fn_block(depth - 1, interp_depth, block_depth)},
      {2, quote_block(depth - 1, interp_depth, block_depth)},
      {2, bitstring(depth - 1, interp_depth, block_depth)},
      {4, binary_op(depth - 1, interp_depth, block_depth)}
    ])
    |> map(&wrap_context(context, &1))
  end

  defp wrap_context(_context, generated), do: generated

  defp literal do
    fragments = [
      integer(-10..10) |> map(&Integer.to_string/1),
      float_literal(),
      member_of(@atoms) |> map(&(":#{&1}")),
      member_of(@aliases) |> map(&Atom.to_string/1),
      char_literal()
    ]

    one_of(fragments)
  end

  defp quoted_atom do
    frequency([
      {3, member_of(@atoms) |> map(&":\"#{&1}\"")},
      {2, member_of(@atoms) |> map(&":'#{&1}'")},
      {1,
       expr(:expr, 1, 0, 0)
       |> map(fn inner -> ":\"foo#{inner}bar\"" end)}
    ])
  end

  defp variable do
    member_of(@identifiers) |> map(&Atom.to_string/1)
  end

  defp float_literal do
    integer(0..50)
    |> map(fn int -> "#{int}.0" end)
  end

  defp char_literal do
    integer(?a..?z) |> map(&"?#{<<&1>>}")
  end

  defp string_like(:binary, depth, interp_depth) do
    string_frag(depth, interp_depth, "\"", "\"")
  end

  defp string_like(:charlist, depth, interp_depth) do
    string_frag(depth, interp_depth, "'", "'")
  end

  defp string_frag(depth, interp_depth, opener, closer) when interp_depth > 0 do
    fragments =
      one_of([
        constant(""),
        string(:alphanumeric, length: 1..4)
      ])

    interpolation =
      expr(:expr, max(depth - 1, 0), interp_depth - 1, @max_block_depth)
      |> map(fn inner ->
        [opener, "foo\#{", inner, "}bar", closer]
        |> IO.iodata_to_binary()
      end)

    frequency([
      {4, map(fragments, &"#{opener}#{&1}#{closer}")},
      {3, interpolation}
    ])
  end

  defp string_frag(_depth, _interp_depth, opener, closer) do
    string(:alphanumeric, length: 0..6)
    |> map(&"#{opener}#{&1}#{closer}")
  end

  defp heredoc(kind, depth, interp_depth) do
    delimiter = if kind == :binary, do: ~s("""), else: "'''"
    closing = delimiter

    inner =
      if interp_depth > 0 do
        expr(:expr, max(depth - 1, 0), interp_depth - 1, @max_block_depth)
        |> map(fn inner -> "foo #{wrap_interpolation(inner)} bar" end)
      else
        string(:alphanumeric, length: 1..6)
      end

    map(inner, fn content -> "#{delimiter}\n#{content}\n#{closing}" end)
  end

  defp sigil(depth, interp_depth) do
    sigil_letter = member_of(~w(s S c C)a)
    delimiter = member_of(["'", "\"", "/"])
    modifiers = member_of(["", "i", "s", "im"])

    inner =
      if interp_depth > 0 do
        expr(:expr, max(depth - 1, 0), interp_depth - 1, @max_block_depth)
        |> map(&wrap_interpolation/1)
      else
        string(:alphanumeric, length: 1..6)
      end

    map({sigil_letter, delimiter, inner, modifiers}, fn {letter, delim, content, mods} ->
      "~#{letter}#{delim}#{content}#{delim}#{mods}"
    end)
  end

  defp keyword_list(depth, interp_depth, block_depth) do
    keyword_key()
    |> bind(fn key ->
      expr(:expr, depth, interp_depth, block_depth)
      |> map(&"[#{key}: #{&1}]")
    end)
  end

  defp keyword_key do
    one_of([
      member_of(@kw_keys) |> map(&Atom.to_string/1),
      member_of(@atoms) |> map(&"\"#{Atom.to_string(&1)}\""),
      member_of(@atoms) |> map(&"'#{Atom.to_string(&1)}'")
    ])
  end

  defp map_expr(depth, interp_depth, block_depth) do
    bind(expr(:expr, depth, interp_depth, block_depth), fn value ->
      bind(keyword_key(), fn key ->
        constant("%{#{key}: #{value}}")
      end)
    end)
  end

  defp list_expr(depth, interp_depth, block_depth) do
    list_of(expr(:expr, depth, interp_depth, block_depth), length: 1..3)
    |> map(&"[#{Enum.join(&1, ", ")}]")
  end

  defp tuple_expr(depth, interp_depth, block_depth) do
    list_of(expr(:expr, depth, interp_depth, block_depth), length: 2..3)
    |> map(&"{#{Enum.join(&1, ", ")}}")
  end

  defp call_expr(depth, interp_depth, block_depth) do
    identifier =
      one_of([
        variable(),
        member_of(@aliases) |> map(&Atom.to_string/1)
      ])

    args = list_of(expr(:expr, depth, interp_depth, block_depth), length: 0..2)

    map({identifier, args}, fn {id, args} ->
      "#{id}(#{Enum.join(args, ", ")})"
    end)
  end

  defp dot_call(depth, interp_depth, block_depth) do
    base = member_of(@aliases) |> map(&Atom.to_string/1)
    target =
      one_of([
        variable(),
        quoted_identifier()
      ])

    args = list_of(expr(:expr, depth, interp_depth, block_depth), length: 0..2)

    map({base, target, args}, fn {base, target, args} ->
      "#{base}.#{target}(#{Enum.join(args, ", ")})"
    end)
  end

  defp capture(depth, interp_depth, block_depth) do
    one_of([
      map(variable(), &"&#{&1}/1"),
      expr(:expr, depth, interp_depth, block_depth)
      |> map(fn inner -> "&(" <> inner <> " + 1)" end),
      member_of(@operator_atoms) |> map(&"&#{&1}/2"),
      member_of(1..3) |> map(&"&#{&1}")
    ])
  end

  defp quote_block(depth, interp_depth, block_depth) do
    bind(expr(:expr, depth, interp_depth, block_depth), fn body ->
      constant("quote do: #{body}")
    end)
  end

  defp fn_block(depth, interp_depth, block_depth) do
    bind(expr(:expr, depth, interp_depth, block_depth), fn body ->
      constant("fn -> #{body} end")
    end)
  end

  defp binary_op(depth, interp_depth, block_depth) do
    ops = ["+", "-", "*", "==", "and", "or", "|>"]

    bind(
      {expr(:expr, depth, interp_depth, block_depth), member_of(ops),
       expr(:expr, depth, interp_depth, block_depth)},
      fn {left, op, right} ->
        constant("#{left} #{op} #{right}")
      end
    )
  end

  defp quoted_identifier do
    one_of([
      string(:alphanumeric, length: 1..4),
      member_of(@atoms) |> map(&Atom.to_string/1)
    ])
    |> map(&"\"#{&1}\"")
  end

  defp wrap_interpolation(inner) do
    ["\#{", inner, "}"] |> IO.iodata_to_binary()
  end

  defp bitstring(depth, interp_depth, block_depth) do
    exprs = list_of(expr(:expr, depth, interp_depth, block_depth), length: 1..2)

    map(exprs, fn parts ->
      inner = Enum.join(parts, ", ")
      "<<#{inner}>>"
    end)
  end
end
