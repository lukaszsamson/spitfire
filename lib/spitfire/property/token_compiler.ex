defmodule Spitfire.Property.TokenCompiler do
  @moduledoc """
  Compiles grammar trees to Toxic token lists.

  This module takes grammar tree nodes (defined in `GrammarTree`) and produces
  linear Toxic streaming tokens that can be rendered to source code.
  """

  alias Spitfire.Property.TokenLayout

  @doc """
  Compile a grammar tree to a list of Toxic tokens.

  ## Options

  - `:phase` - Phase level for compilation (default 1)
  """
  @spec to_tokens(term(), keyword()) :: [Toxic.token()]
  def to_tokens(tree, opts \\ []) do
    _phase = Keyword.get(opts, :phase, 1)
    layout = TokenLayout.new()

    {tokens, _layout} = do_to_tokens(tree, layout, opts)
    tokens
  end

  # ===========================================================================
  # Token compiler: do_to_tokens/3
  # ===========================================================================

  # Top-level grammar
  defp do_to_tokens({:grammar, forms}, layout, opts) do
    compile_forms(forms, layout, opts)
  end

  # ---------------------------------------------------------------------------
  # Literals
  # ---------------------------------------------------------------------------

  defp do_to_tokens({:int, value, _format, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.space_before(layout, lexeme, value)
    {[{:int, meta, chars}], layout}
  end

  defp do_to_tokens({:float, value, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.space_before(layout, lexeme, value)
    {[{:flt, meta, chars}], layout}
  end

  defp do_to_tokens({:char, codepoint, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.space_before(layout, lexeme, chars)
    {[{:char, meta, codepoint}], layout}
  end

  defp do_to_tokens({:atom_lit, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    lexeme = ":" <> name
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, lexeme, chars)
    {[{:atom, meta, atom}], layout}
  end

  defp do_to_tokens({:bool_lit, true}, layout, _opts) do
    {meta, layout} = TokenLayout.space_before(layout, "true", nil)
    {[{true, meta}], layout}
  end

  defp do_to_tokens({:bool_lit, false}, layout, _opts) do
    {meta, layout} = TokenLayout.space_before(layout, "false", nil)
    {[{false, meta}], layout}
  end

  defp do_to_tokens(:nil_lit, layout, _opts) do
    {meta, layout} = TokenLayout.space_before(layout, "nil", nil)
    {[{nil, meta}], layout}
  end

  # ---------------------------------------------------------------------------
  # Identifiers and Aliases
  # ---------------------------------------------------------------------------

  defp do_to_tokens({:identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, name, chars)
    {[{:identifier, meta, atom}], layout}
  end

  defp do_to_tokens({:alias, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, name, chars)
    {[{:alias, meta, atom}], layout}
  end

  # ---------------------------------------------------------------------------
  # Catch-all for unimplemented nodes
  # ---------------------------------------------------------------------------

  defp do_to_tokens(node, _layout, _opts) do
    raise "Unimplemented grammar tree node: #{inspect(node)}"
  end

  # ===========================================================================
  # Helper: compile_forms
  # ===========================================================================

  # Compile a list of forms with EOL separators
  defp compile_forms([], layout, _opts), do: {[], layout}

  defp compile_forms([form], layout, opts) do
    do_to_tokens(form, layout, opts)
  end

  defp compile_forms([form | rest], layout, opts) do
    {form_tokens, layout} = do_to_tokens(form, layout, opts)

    # Add EOL token between forms
    # The EOL token's meta spans from current position to next line
    # stick_right doesn't add the newline to position, we do it explicitly after
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    {rest_tokens, layout} = compile_forms(rest, layout, opts)

    {form_tokens ++ [eol_token] ++ rest_tokens, layout}
  end
end
