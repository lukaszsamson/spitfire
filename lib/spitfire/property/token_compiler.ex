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

  # Top-level grammar (legacy format with implicit newline separators)
  defp do_to_tokens({:grammar, forms}, layout, opts) do
    compile_forms(forms, layout, opts)
  end

  # Top-level grammar with explicit eoe markers (legacy format)
  defp do_to_tokens({:grammar_eoe, forms_with_eoe}, layout, opts) do
    compile_forms_with_eoe(forms_with_eoe, layout, opts)
  end

  # Top-level grammar v2 format per elixir_parser.yrl grammar rules:
  # - leading_eoe: optional eoe before expr_list
  # - exprs: list of {expr, eoe | nil} where eoe is between exprs (last has nil)
  # - trailing_eoe: optional eoe after expr_list
  defp do_to_tokens({:grammar_v2, leading_eoe, exprs, trailing_eoe}, layout, opts) do
    # Emit leading eoe if present
    {leading_tokens, layout} =
      if leading_eoe do
        compile_eoe(leading_eoe, layout)
      else
        {[], layout}
      end

    # Compile expressions with eoe between them
    {expr_tokens, layout} = compile_expr_list(exprs, layout, opts)

    # Emit trailing eoe if present
    {trailing_tokens, layout} =
      if trailing_eoe do
        compile_eoe(trailing_eoe, layout)
      else
        {[], layout}
      end

    {leading_tokens ++ expr_tokens ++ trailing_tokens, layout}
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

  # Matched binary operator: left op right (both operands are matched)
  defp do_to_tokens({:matched_op, left, op_eol, right}, layout, opts) do
    compile_binary_op(left, op_eol, right, layout, opts)
  end

  # Unmatched binary operator: left op right (right is unmatched/do-block-bearing)
  defp do_to_tokens({:unmatched_op, left, op_eol, right}, layout, opts) do
    compile_binary_op(left, op_eol, right, layout, opts)
  end

  # Legacy binary operator (backward compatibility)
  # Per V7 Section 2: operators never render newlines from extra,
  # we emit :eol token if newlines > 0
  defp do_to_tokens({:binary_op, left, op_eol, right}, layout, opts) do
    compile_binary_op(left, op_eol, right, layout, opts)
  end

  # Common binary operator compilation
  defp compile_binary_op(left, {:op_eol, {op_kind, op}, newlines}, right, layout, opts) do
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

  # Matched unary operator: op operand (with adhesion)
  # Per grammar: matched_expr -> unary_op_eol matched_expr
  # unary_op_eol -> unary_op | unary_op eol
  defp do_to_tokens({:matched_unary, {op_kind, op}, newlines, operand}, layout, opts)
       when is_integer(newlines) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.space_before(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Emit newlines if any (per unary_op_eol -> unary_op eol)
    {eol_tokens, layout} =
      if newlines > 0 do
        eol_meta = TokenLayout.meta(layout, "\n", newlines)
        layout = TokenLayout.newlines(layout, newlines)
        {[{:eol, eol_meta}], layout}
      else
        {[], layout}
      end

    # Compile operand with adhesion (stuck to operator for matched_unary)
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[op_token] ++ eol_tokens ++ operand_tokens, layout}
  end

  # Legacy matched_unary without newlines (backward compatibility)
  defp do_to_tokens({:matched_unary, {op_kind, op}, operand}, layout, opts) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.space_before(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Compile operand with adhesion (stuck to operator for matched_unary)
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[op_token] ++ operand_tokens, layout}
  end

  # Legacy unary operator (backward compatibility - keeps original space behavior)
  defp do_to_tokens({:unary_op, {op_kind, op}, operand}, layout, opts) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.space_before(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Compile operand with space (original behavior)
    {operand_tokens, layout} = do_to_tokens(operand, layout, opts)

    {[op_token] ++ operand_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Nullary Operators
  # ---------------------------------------------------------------------------

  # Nullary range operator: ..
  defp do_to_tokens({:nullary_range, nil}, layout, _opts) do
    {meta, layout} = TokenLayout.space_before(layout, "..", nil)
    {[{:range_op, meta, :..}], layout}
  end

  # Nullary ellipsis operator: ...
  defp do_to_tokens({:nullary_ellipsis, nil}, layout, _opts) do
    {meta, layout} = TokenLayout.space_before(layout, "...", nil)
    {[{:ellipsis_op, meta, :...}], layout}
  end

  # ---------------------------------------------------------------------------
  # At operator (@expr)
  # ---------------------------------------------------------------------------

  # At operator with optional newline: @\n expr
  # Per grammar: at_op_eol -> at_op | at_op eol
  defp do_to_tokens({:at_op, newlines, operand}, layout, opts) when is_integer(newlines) do
    {at_meta, layout} = TokenLayout.space_before(layout, "@", nil)
    at_token = {:at_op, at_meta, :@}

    # Emit newlines if any (per at_op_eol -> at_op eol)
    {eol_tokens, layout} =
      if newlines > 0 do
        eol_meta = TokenLayout.meta(layout, "\n", newlines)
        layout = TokenLayout.newlines(layout, newlines)
        {[{:eol, eol_meta}], layout}
      else
        {[], layout}
      end

    # Compile operand
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[at_token] ++ eol_tokens ++ operand_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Capture operator (&expr)
  # ---------------------------------------------------------------------------

  # Capture operator with optional newline: &\n expr
  # Per grammar: capture_op_eol -> capture_op | capture_op eol
  defp do_to_tokens({:capture_op, newlines, operand}, layout, opts) when is_integer(newlines) do
    {amp_meta, layout} = TokenLayout.space_before(layout, "&", nil)
    amp_token = {:capture_op, amp_meta, :&}

    # Emit newlines if any (per capture_op_eol -> capture_op eol)
    {eol_tokens, layout} =
      if newlines > 0 do
        eol_meta = TokenLayout.meta(layout, "\n", newlines)
        layout = TokenLayout.newlines(layout, newlines)
        {[{:eol, eol_meta}], layout}
      else
        {[], layout}
      end

    # Compile operand with adhesion
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[amp_token] ++ eol_tokens ++ operand_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Ellipsis prefix operator (...expr)
  # ---------------------------------------------------------------------------

  # Ellipsis as prefix operator: ...expr
  defp do_to_tokens({:ellipsis_prefix, expr}, layout, opts) do
    {ellipsis_meta, layout} = TokenLayout.space_before(layout, "...", nil)
    ellipsis_token = {:ellipsis_op, ellipsis_meta, :...}

    # Compile expression with adhesion
    {expr_tokens, layout} = compile_arg_with_adhesion(expr, layout, opts)

    {[ellipsis_token] ++ expr_tokens, layout}
  end

  # ---------------------------------------------------------------------------
  # Parenthesized Expressions
  # ---------------------------------------------------------------------------

  # Parenthesized expression: (expr)
  defp do_to_tokens({:paren_expr, expr}, layout, opts) do
    # Opening paren
    {open_meta, layout} = TokenLayout.space_before(layout, "(", nil)
    open_token = {:"(", open_meta}

    # Compile expression (stuck to open paren)
    {expr_tokens, layout} = compile_arg_with_adhesion(expr, layout, opts)

    # Closing paren (stuck to expression)
    {close_meta, layout} = TokenLayout.stick_right(layout, ")", nil)
    close_token = {:")", close_meta}

    {[open_token] ++ expr_tokens ++ [close_token], layout}
  end

  # Empty parentheses: ()
  defp do_to_tokens({:empty_paren, nil}, layout, _opts) do
    # Opening paren
    {open_meta, layout} = TokenLayout.space_before(layout, "(", nil)
    open_token = {:"(", open_meta}

    # Closing paren (stuck to open paren)
    {close_meta, layout} = TokenLayout.stick_right(layout, ")", nil)
    close_token = {:")", close_meta}

    {[open_token, close_token], layout}
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

  # fn_multi: fn clause1; clause2; ... end
  defp do_to_tokens({:fn_multi, clauses}, layout, opts) when length(clauses) >= 2 do
    # Compile 'fn' keyword
    {fn_meta, layout} = TokenLayout.space_before(layout, "fn", nil)
    fn_token = {:fn, fn_meta}

    # Compile stab clauses with semicolon separators
    {clauses_tokens, layout} = compile_stab_clauses(clauses, layout, opts)

    # Compile 'end' keyword
    {end_meta, layout} = TokenLayout.space_before(layout, "end", nil)
    end_token = {:end, end_meta}

    {[fn_token] ++ clauses_tokens ++ [end_token], layout}
  end

  # ---------------------------------------------------------------------------
  # do_block expressions (Phase 2)
  # ---------------------------------------------------------------------------

  # call_do: identifier do body end (e.g., if true do :yes end)
  defp do_to_tokens({:call_do, {:identifier, name}, args, {:do_block, body, extras}}, layout, opts) do
    # Compile identifier as do_identifier
    name_str = Atom.to_string(name)
    chars = String.to_charlist(name_str)
    {id_meta, layout} = TokenLayout.space_before(layout, name_str, chars)
    id_token = {:do_identifier, id_meta, name}

    # Compile arguments (if any)
    {args_tokens, layout} = compile_do_args(args, layout, opts)

    # Compile 'do' keyword
    {do_meta, layout} = TokenLayout.space_before(layout, "do", nil)
    do_token = {:do, do_meta}

    # Newline after do
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    # Compile body expressions
    {body_tokens, layout} = compile_do_body(body, layout, opts)

    # Compile extras (else, rescue, etc.)
    {extras_tokens, layout} = compile_block_items(extras, layout, opts)

    # Compile 'end' keyword
    {end_meta, layout} = TokenLayout.space_before(layout, "end", nil)
    end_token = {:end, end_meta}

    {[id_token] ++ args_tokens ++ [do_token, eol_token] ++ body_tokens ++ extras_tokens ++ [end_token], layout}
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

  # Matched binary operator stuck to previous token
  defp compile_arg_with_adhesion({:matched_op, left, op_eol, right}, layout, opts) do
    compile_binary_op_stuck(left, op_eol, right, layout, opts)
  end

  # Unmatched binary operator stuck to previous token
  defp compile_arg_with_adhesion({:unmatched_op, left, op_eol, right}, layout, opts) do
    compile_binary_op_stuck(left, op_eol, right, layout, opts)
  end

  # Legacy binary operator stuck to previous token
  defp compile_arg_with_adhesion({:binary_op, left, op_eol, right}, layout, opts) do
    compile_binary_op_stuck(left, op_eol, right, layout, opts)
  end

  # Matched unary operator stuck to previous token (with newlines)
  defp compile_arg_with_adhesion({:matched_unary, op_kind, newlines, operand}, layout, opts)
       when is_integer(newlines) do
    compile_unary_op_stuck_with_newlines(op_kind, newlines, operand, layout, opts)
  end

  # Matched unary operator stuck to previous token (legacy, no newlines)
  defp compile_arg_with_adhesion({:matched_unary, op_kind, operand}, layout, opts) do
    compile_unary_op_stuck(op_kind, operand, layout, opts)
  end

  # Legacy unary operator stuck to previous token
  defp compile_arg_with_adhesion({:unary_op, op_kind, operand}, layout, opts) do
    compile_unary_op_stuck(op_kind, operand, layout, opts)
  end

  defp compile_arg_with_adhesion(other, layout, opts) do
    # Fallback: use do_to_tokens (may add unwanted space in some cases)
    do_to_tokens(other, layout, opts)
  end

  # Compile binary operator with left operand stuck to current position
  defp compile_binary_op_stuck(left, {:op_eol, {op_kind, op}, newlines}, right, layout, opts) do
    # Compile left operand stuck to current position
    {left_tokens, layout} = compile_arg_with_adhesion(left, layout, opts)

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

  # Compile unary operator stuck to current position
  defp compile_unary_op_stuck({op_kind, op}, operand, layout, opts) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.stick_right(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Compile operand with adhesion (stuck to operator)
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[op_token] ++ operand_tokens, layout}
  end

  # Compile unary operator stuck to current position with newlines
  defp compile_unary_op_stuck_with_newlines({op_kind, op}, newlines, operand, layout, opts) do
    op_lexeme = op_to_lexeme(op)
    {op_meta, layout} = TokenLayout.stick_right(layout, op_lexeme, nil)
    op_token = {op_kind, op_meta, op}

    # Emit newlines if any
    {eol_tokens, layout} =
      if newlines > 0 do
        eol_meta = TokenLayout.meta(layout, "\n", newlines)
        layout = TokenLayout.newlines(layout, newlines)
        {[{:eol, eol_meta}], layout}
      else
        {[], layout}
      end

    # Compile operand with adhesion (stuck to operator or after newline)
    {operand_tokens, layout} = compile_arg_with_adhesion(operand, layout, opts)

    {[op_token] ++ eol_tokens ++ operand_tokens, layout}
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
  # Helper: compile_forms_with_eoe (explicit eoe markers - legacy)
  # ===========================================================================

  # Compile forms with explicit eoe markers (legacy format where every form has eoe)
  defp compile_forms_with_eoe([], layout, _opts), do: {[], layout}

  defp compile_forms_with_eoe([{form, eoe}], layout, opts) do
    {form_tokens, layout} = do_to_tokens(form, layout, opts)
    {eoe_tokens, layout} = compile_eoe(eoe, layout)
    {form_tokens ++ eoe_tokens, layout}
  end

  defp compile_forms_with_eoe([{form, eoe} | rest], layout, opts) do
    {form_tokens, layout} = do_to_tokens(form, layout, opts)
    {eoe_tokens, layout} = compile_eoe(eoe, layout)
    {rest_tokens, layout} = compile_forms_with_eoe(rest, layout, opts)
    {form_tokens ++ eoe_tokens ++ rest_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_expr_list (grammar v2 format)
  # ===========================================================================

  # Compile expr_list per grammar rules:
  #   expr_list -> expr
  #   expr_list -> expr_list eoe expr
  #
  # The eoe goes BETWEEN expressions. Last expr has eoe = nil.
  # Format: [{expr, eoe | nil}, ...]

  defp compile_expr_list([], layout, _opts), do: {[], layout}

  defp compile_expr_list([{expr, nil}], layout, opts) do
    # Last expression, no eoe after it
    do_to_tokens(expr, layout, opts)
  end

  defp compile_expr_list([{expr, eoe} | rest], layout, opts) when eoe != nil do
    # Expression with eoe after it (between this and next)
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)
    {eoe_tokens, layout} = compile_eoe(eoe, layout)
    {rest_tokens, layout} = compile_expr_list(rest, layout, opts)
    {expr_tokens ++ eoe_tokens ++ rest_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_eoe (end-of-expression markers)
  # ===========================================================================

  # eoe -> eol (newline only)
  defp compile_eoe(:eol, layout) do
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    layout = TokenLayout.newline(layout)
    {[{:eol, eol_meta}], layout}
  end

  # eoe -> ';' (semicolon only)
  defp compile_eoe(:semi, layout) do
    {semi_meta, layout} = TokenLayout.stick_right(layout, ";", nil)
    {[{:";", semi_meta}], layout}
  end

  # eoe -> eol ';' (newline followed by semicolon)
  defp compile_eoe(:eol_semi, layout) do
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    layout = TokenLayout.newline(layout)
    {semi_meta, layout} = TokenLayout.stick_right(layout, ";", nil)
    {[{:eol, eol_meta}, {:";", semi_meta}], layout}
  end

  # ===========================================================================
  # Helper: compile_stab_clause
  # ===========================================================================

  # Compile a stab clause: pattern -> body (or pattern when guard -> body)
  # Pattern can be :empty, {:single, expr}, or {:many, [expr]}
  # Guard can be nil or an expression

  # Stab clause with guard: pattern when guard -> body
  defp compile_stab_clause({:stab_clause, pattern, guard, body}, layout, opts) when guard != nil do
    # Compile pattern (if any)
    {pattern_tokens, layout} = compile_pattern(pattern, layout, opts)

    # Compile 'when' keyword
    {when_meta, layout} = TokenLayout.space_before(layout, "when", nil)
    when_token = {:when_op, when_meta, :when}

    # Compile guard expression
    {guard_tokens, layout} = do_to_tokens(guard, layout, opts)

    # Compile stab operator ->
    {stab_meta, layout} = TokenLayout.space_before(layout, "->", nil)
    stab_token = {:stab_op, stab_meta, :->}

    # Compile body
    {body_tokens, layout} = do_to_tokens(body, layout, opts)

    {pattern_tokens ++ [when_token] ++ guard_tokens ++ [stab_token] ++ body_tokens, layout}
  end

  # Stab clause without guard: pattern -> body
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

  # ===========================================================================
  # Helper: compile_stab_clauses (multiple clauses with semicolon separators)
  # ===========================================================================

  # Compile multiple stab clauses with semicolon separators
  defp compile_stab_clauses([], layout, _opts), do: {[], layout}

  defp compile_stab_clauses([clause], layout, opts) do
    compile_stab_clause(clause, layout, opts)
  end

  defp compile_stab_clauses([clause | rest], layout, opts) do
    # Compile first clause
    {clause_tokens, layout} = compile_stab_clause(clause, layout, opts)

    # Add semicolon separator
    {semi_meta, layout} = TokenLayout.stick_right(layout, ";", nil)
    semi_token = {:";", semi_meta}

    # Compile remaining clauses
    {rest_tokens, layout} = compile_stab_clauses(rest, layout, opts)

    {clause_tokens ++ [semi_token] ++ rest_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_do_args (arguments for do blocks)
  # ===========================================================================

  # Compile arguments for do block (if/unless take one arg, case takes an expression)
  defp compile_do_args([], layout, _opts), do: {[], layout}

  defp compile_do_args([arg], layout, opts) do
    do_to_tokens(arg, layout, opts)
  end

  defp compile_do_args([arg | rest], layout, opts) do
    {arg_tokens, layout} = do_to_tokens(arg, layout, opts)
    {rest_tokens, layout} = compile_do_args(rest, layout, opts)
    {arg_tokens ++ rest_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_do_body (body of do block)
  # ===========================================================================

  # Compile do block body - can be a list of expressions or stab clauses
  defp compile_do_body([], layout, _opts), do: {[], layout}

  # Handle stab clauses (for case expressions)
  defp compile_do_body([{:stab_clause, _, _, _} = clause | rest], layout, opts) do
    compile_stab_body([clause | rest], layout, opts)
  end

  defp compile_do_body([expr], layout, opts) do
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)

    # Add trailing newline
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    {expr_tokens ++ [eol_token], layout}
  end

  defp compile_do_body([expr | rest], layout, opts) do
    {expr_tokens, layout} = do_to_tokens(expr, layout, opts)

    # Add EOL between expressions
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    {rest_tokens, layout} = compile_do_body(rest, layout, opts)

    {expr_tokens ++ [eol_token] ++ rest_tokens, layout}
  end

  # Compile stab clauses in do block body (for case expressions)
  defp compile_stab_body([], layout, _opts), do: {[], layout}

  defp compile_stab_body([clause], layout, opts) do
    {clause_tokens, layout} = compile_stab_clause(clause, layout, opts)

    # Add trailing newline
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    {clause_tokens ++ [eol_token], layout}
  end

  defp compile_stab_body([clause | rest], layout, opts) do
    {clause_tokens, layout} = compile_stab_clause(clause, layout, opts)

    # Add newline between clauses
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    {rest_tokens, layout} = compile_stab_body(rest, layout, opts)

    {clause_tokens ++ [eol_token] ++ rest_tokens, layout}
  end

  # ===========================================================================
  # Helper: compile_block_items (else, rescue, catch, after)
  # ===========================================================================

  # Compile block items (empty for basic do blocks)
  defp compile_block_items([], layout, _opts), do: {[], layout}

  defp compile_block_items([{:block_item, :else, body} | rest], layout, opts) do
    # Compile 'else' keyword
    {else_meta, layout} = TokenLayout.space_before(layout, "else", nil)
    else_token = {:block_identifier, else_meta, :else}

    # Newline after else
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    # Compile else body
    {body_tokens, layout} = compile_do_body(body, layout, opts)

    # Continue with remaining block items
    {rest_tokens, layout} = compile_block_items(rest, layout, opts)

    {[else_token, eol_token] ++ body_tokens ++ rest_tokens, layout}
  end

  defp compile_block_items([{:block_item, :rescue, body} | rest], layout, opts) do
    # Compile 'rescue' keyword
    {rescue_meta, layout} = TokenLayout.space_before(layout, "rescue", nil)
    rescue_token = {:block_identifier, rescue_meta, :rescue}

    # Newline after rescue
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    # Compile rescue body (stab clauses)
    {body_tokens, layout} = compile_do_body(body, layout, opts)

    # Continue with remaining block items
    {rest_tokens, layout} = compile_block_items(rest, layout, opts)

    {[rescue_token, eol_token] ++ body_tokens ++ rest_tokens, layout}
  end

  defp compile_block_items([{:block_item, :catch, body} | rest], layout, opts) do
    # Compile 'catch' keyword
    {catch_meta, layout} = TokenLayout.space_before(layout, "catch", nil)
    catch_token = {:block_identifier, catch_meta, :catch}

    # Newline after catch
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    # Compile catch body (stab clauses)
    {body_tokens, layout} = compile_do_body(body, layout, opts)

    # Continue with remaining block items
    {rest_tokens, layout} = compile_block_items(rest, layout, opts)

    {[catch_token, eol_token] ++ body_tokens ++ rest_tokens, layout}
  end

  defp compile_block_items([{:block_item, :after, body} | rest], layout, opts) do
    # Compile 'after' keyword
    {after_meta, layout} = TokenLayout.space_before(layout, "after", nil)
    after_token = {:block_identifier, after_meta, :after}

    # Newline after after
    eol_meta = TokenLayout.meta(layout, "\n", 1)
    eol_token = {:eol, eol_meta}
    layout = TokenLayout.newline(layout)

    # Compile after body (expressions)
    {body_tokens, layout} = compile_do_body(body, layout, opts)

    # Continue with remaining block items
    {rest_tokens, layout} = compile_block_items(rest, layout, opts)

    {[after_token, eol_token] ++ body_tokens ++ rest_tokens, layout}
  end
end
