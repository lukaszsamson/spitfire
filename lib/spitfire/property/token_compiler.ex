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
  # Binary Operators
  # ---------------------------------------------------------------------------

  # Binary operator: left op right (with optional trailing newlines)
  # Per V7 Section 2: operators never render newlines from extra,
  # we emit :eol token if newlines > 0
  defp do_to_tokens({:binary_op, left, {:op_eol, {op_kind, op}, newlines}, right}, layout, opts) do
    # Compile left operand
    {left_tokens, layout} = do_to_tokens(left, layout, opts)

    # Compile operator
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.space_before(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Handle newlines after operator
    {eol_tokens, layout} =
      if newlines > 0 do
        eol_meta = TokenLayout.meta(layout, "\n", newlines)
        layout = TokenLayout.newlines(layout, newlines)
        {[{:eol, eol_meta}], layout}
      else
        {[], layout}
      end

    # Compile right operand
    {right_tokens, layout} = do_to_tokens(right, layout, opts)

    {left_tokens ++ [op_token] ++ eol_tokens ++ right_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Unary Operators
  # ---------------------------------------------------------------------------

  # Unary operator: op operand
  defp do_to_tokens({:unary_op, {op_kind, op}, operand}, layout, opts) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.space_before(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Compile operand (may need space depending on operator)
    {operand_tokens, layout} = do_to_tokens(operand, layout, opts)

    {[op_token] ++ operand_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Calls and Captures
  # ---------------------------------------------------------------------------

  # Paren identifier: foo (used before `(` in calls)
  defp do_to_tokens({:paren_identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, name, chars)
    {[{:paren_identifier, meta, atom}], layout}
  end

  # Call with parentheses: foo(1, 2) or expr.(1)
  defp do_to_tokens({:call_parens, target, args}, layout, opts) do
    # Compile target
    {target_tokens, layout} = compile_call_target(target, layout, opts)

    # Compile opening paren (stuck to target for adhesion)
    {open_meta, layout} = TokenLayout.stick_right(layout, "(", nil)
    open_token = {:"(", open_meta}

    # Compile arguments with commas (first arg stuck to open paren)
    {args_tokens, layout} = compile_args_in_parens(args, layout, opts)

    # Compile closing paren (stuck to last arg or open paren)
    {close_meta, layout} = TokenLayout.stick_right(layout, ")", nil)
    close_token = {:")", close_meta}

    {target_tokens ++ [open_token] ++ args_tokens ++ [close_token], layout}
  end

  # No-parens call with one argument: foo bar
  defp do_to_tokens({:call_no_parens_one, {:identifier, name}, arg}, layout, opts) do
    # Compile identifier
    name_str = Atom.to_string(name)
    chars = String.to_charlist(name_str)
    {id_meta, layout} = TokenLayout.space_before(layout, name_str, chars)
    id_token = {:identifier, id_meta, name}

    # Compile argument (with space before)
    {arg_tokens, layout} = do_to_tokens(arg, layout, opts)

    {[id_token] ++ arg_tokens, layout}
  end

  # Dot call: expr.(args) - the expr part with the dot
  defp do_to_tokens({:dot_call, expr}, layout, opts) do
    # Compile expression
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)

    # Compile dot (stuck to expression)
    {dot_meta, layout} = TokenLayout.stick_right(layout, ".", nil)
    dot_token = {:., dot_meta}

    {expr_tokens ++ [dot_token], layout}
  end

  # Capture integer: &1, &10 (with adhesion)
  defp do_to_tokens({:capture_int, n}, layout, _opts) when is_integer(n) and n > 0 do
    # Compile & operator
    {amp_meta, layout} = TokenLayout.space_before(layout, "&", nil)
    amp_token = {:capture_op, amp_meta, :&}

    # Compile integer (stuck to & for adhesion)
    int_str = Integer.to_string(n)
    chars = String.to_charlist(int_str)
    {int_meta, layout} = TokenLayout.stick_right(layout, int_str, n)
    int_token = {:int, int_meta, chars}

    {[amp_token, int_token], layout}
  end

  # ---------------------------------------------------------------------------
  # fn expressions (Phase 1: single clause only)
  # ---------------------------------------------------------------------------

  # fn_single: fn clause end
  defp do_to_tokens({:fn_single, [clause]}, layout, opts) do
    # Compile 'fn' keyword
    {fn_meta, layout} = TokenLayout.space_before(layout, "fn", nil)
    fn_token = {:fn, fn_meta}

    # Compile the stab clause
    {clause_tokens, layout} = compile_stab_clause(clause, layout, opts)

    # Compile 'end' keyword
    {end_meta, layout} = TokenLayout.space_before(layout, "end", nil)
    end_token = {:end, end_meta}

    {[fn_token] ++ clause_tokens ++ [end_token], layout}
  end

  # ---------------------------------------------------------------------------
  # Catch-all for unimplemented nodes
  # ---------------------------------------------------------------------------

  defp do_to_tokens(node, _layout, _opts) do
    raise "Unimplemented grammar tree node: #{inspect(node)}"
  end

  # ===========================================================================
  # Helper: compile_call_target
  # ===========================================================================

  # Target is a paren_identifier (most common case): foo(...)
  defp compile_call_target({:paren_identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, name, chars)
    {[{:paren_identifier, meta, atom}], layout}
  end

  # Target is a dot_call: expr.(...)
  defp compile_call_target({:dot_call, expr}, layout, opts) do
    # Compile expression
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)

    # Compile dot (stuck to expression for adhesion)
    {dot_meta, layout} = TokenLayout.stick_right(layout, ".", nil)
    dot_token = {:., dot_meta}

    {expr_tokens ++ [dot_token], layout}
  end

  # Target is an identifier (shouldn't happen for call_parens, but handle it)
  defp compile_call_target({:identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.space_before(layout, name, chars)
    {[{:identifier, meta, atom}], layout}
  end

  # ===========================================================================
  # Helper: compile_args_in_parens
  # ===========================================================================

  # Compile arguments inside parentheses (first arg stuck to open paren)
  defp compile_args_in_parens([], layout, _opts), do: {[], layout}

  defp compile_args_in_parens([arg | rest], layout, opts) do
    # First argument is stuck to opening paren (no space)
    {first_tokens, layout} = compile_arg_stuck(arg, layout, opts)

    # Remaining args have commas and spaces
    {rest_tokens, layout} = compile_remaining_args(rest, layout, opts)

    {first_tokens ++ rest_tokens, layout}
  end

  # Compile an argument stuck to previous token (no leading space)
  defp compile_arg_stuck(arg, layout, opts) do
    compile_arg_with_adhesion(arg, layout, opts)
  end

  # Compile remaining arguments with comma separators
  defp compile_remaining_args([], layout, _opts), do: {[], layout}

  defp compile_remaining_args([arg | rest], layout, opts) do
    # Add comma token (stuck to previous)
    {comma_meta, layout} = TokenLayout.stick_right(layout, ",", nil)
    comma_token = {:",", comma_meta}

    # Compile arg with space before
    {arg_tokens, layout} = do_to_tokens(arg, layout, opts)

    # Continue with remaining args
    {rest_tokens, layout} = compile_remaining_args(rest, layout, opts)

    {[comma_token] ++ arg_tokens ++ rest_tokens, layout}
  end

  # Helper to compile an expression with adhesion (stuck to previous token)
  # This handles various expression types by emitting them without leading space
  defp compile_arg_with_adhesion({:int, value, _format, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.stick_right(layout, lexeme, value)
    {[{:int, meta, chars}], layout}
  end

  defp compile_arg_with_adhesion({:float, value, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.stick_right(layout, lexeme, value)
    {[{:flt, meta, chars}], layout}
  end

  defp compile_arg_with_adhesion({:char, codepoint, chars}, layout, _opts) do
    lexeme = List.to_string(chars)
    {meta, layout} = TokenLayout.stick_right(layout, lexeme, chars)
    {[{:char, meta, codepoint}], layout}
  end

  defp compile_arg_with_adhesion({:atom_lit, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    lexeme = ":" <> name
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, lexeme, chars)
    {[{:atom, meta, atom}], layout}
  end

  defp compile_arg_with_adhesion({:bool_lit, true}, layout, _opts) do
    {meta, layout} = TokenLayout.stick_right(layout, "true", nil)
    {[{true, meta}], layout}
  end

  defp compile_arg_with_adhesion({:bool_lit, false}, layout, _opts) do
    {meta, layout} = TokenLayout.stick_right(layout, "false", nil)
    {[{false, meta}], layout}
  end

  defp compile_arg_with_adhesion(:nil_lit, layout, _opts) do
    {meta, layout} = TokenLayout.stick_right(layout, "nil", nil)
    {[{nil, meta}], layout}
  end

  defp compile_arg_with_adhesion({:identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, name, chars)
    {[{:identifier, meta, atom}], layout}
  end

  defp compile_arg_with_adhesion({:alias, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, name, chars)
    {[{:alias, meta, atom}], layout}
  end

  defp compile_arg_with_adhesion({:capture_int, n}, layout, _opts) when is_integer(n) and n > 0 do
    # & stuck to position, int stuck to &
    {amp_meta, layout} = TokenLayout.stick_right(layout, "&", nil)
    amp_token = {:capture_op, amp_meta, :&}

    int_str = Integer.to_string(n)
    chars = String.to_charlist(int_str)
    {int_meta, layout} = TokenLayout.stick_right(layout, int_str, n)
    int_token = {:int, int_meta, chars}

    {[amp_token, int_token], layout}
  end

  # For complex expressions like nested calls, emit with adhesion
  defp compile_arg_with_adhesion({:call_parens, target, args}, layout, opts) do
    # Compile target stuck to current position
    {target_tokens, layout} = compile_call_target_stuck(target, layout, opts)

    # Opening paren stuck to target
    {open_meta, layout} = TokenLayout.stick_right(layout, "(", nil)
    open_token = {:"(", open_meta}

    # Args inside parens
    {args_tokens, layout} = compile_args_in_parens(args, layout, opts)

    # Closing paren stuck to args
    {close_meta, layout} = TokenLayout.stick_right(layout, ")", nil)
    close_token = {:")", close_meta}

    {target_tokens ++ [open_token] ++ args_tokens ++ [close_token], layout}
  end

  defp compile_arg_with_adhesion({:paren_identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, name, chars)
    {[{:paren_identifier, meta, atom}], layout}
  end

  # fn_single stuck to previous token
  defp compile_arg_with_adhesion({:fn_single, [clause]}, layout, opts) do
    # Compile 'fn' keyword stuck to previous
    {fn_meta, layout} = TokenLayout.stick_right(layout, "fn", nil)
    fn_token = {:fn, fn_meta}

    # Compile the stab clause
    {clause_tokens, layout} = compile_stab_clause(clause, layout, opts)

    # Compile 'end' keyword
    {end_meta, layout} = TokenLayout.space_before(layout, "end", nil)
    end_token = {:end, end_meta}

    {[fn_token] ++ clause_tokens ++ [end_token], layout}
  end

  defp compile_arg_with_adhesion(other, layout, opts) do
    # Fallback: use do_to_tokens (may add unwanted space in some cases)
    do_to_tokens(other, layout, opts)
  end

  # Compile call target stuck to current position (no leading space)
  defp compile_call_target_stuck({:paren_identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, name, chars)
    {[{:paren_identifier, meta, atom}], layout}
  end

  defp compile_call_target_stuck({:dot_call, expr}, layout, opts) do
    # Compile expression stuck
    {expr_tokens, layout} = compile_arg_with_adhesion(expr, layout, opts)

    # Compile dot stuck to expression
    {dot_meta, layout} = TokenLayout.stick_right(layout, ".", nil)
    dot_token = {:., dot_meta}

    {expr_tokens ++ [dot_token], layout}
  end

  defp compile_call_target_stuck({:identifier, atom}, layout, _opts) do
    name = Atom.to_string(atom)
    chars = String.to_charlist(name)
    {meta, layout} = TokenLayout.stick_right(layout, name, chars)
    {[{:identifier, meta, atom}], layout}
  end

  # ===========================================================================
  # Helper: op_to_lexeme
  # ===========================================================================

  defp op_to_lexeme(op) when is_atom(op), do: Atom.to_string(op)

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

  # ===========================================================================
  # Helper: compile_stab_clause
  # ===========================================================================

  # Compile a stab clause: pattern -> body
  # Pattern can be :empty, {:single, expr}, or {:many, [expr]}
  # Guard must be nil in Phase 1
  defp compile_stab_clause({:stab_clause, pattern, nil, body}, layout, opts) do
    # Compile pattern (if any)
    {pattern_tokens, layout} = compile_pattern(pattern, layout, opts)

    # Compile stab operator ->
    {stab_meta, layout} = TokenLayout.space_before(layout, "->", nil)
    stab_token = {:stab_op, stab_meta, :->}

    # Compile body
    {body_tokens, layout} = do_to_tokens(body, layout, opts)

    {pattern_tokens ++ [stab_token] ++ body_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_pattern
  # ===========================================================================

  # Empty pattern (no arguments): fn -> ... end
  defp compile_pattern(:empty, layout, _opts), do: {[], layout}

  # Single pattern: fn x -> ... end
  defp compile_pattern({:single, expr}, layout, opts) do
    do_to_tokens(expr, layout, opts)
  end

  # Multiple patterns: fn x, y -> ... end (Phase 2+)
  defp compile_pattern({:many, exprs}, layout, opts) do
    compile_pattern_list(exprs, layout, opts)
  end

  # Compile a list of patterns with comma separators
  defp compile_pattern_list([], layout, _opts), do: {[], layout}

  defp compile_pattern_list([expr], layout, opts) do
    do_to_tokens(expr, layout, opts)
  end

  defp compile_pattern_list([expr | rest], layout, opts) do
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)

    # Add comma token
    {comma_meta, layout} = TokenLayout.stick_right(layout, ",", nil)
    comma_token = {:",", comma_meta}

    # Compile remaining patterns
    {rest_tokens, layout} = compile_pattern_list(rest, layout, opts)

    {expr_tokens ++ [comma_token] ++ rest_tokens, layout}
  end
end
