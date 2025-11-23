defmodule Spitfire do
  @moduledoc """
  Spitfire parser
  """
  import Spitfire.Tracer
  import Spitfire.While
  import Spitfire.While2

  require Logger

  @trace? Application.compile_env(:spitfire, :trace, false)

  defmodule NoFuelRemaining do
    @moduledoc false
    defexception message: """
                 The parser ran out of fuel!

                 This happens when the parser recurses too many times without consuming a new token,
                 and most likely indicates a bug in the parser.
                 """
  end

  # precedences

  # pratt parsers are top down operator precedence recursive descent parsers
  #
  # operators have precedence (also known as binding power in some literature) and have a direction, left or right
  #
  # precedences increment by 2s to account for the left and right binding power. when doing the calculation (as seen in parse_expression/2)
  # if an operator has a right binding power, then you subtract 1 before comparing.

  # an example to differentiate the two binding powers are to compare the plus and concat operators.
  #
  # the implicit parentheses in the following two expressions makes this concept clearer
  #
  # one + two + three => ((one + two) + three)
  #   and
  # one ++ two ++ three => (one ++ (two ++ three))
  #
  # this is also made evident by comparing the resulting AST

  # iex(1)> quote do
  # ...(1)> one + two + three
  # ...(1)> end
  # {:+, [context: Elixir, imports: [{1, Kernel}, {2, Kernel}]],
  #  [
  #    {:+, [context: Elixir, imports: [{1, Kernel}, {2, Kernel}]],
  #     [{:one, [], Elixir}, {:two, [], Elixir}]},
  #    {:three, [], Elixir}
  #  ]}
  # iex(2)> quote do
  # ...(2)> one ++ two ++ three
  # ...(2)> end
  # {:++, [context: Elixir, imports: [{2, Kernel}]],
  #  [
  #    {:one, [], Elixir},
  #    {:++, [context: Elixir, imports: [{2, Kernel}]],
  #     [{:two, [], Elixir}, {:three, [], Elixir}]}
  #  ]}

  @lowest {:left, 2}
  @doo {:left, 4}
  @stab_op {:right, 6}
  # list comma are commas inside tuples, maps, and lists, and function parameter/argument lists
  @list_comma {:left, 8}
  @in_match_op {:left, 10}
  @whenn {:right, 12}
  # comma are commas inside a right stab argument list
  @comma {:left, 14}
  @kw_identifier {:left, 16}
  @assoc_op {:right, 18}
  @type_op {:right, 20}
  @pipe_op {:right, 22}
  @capture_op {:left, 24}
  @match_op {:right, 26}
  @or_op {:left, 28}
  @and_op {:left, 30}
  @comp_op {:left, 32}
  @rel_op {:left, 34}
  @arrow_op {:left, 36}
  @in_op {:left, 38}
  @xor_op {:left, 40}
  @ternary_op {:right, 42}
  @concat_op {:right, 44}
  @range_op {:right, 46}
  @dual_op {:left, 48}
  @mult_op {:left, 50}
  @power_op {:left, 52}
  @left_paren {:left, 54}
  @unary_op {:left, 56}
  @left_bracket {:left, 58}
  @dot_call_op {:left, 60}
  @dot_op {:left, 62}
  @at_op {:left, 64}

  @precedences %{
    :"," => @comma,
    :. => @dot_call_op,
    :"(" => @left_paren,
    :"[" => @left_bracket,
    dot_call_op: @dot_call_op,
    do: @doo,
    kw_identifier: @kw_identifier,
    stab_op: @stab_op,
    in_match_op: @in_match_op,
    when_op: @whenn,
    type_op: @type_op,
    pipe_op: @pipe_op,
    assoc_op: @assoc_op,
    capture_op: @capture_op,
    match_op: @match_op,
    or_op: @or_op,
    and_op: @and_op,
    comp_op: @comp_op,
    rel_op: @rel_op,
    arrow_op: @arrow_op,
    in_op: @in_op,
    xor_op: @xor_op,
    ternary_op: @ternary_op,
    concat_op: @concat_op,
    range_op: @range_op,
    dual_op: @dual_op,
    mult_op: @mult_op,
    power_op: @power_op,
    unary_op: @unary_op,
    dot_op: @dot_op,
    at_op: @at_op
  }

  @doc """
  Parses the given code into Elixir AST.

  ## Options

    * `:file` - the filename to be reported in case of errors.
    * `:line` - the starting line of the parsed code. Defaults to 1.
    * `:column` - the starting column of the parsed code. Defaults to 1.
    * `:literal_encoder` - a function to encode literals. See `Code.string_to_quoted/2` for details.
      When provided, this function receives the literal value and its metadata.
      Spitfire passes range information in the metadata if available.
    * `:tokenizer` - the tokenizer backend to use. Defaults to `:legacy`.
      Set to `:toxic` to enable precise range tracking.

  ## Range Metadata

  When using the `:toxic` tokenizer, Spitfire attaches range information to the AST metadata.
  The range is stored in the `:range` key as a tuple `{{start_line, start_col}, {end_line, end_col}}`.
  The range is inclusive of the start position and exclusive of the end position (half-open interval).

  For literals (integers, strings, atoms, etc.), standard Elixir AST does not support metadata.
  To capture ranges for literals, you must provide a `:literal_encoder` that wraps the literal
  in a node that can hold metadata (e.g., `{:__literal__, meta, [value]}`).
  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, Macro.t()} | {:error, :no_fuel_remaining} | {:error, Macro.t(), list()}
  def parse(code, opts \\ []) do
    parser = code |> new(opts) |> next_token() |> next_token()

    # eat all the beginning eol tokens in case the file starts with a comment
    parser =
      while current_token(parser) == :eol <- parser do
        next_token(parser)
      end

    case parse_program(parser) do
      {ast, %{errors: errors} = parser_after} ->
        ast =
          ast
          |> attach_root_range(parser_after)
          |> strip_ranges_if_needed(opts)

        if errors == [] do
          {:ok, ast}
        else
          {:error, ast, Enum.reverse(errors)}
        end
    end
  rescue
    NoFuelRemaining ->
      {:error, :no_fuel_remaining}
  after
    Process.delete(:comma_list_parsers)
  end

  def parse!(code, opts \\ []) do
    case parse(code, opts) do
      {:ok, ast} ->
        ast

      {:error, :no_fuel_remaining} ->
        raise "No fuel remaining!"

      {:error, _ast, _errors} ->
        raise "Failed to parse!"
    end
  end

  def parse_with_comments(code, opts \\ []) do
    Process.put(:code_formatter_comments, [])

    opts = [{:preserve_comments, &preserve_comments/5} | opts]
    result = parse(code, opts)
    comments = Enum.reverse(Process.get(:code_formatter_comments))

    case result do
      {:ok, ast} -> {:ok, ast, comments}
      {:error, ast, errors} -> {:error, ast, comments, errors}
    end
  after
    Process.delete(:code_formatter_comments)
  end

  def container_cursor_to_quoted(code, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:cursor_completion, true)
      |> Keyword.put(:emit_warnings, false)
      |> Keyword.put(:check_terminators, {:cursor, []})

    Spitfire.parse(code, opts)
  end

  defp attach_root_range(ast, %{stream: %Spitfire.TokenStream{backend: Toxic}} = parser) do
    root_start = {parser.start_line, parser.start_column}

    root_end =
      case parser.last_span do
        {{_, _}, {el, ec}} -> {el, ec}
        _ -> root_start
      end

    case ast do
      {form, meta, args} ->
        range = merge_ranges([ast_range(ast), {root_start, root_end}])
        {form, put_meta_range(meta, range), args}

      other ->
        other
    end
  end

  defp attach_root_range(ast, _parser), do: ast

  defp parse_program(parser) do
    trace "parse_program", trace_meta(parser) do
      {exprs, parser} =
        while2 current_token(parser) != :eof <- parser do
          {ast, parser} = parse_expression(parser, @lowest, false, false, true)

          parser =
            cond do
              match?({:__block__, [{:error, true} | _], _}, ast) ->
                next_token(parser)

              peek_token(parser) in [:eol, :";", :eof] ->
                next_token(parser)

              true ->
                parser
            end

          ast = push_eoe(ast, current_eoe(parser))

          {ast, eat_eol(parser)}
        end

      exprs = build_block_nr(exprs, parser)

      {exprs, parser}
    end
  end

  defp calc_prec(parser, associativity, precedence) do
    {_associativity, power} = peek_precedence(parser)

    precedence =
      case associativity do
        :left -> precedence
        :right -> precedence - 1
      end

    precedence < power
  end

  @terminals MapSet.new([:eol, :eof, :"}", :")", :"]", :">>"])
  @terminals_with_comma MapSet.put(@terminals, :",")

  # Dynamic terminal set selection based on parser context
  defp get_terminals(parser, with_comma) do
    base = if with_comma, do: @terminals_with_comma, else: @terminals

    if parser.interpolation_depth > 0 do
      MapSet.put(base, :end_interpolation)
    else
      base
    end
  end

  defp(
    parse_expression(
      parser,
      assoc \\ @lowest,
      is_list \\ false,
      is_map \\ false,
      is_top \\ false,
      is_stab \\ false
    )
  )

  defp parse_expression(parser, {associativity, precedence}, is_list, is_map, is_top, is_stab) do
    trace "parse_expression", trace_meta(parser) do
      parser = consume_fuel(parser)

      prefix =
        case current_token_type(parser) do
          :identifier -> &parse_identifier/1
          :do_identifier -> &parse_do_identifier/1
          :paren_identifier -> &parse_paren_identifier/1
          :bracket_identifier -> &parse_lone_identifier/1
          :op_identifier -> &parse_identifier/1
          :alias -> &parse_alias/1
          :"<<" -> &parse_bitstring/1
          :kw_identifier when is_list or is_map -> &parse_kw_identifier/1
          :kw_identifier_unsafe when is_list or is_map -> &parse_kw_identifier/1
          :kw_identifier when not is_list and not is_map -> &parse_bracketless_kw_list/1
          :kw_identifier_unsafe when not is_list and not is_map -> &parse_bracketless_kw_list/1
          :int -> &parse_int/1
          :flt -> &parse_float/1
          :atom -> &parse_atom/1
          :atom_quoted -> &parse_atom/1
          :atom_unsafe -> &parse_atom/1
          true -> &parse_boolean/1
          false -> &parse_boolean/1
          :bin_string -> &parse_string/1
          :bin_heredoc -> &parse_string/1
          :list_string -> &parse_string/1
          :list_heredoc -> &parse_string/1
          :char -> &parse_char/1
          :sigil -> &parse_sigil/1
          :fn -> &parse_anon_function/1
          :at_op -> &parse_prefix_expression/1
          :unary_op -> &parse_prefix_expression/1
          :capture_op -> &parse_prefix_expression/1
          :dual_op -> &parse_prefix_expression/1
          :capture_int -> &parse_capture_int/1
          :stab_op -> &parse_stab_expression/1
          :range_op -> &parse_range_expression/1
          :"[" -> &parse_list_literal/1
          :"(" -> &parse_grouped_expression/1
          :"{" -> &parse_tuple_literal/1
          :";" -> raise "semicolon"
          :%{} -> &parse_map_literal/1
          :% -> &parse_struct_literal/1
          :ellipsis_op -> &parse_ellipsis_op/1
          nil -> &parse_nil_literal/1
          # Linearized token handlers
          :bin_string_start -> &parse_linearized_string(&1, :binary)
          :list_string_start -> &parse_linearized_string(&1, :charlist)
          :bin_heredoc_start -> &parse_linearized_heredoc(&1, :binary)
          :list_heredoc_start -> &parse_linearized_heredoc(&1, :charlist)
          :sigil_start -> &parse_linearized_sigil/1
          :atom_safe_start -> &parse_linearized_atom(&1, :safe)
          :atom_unsafe_start -> &parse_linearized_atom(&1, :unsafe)
          _ -> nil
        end

      if prefix == nil do
        meta = current_meta(parser)
        ctype = current_token_type(parser)
        parser = put_error(parser, {meta, "unknown token: #{ctype}"})

        parser =
          case ctype do
            :")" -> parser
            :"]" -> parser
            :"}" -> parser
            :">>" -> parser
            :end -> parser
            _ -> next_token(parser)
          end

        {{:__block__, [{:error, true} | meta], []}, parser}
      else
        {left, parser} = prefix.(parser)

        terminals = get_terminals(parser, not is_top)

        {parser, is_valid} = validate_peek(parser, current_token_type(parser))

        if is_valid do
          while (is_nil(Map.get(parser, :stab_state)) and
                   not MapSet.member?(terminals, peek_token(parser))) &&
                  (current_token(parser) != :do and peek_token(parser) != :eol) &&
                  calc_prec(parser, associativity, precedence) <- {left, parser} do
            parser = consume_fuel(parser)
            peek_token_type = peek_token_type(parser)

            infix =
              case peek_token_type do
                :match_op -> &parse_infix_expression/2
                :when_op -> &parse_infix_expression/2
                :pipe_op when is_map -> &parse_pipe_op/2
                :pipe_op -> &parse_infix_expression/2
                :type_op -> &parse_infix_expression/2
                :dual_op -> &parse_infix_expression/2
                :mult_op -> &parse_infix_expression/2
                :power_op -> &parse_infix_expression/2
                :"[" -> &parse_access_expression/2
                :concat_op -> &parse_infix_expression/2
                :assoc_op -> &parse_assoc_op/2
                :arrow_op -> &parse_infix_expression/2
                :ternary_op -> &parse_infix_expression/2
                :or_op -> &parse_infix_expression/2
                :and_op -> &parse_infix_expression/2
                :comp_op -> &parse_infix_expression/2
                :rel_op -> &parse_infix_expression/2
                :in_op -> &parse_infix_expression/2
                :xor_op -> &parse_infix_expression/2
                :in_match_op -> &parse_infix_expression/2
                :range_op -> &parse_range_expression/2
                :stab_op when not is_stab -> &parse_stab_expression/2
                :do -> &parse_do_block/2
                :dot_call_op -> &parse_dot_call_expression/2
                :"(" -> &parse_call_expression/2
                :. -> &parse_dot_expression/2
                :"," when is_top -> &parse_comma/2
                _ -> nil
              end

            do_block = &parse_do_block/2

            case infix do
              nil when is_stab and peek_token_type == :stab_op ->
                parser = Map.put(parser, :stab_state, %{ast: left})
                # this will be ignored on the return
                {left, parser}

              nil ->
                {left, parser}

              ^do_block when parser.nesting != 0 ->
                {left, next_token(parser)}

              _ ->
                infix.(next_token(parser), left)
            end
          end
        else
          {left, parser}
        end
      end

      # |> tap(fn {v, p} -> IO.puts("current_token: #{inspect(p.current_token)}") end)
    end
  end

  defp parse_grouped_expression(parser) do
    trace "parse_grouped_expression", trace_meta(parser) do
      open_range = token_range(parser.current_token)
      opening_paren_meta = current_meta(parser)

      if peek_token(parser) == :")" do
        parser = parser |> next_token() |> eat_eol()
        closing_paren_meta = current_meta(parser)
        close_range = token_range(parser.current_token)

        ast =
          {:__block__, [parens: opening_paren_meta ++ [closing: closing_paren_meta]], []}
          |> attach_range([open_range, close_range])

        {ast, parser}
      else
        orig_meta = current_meta(parser)
        parser = parser |> next_token() |> eat_eol()
        old_nesting = parser.nesting

        parser = Map.put(parser, :nesting, 0)

        {expression, parser} = parse_expression(parser, @lowest, false, false, true)

        expression = push_eoe(expression, peek_eoe(parser))

        cond do
          # if the next token is the closing paren or if the next token is a newline and the next next token is the closing paren
          peek_token(parser) == :")" ||
              (peek_token(parser) == :eol && peek_token(next_token(parser)) == :")") ->
            parser =
              parser
              |> Map.put(:nesting, old_nesting)
              |> next_token()
              |> eat_eol()

            closing_paren_meta = current_meta(parser)
            close_range = token_range(parser.current_token)

            ast =
              case expression do
                # unquote splicing is special cased, if it has one expression as an arg, its wrapped in a block
                {:unquote_splicing, _, [_]} ->
                  {:__block__, [{:closing, current_meta(parser)} | orig_meta], [expression]}

                # not and ! are special cased, if it has one expression as an arg, its wrapped in a block
                {op, _, [_]} when op in [:not, :!] ->
                  {:__block__, [], [expression]}

                {:->, _, _} ->
                  [expression]

                {f, meta, a} ->
                  {f, [parens: opening_paren_meta ++ [closing: closing_paren_meta]] ++ meta, a}

                expression ->
                  expression
              end

            ast =
              case ast do
                {f, meta, args} ->
                  child_ranges = if is_list(args), do: Enum.map(args, &arg_range/1), else: []
                  {f, put_meta_range(meta, merge_ranges([open_range, close_range | child_ranges])), args}

                _ ->
                  ast
              end

            {ast, parser}

          # if the next token is a new line, but the next next token is not the closing paren (implied from previous clause)
          peek_token(parser) == :eol or current_token(parser) == :-> ->
            # second conditon checks of the next next token is a closing paren or another expression
            {exprs, parser} =
              while2 current_token(parser) == :-> ||
                       (peek_token(parser) == :eol &&
                          parser |> next_token() |> peek_token() != :")") <- parser do
                {ast, parser} =
                  case Map.get(parser, :stab_state) do
                    %{ast: lhs} ->
                      {ast, parser} = parse_stab_expression(Map.delete(parser, :stab_state), lhs)

                      {ast, parser} =
                        if current_token(parser) == :-> do
                          {ast, parser}
                        else
                          if peek_token(parser) == :")" do
                            {ast, parser}
                          else
                            eoe = current_eoe(parser)
                            ast = push_eoe(ast, eoe)
                            {ast, next_token(parser)}
                          end
                        end

                      {ast, parser}

                    nil ->
                      parser = parser |> next_token() |> eat_eol()
                      {ast, parser} = parse_expression(parser, @lowest, false, false, true)

                      {ast, parser} =
                        cond do
                          current_token(parser) == :-> ->
                            {ast, parser}

                          peek_token(parser) == :")" ->
                            {ast, parser}

                          true ->
                            eoe = peek_eoe(parser)
                            ast = push_eoe(ast, eoe)
                            {ast, parser}
                        end

                      {ast, parser}
                  end

                {ast, parser}
              end

            # handles if the closing paren is on a new line or the same line
            parser =
              if peek_token(parser) == :eol do
                next_token(parser)
              else
                parser
              end

            if peek_token(parser) == :")" do
              parser =
                parser
                |> Map.put(:nesting, old_nesting)
                |> next_token()

              exprs = [expression | exprs]

              ast =
                case exprs do
                  [{:->, _, _} | _] ->
                    exprs

                  _ ->
                    {:__block__, [{:closing, current_meta(parser)} | orig_meta], exprs}
                end

              close_range = token_range(parser.current_token)

              ast =
                case ast do
                  {f, meta, args} ->
                    child_ranges = if is_list(args), do: Enum.map(args, &arg_range/1), else: []
                    {f, put_meta_range(meta, merge_ranges([open_range, close_range | child_ranges])), args}

                  _ ->
                    ast
                end

              {ast, parser}
            else
              meta = current_meta(parser)

              parser =
                parser
                |> put_error({meta, "missing closing parentheses"})
                |> Map.put(:nesting, old_nesting)

              {{:__block__, [{:error, true} | meta], []}, next_token(parser)}
            end

          true ->
            meta = current_meta(parser)

            parser =
              parser
              |> put_error({meta, "missing closing parentheses"})
              |> Map.put(:nesting, old_nesting)

            {{:__block__, [{:error, true} | meta], []}, next_token(parser)}
        end
      end
    end
  end

  defp parse_nil_literal(%{current_token: {nil, _meta}} = parser) do
    trace "parse_nil_literal", trace_meta(parser) do
      ast = encode_literal(parser, nil)
      {ast, parser}
    end
  end

  defp parse_kw_identifier(%{current_token: {:kw_identifier, _meta, token}} = parser) do
    trace "parse_kw_identifier", trace_meta(parser) do
      range = token_range(parser.current_token)
      token = encode_literal(parser, token, range)
      parser = parser |> next_token() |> eat_eol()

      {expr, parser} = parse_expression(parser, @kw_identifier, false, false, false)
      parser = parser |> Map.put(:produced_kw_pair, true) |> Map.put(:produced_kw_source, :token)
      {{token, expr}, parser}
    end
  end

  defp parse_kw_identifier(%{current_token: {:kw_identifier_unsafe, meta, tokens}} = parser) do
    trace "parse_kw_identifier (unsafe)", trace_meta(parser) do
      {atom, parser} = parse_atom(%{parser | current_token: {:atom_unsafe, meta, tokens}})
      parser = parser |> next_token() |> eat_eol()

      {expr, parser} = parse_expression(parser, @kw_identifier, false, false, false)

      atom =
        case atom do
          {t, meta, args} ->
            {delimiter, meta} = Keyword.pop(meta, :delimiter)
            meta = meta |> Keyword.put(:format, :keyword) |> Keyword.put(:delimiter, delimiter)
            {t, meta, args}
        end

      parser = parser |> Map.put(:produced_kw_pair, true) |> Map.put(:produced_kw_source, :token)
      {{atom, expr}, parser}
    end
  end

  defp parse_keyword_pair(%{current_token: {type, _, _}} = parser)
       when type in [:kw_identifier, :kw_identifier_unsafe] do
    parse_kw_identifier(parser)
  end

  defp parse_keyword_pair(%{current_token: {:bin_string_start, _, _}} = parser) do
    parse_linearized_string(parser, :binary)
  end

  defp parse_keyword_pair(%{current_token: {:list_string_start, _, _}} = parser) do
    parse_linearized_string(parser, :charlist)
  end

  defp parse_bracketless_kw_list(%{current_token: {:kw_identifier, _meta, token}} = parser) do
    trace "parse_bracketless_kw_list", trace_meta(parser) do
      token = encode_literal(parser, token)
      parser = parser |> next_token() |> eat_eol()

      {value, parser} = parse_expression(parser, @kw_identifier, false, false, false)

      {kvs, parser} =
        while2 peek_token(parser) == :"," <- parser do
          parser = parser |> next_token()

          case peek_token(parser) do
            :"]" ->
              {:filter, {nil, parser}}

            _ ->
              parser = next_token(parser)
              {pair, parser} = parse_keyword_pair(parser)

              {pair, parser}
          end
        end

      {[{token, value} | kvs], parser}
    end
  end

  defp parse_bracketless_kw_list(%{current_token: {:kw_identifier_unsafe, meta, tokens}} = parser) do
    trace "parse_bracketless_kw_list (unsafe)", trace_meta(parser) do
      {atom, parser} = parse_atom(%{parser | current_token: {:atom_unsafe, meta, tokens}})
      parser = parser |> next_token() |> eat_eol()

      atom =
        case atom do
          {t, meta, args} ->
            {delimiter, meta} = Keyword.pop(meta, :delimiter)
            meta = meta |> Keyword.put(:format, :keyword) |> Keyword.put(:delimiter, delimiter)
            {t, meta, args}
        end

      {value, parser} = parse_expression(parser, @kw_identifier, false, false, false)

      {kvs, parser} =
        while2 peek_token(parser) == :"," <- parser do
          parser = parser |> next_token()

          case peek_token(parser) do
            :"]" ->
              {:filter, {nil, parser}}

            _ ->
              parser = next_token(parser)
              {pair, parser} = parse_keyword_pair(parser)

              {pair, parser}
          end
        end

      {[{atom, value} | kvs], parser}
    end
  end

  defp parse_assoc_op(%{current_token: {:assoc_op, _, _token}} = parser, key) do
    trace "parse_assoc_op", trace_meta(parser) do
      op_range = token_range(parser.current_token)
      assoc_meta =
        parser
        |> current_meta()
        |> put_meta_range(op_range)

      parser = parser |> next_token() |> eat_eol()
      {value, parser} = parse_expression(parser, @assoc_op, false, false, false)

      {_, assoc_meta, _} = attach_op_range({:assoc, assoc_meta, [key, value]}, op_range)

      key =
        case key do
          {f, meta, args} ->
            {f, [{:assoc, assoc_meta} | meta], args}

          _ ->
            key
        end

      {{key, value}, parser}
    end
  end

  defp(parse_comma_list(parser, precedence \\ @list_comma, is_list \\ false, is_map \\ false))

  defp parse_comma_list(parser, precedence, is_list, is_map) do
    trace "parse_comma_list", trace_meta(parser) do
      {front, parser} = parse_expression(parser, precedence, is_list, is_map, false)

      # track 2-tuple literals for keyword merging avoidance (front element)
      if is_tuple(front) and tuple_size(front) == 2 do
        set = Process.get(:kw_tuple_literals) || MapSet.new()
        Process.put(:kw_tuple_literals, MapSet.put(set, front))
      end

      # we zip together the expression and parser state so that we can potentially
      # backtrack later
      Process.put(:comma_list_parsers, [parser])

      {items, parser} =
        while2 peek_token(parser) == :"," <- parser do
          parser = next_token(parser)

          case peek_token(parser) do
            delimiter when delimiter in [:"]", :"}"] ->
              {:filter, {nil, parser}}

            _ ->
              parser = next_token(parser)
              {item, parser} = parse_expression(parser, precedence, is_list, is_map, false)

              # track 2-tuple literals for keyword merging avoidance
              if is_tuple(item) and tuple_size(item) == 2 do
                set = Process.get(:kw_tuple_literals) || MapSet.new()
                Process.put(:kw_tuple_literals, MapSet.put(set, item))
              end

              clp = Process.get(:comma_list_parsers)
              Process.put(:comma_list_parsers, [parser | clp])

              {item, parser}
          end
        end

      {[front | items], parser}
    end
  end

  # Tuple argument comma-list: detect lone keyword pairs at token-time and wrap them
  # into a keyword list. This mirrors how s2q treats `{1, foo: 1}` as `{1, [foo: 1]}`.
  defp parse_tuple_args_comma_list(parser) do
    trace "parse_tuple_args_comma_list", trace_meta(parser) do
      {first, first_is_kw_pair, parser} = parse_tuple_arg_item(parser)

      Process.put(:comma_list_parsers, [parser])

      {rest, parser} =
        while2 peek_token(parser) == :"," <- parser do
          parser = next_token(parser)

          case peek_token(parser) do
            :"}" ->
              {:filter, {nil, parser}}

            _ ->
              parser = next_token(parser)
              {item, is_kw_pair, parser} = parse_tuple_arg_item(parser)

              clp = Process.get(:comma_list_parsers)
              Process.put(:comma_list_parsers, [parser | clp])

              {{item, is_kw_pair}, parser}
          end
        end

      items = [{first, first_is_kw_pair} | rest]

      # Group trailing keyword pairs into a single keyword list element
      {trailing_kw_rev, rest_rev} =
        items
        |> Enum.reverse()
        |> Enum.split_while(fn {_it, is_kw_pair} -> is_kw_pair end)

      case trailing_kw_rev do
        [] ->
          {Enum.map(items, &elem(&1, 0)), parser}

        _ ->
          trailing_kw = Enum.reverse(trailing_kw_rev) |> Enum.map(&elem(&1, 0))
          leading = Enum.reverse(rest_rev) |> Enum.map(&elem(&1, 0))
          {leading ++ [trailing_kw], parser}
      end
    end
  end

  defp parse_tuple_arg_item(parser) do
    # Reset per-item flag
    parser = Map.put(parser, :produced_kw_pair, false)

    case current_token_type(parser) do
      :kw_identifier ->
        {pair, parser} = parse_kw_identifier(parser)
        {pair, true, parser}

      :kw_identifier_unsafe ->
        {pair, parser} = parse_kw_identifier(parser)
        {pair, true, parser}

      :bin_string_start ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {{is_kw_pair, source}, parser} = pop_kw_pair_flag(parser)
        is_kw_pair = is_kw_pair and source == :string
        {item, is_kw_pair, parser}

      :list_string_start ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {{is_kw_pair, source}, parser} = pop_kw_pair_flag(parser)
        is_kw_pair = is_kw_pair and source == :string
        {item, is_kw_pair, parser}

      _ ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {item, false, parser}
    end
  end

  # Specialized comma-list for function call arguments.
  # It detects trailing keyword pairs (based on token-time flags) and
  # folds them into a single keyword list argument, matching s2q behavior.
  defp parse_fn_args_comma_list(parser) do
    trace "parse_fn_args_comma_list", trace_meta(parser) do
      {first, first_is_kw_pair, parser} = parse_fn_arg_item(parser)

      # Track parsers for potential error backtracking (same as parse_comma_list)
      Process.put(:comma_list_parsers, [parser])

      {rest, parser} =
        while2 peek_token(parser) == :"," <- parser do
          parser = next_token(parser)

          case peek_token(parser) do
            delimiter when delimiter in [:")", :"}"] ->
              {:filter, {nil, parser}}

            _ ->
              parser = next_token(parser)
              {item, is_kw_pair, parser} = parse_fn_arg_item(parser)

              clp = Process.get(:comma_list_parsers)
              Process.put(:comma_list_parsers, [parser | clp])

              {{item, is_kw_pair}, parser}
          end
        end

      items = [{first, first_is_kw_pair} | rest]

      # Split into leading non-keyword args and trailing keyword pairs
      {trailing_kw_rev, rest_rev} =
        items
        |> Enum.reverse()
        |> Enum.split_while(fn {_it, is_kw_pair} -> is_kw_pair end)

      case trailing_kw_rev do
        [] ->
          {Enum.map(items, &elem(&1, 0)), parser}

        _ ->
          trailing_kw = Enum.reverse(trailing_kw_rev) |> Enum.map(&elem(&1, 0))
          leading = Enum.reverse(rest_rev) |> Enum.map(&elem(&1, 0))
          {leading ++ [trailing_kw], parser}
      end
    end
  end

  defp pop_kw_pair_flag(parser) do
    is_kw_pair = Map.get(parser, :produced_kw_pair) == true
    source = Map.get(parser, :produced_kw_source)
    parser = parser |> Map.put(:produced_kw_pair, false) |> Map.put(:produced_kw_source, nil)
    {{is_kw_pair, source}, parser}
  end

  defp parse_fn_arg_item(parser) do
    # Reset per-item keyword flag to avoid leaking state across items/expressions
    parser = Map.put(parser, :produced_kw_pair, false)

    case current_token_type(parser) do
      :kw_identifier ->
        {pair, parser} = parse_kw_identifier(parser)
        {pair, true, parser}

      :kw_identifier_unsafe ->
        {pair, parser} = parse_kw_identifier(parser)
        {pair, true, parser}

      :bin_string_start ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {{is_kw_pair, source}, parser} = pop_kw_pair_flag(parser)
        is_kw_pair = is_kw_pair and source == :string
        {item, is_kw_pair, parser}

      :list_string_start ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {{is_kw_pair, source}, parser} = pop_kw_pair_flag(parser)
        is_kw_pair = is_kw_pair and source == :string
        {item, is_kw_pair, parser}

      _ ->
        {item, parser} = parse_expression(parser, @list_comma, false, false, false)
        {item, false, parser}
    end
  end

  defp parse_prefix_expression(parser) do
    trace "parse_prefix_expression", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)

      precedence =
        if current_token_type(parser) == :dual_op do
          # dual ops are treated as unary ops when being used as a prefix operator
          @unary_op
        else
          current_precedence(parser)
        end

      parser = parser |> next_token() |> eat_eol()
      {rhs, parser} = parse_expression(parser, precedence, false, false, false)

      ast =
        {token, meta, [rhs]}
        |> attach_op_range(op_range)

      {ast, parser}
    end
  end

  defp parse_prefix_lone_identifer(parser) do
    trace "parse_prefix_lone_identifer", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)

      parser = next_token(parser)
      {rhs, parser} = parse_lone_identifier(parser)

      ast =
        {token, meta, [rhs]}
        |> attach_op_range(op_range)

      {ast, parser}
    end
  end

  defp parse_capture_int(parser) do
    trace "parse_capture_int", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)
      parser = next_token(parser)
      {encoder, parser} = Map.pop(parser, :literal_encoder)
      {rhs, parser} = parse_int(parser)
      parser = Map.put(parser, :literal_encoder, encoder)

      ast =
        {token, meta, [rhs]}
        |> attach_op_range(op_range)

      {ast, parser}
    end
  end

  # """
  # A stab expression without a lhs is only possible as the argument to an anonymous function and in the typespect of an anon function

  # ```elixir
  # fn -> :ok end
  # @spec start_link((-> term), GenServer.options()) :: on_start
  # ```
  # """

  defp parse_stab_expression(parser) do
    trace "parse_stab_expression", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)
      newlines = get_newlines(parser)

      parser = eat_at(parser, [:eol, :";"], 1)
      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

      {exprs, parser} =
        while2 peek_token(parser) not in [:end, :")"] <- parser do
          parser = parser |> next_token() |> eat_eol()
          {ast, parser} = parse_expression(parser, @lowest, false, false, true)

          eoe = peek_eoe(parser)

          parser = eat_eol_at(parser, 1)

          ast = push_eoe(ast, eoe)

          {ast, parser}
        end

      rhs = build_block_nr(exprs)

      meta =
        meta
        |> inject_newlines(newlines)
        |> reorder_parens_newlines()

      ast =
        {token, meta, [[], rhs]}
        |> attach_op_range(op_range)

      parser = Map.put(parser, :nesting, old_nesting)

      {ast, parser}
    end
  end

  # """
  # A stab expression with a lhs is present in case, cond, and try blocks, as well as macros and typespecs.

  # The rhs of a stab expression can be a single expression or a block of expressions. The end of the
  # block is denoted by either the `end` keyword or by the start of another "bare" stab expression.

  # ```elixir
  # case foo do
  #   :bar ->
  #     Some.thing()
  #     :ok

  #   :baz ->
  #     Another.thing()
  #     :error
  # end
  # ```
  # """

  defp parse_stab_expression(parser, lhs) do
    trace "parse_stab_expression (with lhs)", trace_meta(parser) do
      token = current_token(parser)
      op_range = token_range(parser.current_token)

      case token do
        :<- ->
          parse_infix_expression(parser, lhs)

        :-> ->
          meta = current_meta(parser)
          newlines = get_newlines(parser)

          parser = eat_eol_at(parser, 1)

          old_nesting = parser.nesting
          parser = Map.put(parser, :nesting, 0)

          {exprs, parser} =
            while2 Map.get(parser, :stab_state) == nil and
                     peek_token(parser) not in [:eof, :end, :")", :block_identifier] <-
                     parser do
              parser = next_token(parser)
              {ast, parser} = parse_expression(parser, @lowest, false, false, true, true)

              if Map.get(parser, :stab_state) == nil do
                eoe = peek_eoe(parser)
                ast = push_eoe(ast, eoe)
                parser = eat_eol_at(parser, 1)

                {ast, eat_eol(parser)}
              else
                {:filter, {nil, next_token(parser)}}
              end
            end

          rhs = build_block_nr(exprs)

          {lhs, meta} =
            case lhs do
              {:when, wmeta, [{:__block__, [{:parens, _} = paren_meta | _], []} | rest]} ->
                # Empty paren args: move parens meta to the stab node and drop the empty block
                {{:when, wmeta, rest}, [paren_meta | meta]}

              {type, [{:parens, _} = paren_meta | _], _}
              when type in [:__block__, :comma] ->
                {lhs, [paren_meta | meta]}

              _ ->
                {lhs, meta}
            end

          lhs =
            case lhs do
              {:__block__, _, []} -> []
              {:comma, _, lhs} -> lhs
              lhs -> [lhs]
            end

          meta =
            meta
            |> inject_newlines(newlines)
            |> reorder_parens_newlines()

          ast =
            {token, meta, [lhs, rhs]}
            |> attach_op_range(op_range)

          parser = Map.put(parser, :nesting, old_nesting)

          {ast, eat_eol(parser)}
      end
    end
  end

  defp parse_comma(parser, lhs) do
    trace "parse_comma", trace_meta(parser) do
      op_range = token_range(parser.current_token)
      parser = parser |> next_token() |> eat_eol()
      {exprs, parser} = parse_comma_list(parser, @comma)

      ast =
        {:comma, [], [lhs | exprs]}
        |> attach_op_range(op_range)

      {ast, eat_eol(parser)}
    end
  end

  defp parse_infix_expression(parser, lhs) do
    trace "parse_infix_expression", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)
      precedence = current_precedence(parser)
      # we save this in case the next expression is an error
      pre_parser = parser

      newlines =
        case current_newlines(parser) || peek_newlines(parser, :eol) do
          nil -> []
          nl -> [newlines: nl]
        end

      parser = parser |> next_token() |> eat_eol()

      {rhs, parser} = parse_expression(parser, precedence, false, false, false)

      {rhs, parser} =
        case rhs do
          {:__block__, [{:error, true} | _], []} ->
            parser =
              put_error(pre_parser, {meta, "malformed right-hand side of #{token} operator"})

            {{:__block__, [{:error, true} | meta], []}, parser}

          _ ->
            {rhs, parser}
        end

      ast =
        case token do
          :"not in" ->
            {in_meta, in_range} =
              case pre_parser do
                # New 4-tuple shape with separate meta for the "in" keyword (Toxic or updated legacy)
                %{current_token: {:in_op, _not_meta, :"not in", info_meta}} ->
                  case info_meta do
                    {{line, col}, {el, ec}, _extra} ->
                      {[line: line, column: col], {{line, col}, {el, ec}}}

                    {line, col, _extra} ->
                      {[line: line, column: col], nil}

                    _ ->
                      {meta, nil}
                  end

                _ ->
                  {meta, nil}
              end

            in_ast = attach_op_range({:in, in_meta, [lhs, rhs]}, in_range)

            {:not, meta, [in_ast]}

          :when ->
            lhs =
              case lhs do
                {:comma, _, lhs} -> lhs
                lhs -> [lhs]
              end

            {token, newlines ++ meta, lhs ++ [rhs]}

          _ ->
            {token, newlines ++ meta, [lhs, rhs]}
        end

      ast = attach_op_range(ast, op_range)

      {ast, parser}
    end
  end

  defp parse_pipe_op(parser, lhs) do
    trace "parse_pipe_op", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)

      newlines =
        case current_newlines(parser) || peek_newlines(parser, :eol) do
          nil -> []
          nl -> [newlines: nl]
        end

      parser = next_token(parser)

      parser = eat_eol(parser)

      {pairs, parser} = parse_comma_list(parser, @list_comma, false, true)

      ast =
        {token, newlines ++ meta, [lhs, pairs]}
        |> attach_op_range(op_range)

      {ast, parser}
    end
  end

  defp parse_access_expression(parser, lhs) do
    trace "parse_access_expression", trace_meta(parser) do
      meta = current_meta(parser)
      open_range = token_range(parser.current_token)
      parser = parser |> next_token() |> eat_eol()

      # Detect keyword list bracket arg at token-time
      {rhs, parser} =
        case current_token_type(parser) do
          type when type in [:kw_identifier, :kw_identifier_unsafe] ->
            parse_bracketless_kw_list(parser)

          type when type in [:bin_string_start, :list_string_start] ->
            # Parse potentially quoted keyword pair, then collect additional pairs separated by commas
            {first, is_kw, parser1} = parse_fn_arg_item(parser)

            if is_kw do
              {kvs, parser2} =
                while2 peek_token(parser1) == :"," <- parser1 do
                  parser1 = parser1 |> next_token()

                  case peek_token(parser1) do
                    :"]" ->
                      {:filter, {nil, parser1}}

                    _ ->
                      parser1 = next_token(parser1)

                      case current_token_type(parser1) do
                        type
                        when type in [
                               :kw_identifier,
                               :kw_identifier_unsafe,
                               :bin_string_start,
                               :list_string_start
                             ] ->
                          parse_keyword_pair(parser1)

                        _ ->
                          {:filter, {nil, parser1}}
                      end
                  end
                end

              {[first | kvs], parser2}
            else
              # Not a keyword pair, treat entire content as container expr from original state
              parse_expression(parser, @lowest, false, false, false)
            end

          _ ->
            parse_expression(parser, @lowest, false, false, false)
        end

      extra_meta = [from_brackets: true]

      newlines =
        case peek_newlines(parser, :eol) do
          nil -> []
          nl -> [newlines: nl]
        end

      # Optional trailing comma allowed only for container_expr variant; we conservatively allow it
      parser =
        if peek_token(parser) == :"," do
          parser |> next_token() |> eat_eol()
        else
          parser
        end

      parser = parser |> next_token() |> eat_eol()
      closing = current_meta(parser)
      close_range = token_range(parser.current_token)
      meta = extra_meta ++ newlines ++ [{:closing, closing} | meta]
      range = merge_ranges([ast_range(lhs), open_range, close_range, arg_range(rhs)])
      meta = put_meta_range(meta, range)

      ast =
        {{:., meta, [Access, :get]}, meta, [lhs, rhs]}
        |> attach_range([range])

      {ast, parser}
    end
  end

  defp parse_range_expression(parser) do
    trace "parse_range_expression", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)

      ast =
        {token, meta, []}
        |> attach_op_range(op_range)

      {ast, parser}
    end
  end

  defp parse_range_expression(parser, lhs) do
    trace "parse_range_expression (with lhs)", trace_meta(parser) do
      token = current_token(parser)
      meta = current_meta(parser)
      op_range = token_range(parser.current_token)
      precedence = current_precedence(parser)
      parser = next_token(parser)
      {rhs, parser} = parse_expression(parser, precedence, false, false, false)

      {ast, parser} =
        case peek_token(parser) do
          :ternary_op ->
            parser = parser |> next_token() |> next_token()
            {rrhs, parser} = parse_expression(parser, precedence, false, false, false)
            {{:..//, meta, [lhs, rhs, rrhs]}, eat_eol(parser)}

          _ ->
            {{token, meta, [lhs, rhs]}, eat_eol(parser)}
        end

      ast = attach_op_range(ast, op_range)

      {ast, parser}
    end
  end

  # Do Block Algorithm: The Movie
  #
  # A do block consists of the keyword `do`, following by 0 or more expressions
  # separated by newlines/semicolons, followed by 0 or more block identifier
  # (else, rescue, after, catch) + 0 or more expressions separated by newlines/semicolons
  # and concluded with the keyword `end`
  #
  # - beginning of parse function, current_token = :do
  # - encode `:do` literal in case of literal_encoder
  # - save the old nesting level and insert a 0
  # - enter outer loop
  #   - the job of the outer loop is to collect the expressions for each do+block_identifier
  #     (from now on just referred to as block_identifier)
  #   - else, start inner loop
  #     - each iteration of the loop continues if the peek token (while eating an eol) is not in end, block_identifier, or eof
  #     - increment the token, and eat the eol token
  #     - if the current token is end or a block_identifier, then the expression
  #       list is empty. return the expressions and end the iteration
  #     - else, parse the current expression
  #       - each iteration of the loop continues if the peek token is not in end, block_identifier, or eof
  #       - increment the token, and eat the eol token
  #       - if stab_state
  #         - we are in the body of a stab expression, don't increment and parse the stab
  #       - else
  #         - parse expression
  #         - push eoe of the next token, but don't actually increment the parser
  #     - end inner loop
  #   - encode block_identifier and save as {type, expressions}
  #   - end outer loop
  # - if current token is block_identifier, that means the last section was empty. encode the token
  #   and create an empty list of expressions
  # - assert peek token is end
  # - various clean up and metadata

  defp parse_do_block(%{current_token: {:do, _meta}} = parser, lhs) do
    trace "parse_do_block", trace_meta(parser) do
      do_meta = current_meta(parser)
      do_range = token_range(parser.current_token)
      type = encode_literal(parser, :do)

      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

      {exprs, {_, parser}} =
        while2 peek_token_eat_eol(parser) not in [:end, :eof] <- {type, parser} do
          {exprs, parser} =
            while2 peek_token_eat_eol(parser) not in [:end, :block_identifier, :eof] <- parser do
              {ast, parser} =
                case Map.get(parser, :stab_state) do
                  %{ast: lhs} ->
                    parse_stab_expression(Map.delete(parser, :stab_state), lhs)

                  nil ->
                    parser = parser |> next_token() |> eat_eol()
                    parse_expression(parser, @lowest, false, false, true)
                end

              temp_parser = next_token(parser)
              eoe = current_eoe(temp_parser)
              ast = push_eoe(ast, eoe)

              {ast, parser}
            end

          case peek_token_eat_eol(parser) do
            :block_identifier ->
              parser = parser |> next_token() |> eat_eol()
              {:block_identifier, _meta, token} = parser.current_token
              {{type, exprs}, {encode_literal(parser, token), parser}}

            _ ->
              {{type, exprs}, {type, parser}}
          end
        end

      extra_exprs =
        if current_token_type(parser) == :block_identifier do
          {:block_identifier, _meta, token} = parser.current_token
          [{encode_literal(parser, token), []}]
        else
          []
        end

      {parser, end_meta} =
        if peek_token_eat_eol(parser) == :end do
          parser = parser |> next_token() |> eat_eol()
          {parser, current_meta(parser)}
        else
          {put_error(parser, {do_meta, "missing `end` for do block"}), do_meta}
        end

      end_range =
        case parser.current_token do
          {:end, _} -> token_range(parser.current_token)
          _ -> nil
        end

      exprs =
        case exprs ++ extra_exprs do
          [] -> [{type, []}]
          exprs -> exprs
        end

      exprs =
        for {type, expr} <- exprs do
          {type, build_block_nr(expr)}
        end

      ast =
        case lhs do
          {token, meta, nil} ->
            {token, [do: do_meta, end: end_meta] ++ meta, [exprs]}

          {token, meta, args} when is_list(args) ->
            {token, [do: do_meta, end: end_meta] ++ meta, args ++ [exprs]}
        end

      ast =
        case ast do
          {form, meta, args} ->
            callee_range = ast_range(lhs)
            child_ranges = Enum.map(args, &arg_range/1)
            range = merge_ranges([callee_range, do_range, end_range | child_ranges])
            {form, put_meta_range(meta, range), args}

          _ ->
            ast
        end

      parser = Map.put(parser, :nesting, old_nesting)
      {ast, parser}
    end
  end

  defp parse_dot_expression(parser, lhs) do
    trace "parse_dot_expression", trace_meta(parser) do
      token = current_token(parser)
      precedence = current_precedence(parser)
      meta = current_meta(parser)
      dot_range = token_range(token)
      lhs_range = ast_range(lhs)

      case peek_token_type(parser) do
        :quoted_identifier_start ->
          # Handle remote calls with quoted identifiers: D."foo", D."foo"(1), D."foo"[1], D."foo" + 1, D."foo" do ... end
          parser = next_token(parser)
          id_start_meta = current_meta(parser)
          id_start_range = token_range(parser.current_token)

          {:quoted_identifier_start, _m, h} = parser.current_token

          delim_str = <<h>>

          # Scan the quoted identifier and classify its end
          # Advance past the start token to the first content token
          parser = next_token(parser)
          {parts, parser, end_type} = scan_linearized_identifier(parser)
          content = build_identifier_content(parts)
          callee_range = merge_ranges([id_start_range, token_range(parser.current_token)])

          callee_atom =
            if is_binary(content), do: String.to_atom(content), else: :interpolated_identifier

          base_call_meta = [{:delimiter, delim_str} | id_start_meta]
          build_dot_ast = fn dot_meta ->
            {token, dot_meta, [lhs, callee_atom]}
            |> attach_range([lhs_range, dot_range, callee_range])
          end

          # Decide argument parsing strategy based on end_type and upcoming tokens
          case end_type do
            :quoted_paren_identifier_end ->
              # Build call like regular paren_identifier: use dot ast as callee with dot's own meta.
              # Then rewrite the returned call meta to include delimiter and identifier start meta.
              dot_ast = build_dot_ast.(meta)
              parser1 = next_token(parser)

              case current_token(parser1) do
                :"(" ->
                  {{lhs_dot, call_meta, args}, parser2} = parse_call_expression(parser1, dot_ast)

                  # Preserve newlines and closing from call_meta, but replace base meta with base_call_meta
                  newlines =
                    case Keyword.get(call_meta, :newlines) do
                      nil -> []
                      nl -> [newlines: nl]
                    end

                  closing = Keyword.get(call_meta, :closing)
                  new_meta =
                    newlines
                    |> Kernel.++([{:closing, closing} | base_call_meta])
                    |> put_meta_range(meta_range(call_meta))

                  ast = {lhs_dot, new_meta, args}
                  ast = attach_range(ast, [ast_range(lhs_dot) | Enum.map(args, &arg_range/1)])
                  {ast, parser2}

                _ ->
                  # No actual parens; treat as no-parens call site
                  ast =
                    dot_ast
                    |> put_elem(1, [no_parens: true] ++ base_call_meta)
                    |> attach_range([lhs_range, dot_range, callee_range])

                  {ast, parser1}
              end

            :quoted_bracket_identifier_end ->
              # Inner remote call is a no-parens call site; expect a following "[".
              inner_meta = [no_parens: true] ++ base_call_meta
              dot_ast = build_dot_ast.(meta)
              base_ast = {dot_ast, inner_meta, []}
              base_ast = attach_range(base_ast, [ast_range(dot_ast)])
              parser1 = next_token(parser)

              case current_token(parser1) do
                :"[" ->
                  parse_access_expression(parser1, base_ast)

                _ ->
                  {base_ast, parser1}
              end

            :quoted_do_identifier_end ->
              # Expect a following :do; otherwise fall back to no-parens call-site.
              dot_ast = build_dot_ast.(meta)
              base_ast = {dot_ast, base_call_meta, []} |> attach_range([ast_range(dot_ast)])
              parser1 = next_token(parser)

              case current_token_type(parser1) do
                :do ->
                  parse_do_block(parser1, base_ast)

                _ ->
                  ast =
                    base_ast
                    |> put_elem(1, [no_parens: true] ++ base_call_meta)
                    |> attach_range([ast_range(elem(base_ast, 0))])

                  {ast, parser1}
              end

            :quoted_op_identifier_end ->
              # Always parse at least one argument (operator identifier semantics)
              # Drop the end token; then parse first argument
              parser = next_token(parser)
              parser = push_nesting(parser)
              {front, parser} = parse_expression(parser, @lowest, false, false, false)

              {rest, parser} =
                while2 peek_token(parser) == :"," <- parser do
                  parser = next_token(parser)
                  parser = next_token(parser)
                  parse_expression(parser, @lowest, false, false, false)
                end

              parser = pop_nesting(parser)
              dot_ast = build_dot_ast.(meta)
              base_ast = {dot_ast, base_call_meta, []}
              ast =
                base_ast
                |> put_elem(2, List.wrap(front) ++ List.wrap(rest))
                |> attach_range([ast_range(dot_ast) | Enum.map(List.wrap(front) ++ List.wrap(rest), &arg_range/1)])

              {ast, parser}

            _ ->
              # :quoted_identifier_end and any other: behave like plain identifier,
              # but allow op-identifier style no-parens when a unary op follows.
              dot_ast = build_dot_ast.(meta)
              base_ast = {dot_ast, base_call_meta, []}

              if peek_token_type(parser) == :unary_op do
                # Consume end token to reach the unary op and parse at least one arg
                parser = next_token(parser)
                parser = push_nesting(parser)
                {front, parser} = parse_expression(parser, @lowest, false, false, false)

                {rest, parser} =
                  while2 peek_token(parser) == :"," <- parser do
                    parser = next_token(parser)
                    parser = next_token(parser)
                    parse_expression(parser, @lowest, false, false, false)
                  end

                parser = pop_nesting(parser)
                ast =
                  base_ast
                  |> put_elem(2, List.wrap(front) ++ List.wrap(rest))
                  |> attach_range([ast_range(dot_ast) | Enum.map(List.wrap(front) ++ List.wrap(rest), &arg_range/1)])

                {ast, parser}
              else
                ast =
                  base_ast
                  |> put_elem(1, [no_parens: true] ++ base_call_meta)
                  |> attach_range([ast_range(dot_ast)])

                {ast, parser}
              end
          end

        # if the next token is an open brace, we are in a multi alias situation `alias Foo.{Bar, Baz}`
        # technically the contents of the braces can be anything, so we parse them as anything
        :"{" ->
          dot_meta = current_meta(parser)
          parser = next_token(parser)
          open_range = token_range(parser.current_token)
          newlines = get_newlines(parser)

          parser = parser |> next_token() |> eat_eol()
          if current_token(parser) == :"}" do
            closing = current_meta(parser)
            close_range = token_range(parser.current_token)

            dot_ast =
              {:., dot_meta, [lhs, :{}]}
              |> attach_range([lhs_range, dot_range, open_range, close_range])

            multis =
              {dot_ast,
               newlines ++ [{:closing, closing} | dot_meta], []}
              |> attach_range([ast_range(dot_ast), open_range, close_range])

            {multis, parser}
          else
            {multis_list, parser} = parse_comma_list(parser)
            parser = parser |> next_token() |> eat_eol()
            close_range = token_range(parser.current_token)

            closing_meta = current_meta(parser)

            dot_ast =
              {:., dot_meta, [lhs, :{}]}
              |> attach_range([lhs_range, dot_range, open_range, close_range])

            multis =
              {dot_ast,
               newlines ++ [{:closing, closing_meta} | dot_meta], multis_list}
              |> attach_range(
                [ast_range(dot_ast), open_range, close_range | Enum.map(multis_list, &arg_range/1)]
              )

            {multis, parser}
          end

        # if the next token is an alias, then we are in a dot chain of aliases, eg: __MODULE__.Foo
        :alias ->
          parser = next_token(parser)

          {{:__aliases__, ameta, aliases} = rhs_alias, parser} = parse_alias(parser)

          last = ameta[:last]
          ast =
            {:__aliases__, [{:last, last} | meta], [lhs | aliases]}
            |> attach_range([lhs_range, dot_range, ast_range(rhs_alias)])

          {ast, parser}

        # if the next token is a bracket_identifier, then we know that the whole dot expression needs to be used as an argument for the access expression. eg, foo.bar[:baz]
        :bracket_identifier ->
          parser = next_token(parser)
          ident_meta = current_meta(parser)
          rhs_range = token_range(parser.current_token)

          %{current_token: {:bracket_identifier, _, rhs_ident}} = parser

          dot_ast =
            {token, meta, [lhs, rhs_ident]}
            |> attach_range([lhs_range, dot_range, rhs_range])

          rhs =
            {dot_ast, [no_parens: true] ++ ident_meta, []}
            |> attach_range([ast_range(dot_ast)])

          parser = next_token(parser)
          {ast, parser} = parse_access_expression(parser, rhs)

          {ast, eat_eol(parser)}

        type when type in [:identifier, :paren_identifier, :do_identifier] ->
          parser = next_token(parser)

          {{rhs_form, rhs_meta, rhs_args} = rhs_ast, parser} =
            parse_expression(parser, precedence, false, false, false)

          args =
            if rhs_args == nil do
              []
            else
              rhs_args
            end

          extra =
            if type in [:identifier, :do_identifier] && args == [] do
              [no_parens: true]
            else
              []
            end

          callee_ast =
            {token, meta, [lhs, rhs_form]}
            |> attach_range([lhs_range, dot_range, ast_range(rhs_ast)])

          ast =
            {callee_ast, extra ++ rhs_meta, args}
            |> attach_range([ast_range(callee_ast) | Enum.map(args, &arg_range/1)])

          {ast, parser}

        _ ->
          # Default: consume dot and parse RHS expression. If RHS is a quoted identifier,
          # attach no_parens + delimiter metadata to the call site and use atom as callee.
          parser = next_token(parser)
          base_meta = current_meta(parser)
          quoted? = current_token_type(parser) == :quoted_identifier_start

          delim_str =
            if quoted? do
              case parser.current_token do
                {:quoted_identifier_start, _m, h} when is_integer(h) -> <<h>>
                {:quoted_identifier_start, _m, d} when is_binary(d) -> d
                _ -> ~S'"'
              end
            else
              nil
            end

          {rhs, parser} = parse_expression(parser, @lowest, false, false, false)
          rhs_range = arg_range(rhs)

          call_meta =
            if quoted?, do: [no_parens: true, delimiter: delim_str] ++ base_meta, else: base_meta

          callee_ast =
            {token, meta, [lhs, rhs]}
            |> attach_range([lhs_range, dot_range, rhs_range])

          ast =
            {callee_ast, call_meta, []}
            |> attach_range([ast_range(callee_ast)])

          {ast, parser}
      end
    end
  end

  defp parse_anon_function(%{current_token: {:fn, _}} = parser) do
    trace "parse_anon_function", trace_meta(parser) do
      meta = current_meta(parser)
      fn_range = token_range(parser.current_token)

      newlines = get_newlines(parser)
      parser = parser |> next_token() |> eat_eol()

      {exprs, parser} =
        while2 current_token(parser) not in [:end, :eof] <- parser do
          {ast, parser} =
            case Map.get(parser, :stab_state) do
              %{ast: lhs} ->
                {ast, parser} = parse_stab_expression(Map.delete(parser, :stab_state), lhs)

                {ast, parser} =
                  if current_token(parser) == :-> do
                    {ast, parser}
                  else
                    if peek_token(parser) == :end do
                      parser = next_token(parser)
                      {ast, parser}
                    else
                      parser = next_token(parser)
                      eoe = current_eoe(parser)
                      ast = push_eoe(ast, eoe)
                      {ast, eat_eol(parser)}
                    end
                  end

                {ast, parser}

              nil ->
                {ast, parser} = parse_expression(parser, @lowest, false, false, true)

                {ast, parser} =
                  if current_token(parser) in [:->] do
                    {ast, parser}
                  else
                    if peek_token(parser) == :end do
                      parser = next_token(parser)
                      {ast, parser}
                    else
                      parser = next_token(parser)
                      eoe = current_eoe(parser)
                      ast = push_eoe(ast, eoe)
                      {ast, eat_eol(parser)}
                    end
                  end

                {ast, parser}
            end

          {ast, parser}
        end

      {parser, meta} =
        case current_token(parser) do
          :end ->
            {parser, [{:closing, current_meta(parser)} | meta]}

          _ ->
            {put_error(parser, {meta, "missing closing end for anonymous function"}), meta}
        end

      end_range =
        case parser.current_token do
          {:end, _} -> token_range(parser.current_token)
          _ -> nil
        end

      ast =
        {:fn, newlines ++ meta, exprs}
        |> attach_range([fn_range, end_range | Enum.map(exprs, &arg_range/1)])

      {ast, parser}
    end
  end

  defp parse_dot_call_expression(parser, lhs) do
    trace "parse_dot_call_expression", trace_meta(parser) do
      meta = current_meta(parser)
      dot_range = token_range(parser.current_token)
      lhs_range = ast_range(lhs)
      parser = next_token(parser)
      open_range = token_range(parser.current_token)
      newlines = get_newlines(parser)

      parser = eat_eol(parser)

      if peek_token(parser) == :")" do
        parser = next_token(parser)
        closing = [closing: current_meta(parser)]
        close_range = token_range(parser.current_token)

        callee_ast =
          {:., meta, [lhs]}
          |> attach_range([lhs_range, dot_range, open_range, close_range])

        ast =
          {callee_ast, newlines ++ closing ++ meta, []}
          |> attach_range([ast_range(callee_ast), open_range, close_range])

        {ast, parser}
      else
        {pairs, parser} =
          parser
          |> next_token()
          |> eat_eol()
          |> parse_fn_args_comma_list()

        parser = parser |> next_token() |> eat_eol()
        closing = [closing: current_meta(parser)]
        close_range = token_range(parser.current_token)

        callee_ast =
          {:., meta, [lhs]}
          |> attach_range([lhs_range, dot_range, open_range, close_range])

        ast =
          {callee_ast, newlines ++ closing ++ meta, pairs}
          |> attach_range(
            [ast_range(callee_ast), open_range, close_range | Enum.map(pairs, &arg_range/1)]
          )

        {ast, parser}
      end
    end
  end

  defp parse_atom(%{current_token: {:atom, _meta, atom}} = parser) do
    trace "parse_atom", trace_meta(parser) do
      atom = encode_literal(parser, atom)
      {atom, parser}
    end
  end

  defp parse_atom(%{current_token: {:atom_quoted, _meta, atom}} = parser) do
    trace "parse_atom (quoted)", trace_meta(parser) do
      atom = encode_literal(parser, atom)
      {atom, parser}
    end
  end

  defp parse_atom(%{current_token: {:atom_unsafe, _, tokens}} = parser) do
    trace "parse_atom (unsafe)", trace_meta(parser) do
      range = token_range(parser.current_token)
      meta = parser |> current_meta() |> put_meta_range(range)
      {args, parser} = parse_interpolation(parser, tokens)

      {{{:., meta, [:erlang, :binary_to_atom]}, [{:delimiter, ~S'"'} | meta],
        [{:<<>>, meta, args}, :utf8]}, parser}
    end
  end

  defp parse_boolean(%{current_token: {bool, _meta}} = parser) do
    trace "parse_boolean", trace_meta(parser) do
      bool = encode_literal(parser, bool)

      {bool, parser}
    end
  end

  defp parse_int(%{current_token: {:int, {_, _, int}, _}} = parser) do
    trace "parse_int", trace_meta(parser) do
      int = encode_literal(parser, int)
      {int, parser}
    end
  end

  defp parse_float(%{current_token: {:flt, {_, _, float}, _}} = parser) do
    trace "parse_float", trace_meta(parser) do
      float = encode_literal(parser, float)
      {float, parser}
    end
  end

  defp parse_string(%{current_token: {:bin_heredoc, _meta, _indent, [string]}} = parser) do
    trace "parse_string (bin_heredoc)", trace_meta(parser) do
      string = encode_literal(parser, string)
      {string, parser}
    end
  end

  defp parse_string(%{current_token: {:list_heredoc, _meta, _indent, [string]}} = parser) do
    trace "parse_string (list_heredoc)", trace_meta(parser) do
      string = encode_literal(parser, String.to_charlist(string))
      {string, parser}
    end
  end

  defp parse_string(%{current_token: {:bin_heredoc, _meta, indentation, tokens}} = parser) do
    trace "parse_string (bin_heredoc w/interpolation)", trace_meta(parser) do
      meta = current_meta(parser)

      {args, parser} = parse_interpolation(parser, tokens)

      meta =
        if indentation != nil do
          [{:indentation, indentation} | meta]
        else
          meta
        end

      {{:<<>>, [{:delimiter, ~s|"""|} | meta], args}, parser}
    end
  end

  defp parse_string(%{current_token: {:list_heredoc, _meta, indentation, tokens}} = parser) do
    trace "parse_string (list_heredoc w/interpolation)", trace_meta(parser) do
      meta = current_meta(parser)

      args =
        for token <- tokens do
          case token do
            token when is_binary(token) ->
              token

            {{line, col, _}, {cline, ccol, _}, tokens} ->
              meta = put_meta_range([line: line, column: col], {{line, col}, {cline, ccol}})
              # construct a new parser
              ast =
                if tokens == [] do
                  {:__block__, [], []}
                else
                  parser =
                    %{
                      stream: Spitfire.TokenStream.from_tokens(tokens),
                      start_line: line,
                      start_column: col,
                      current_token: nil,
                      peek_token: nil,
                      nesting: 0,
                      fuel: 150,
                      errors: [],
                      last_span: nil,
                      literal_encoder: parser.literal_encoder,
                      interpolation_depth: 0,
                      saved_nesting_stack: []
                    }
                    |> next_token()
                    |> next_token()
                    |> eat_eol()

                  {ast, parser} = parse_expression(parser)
                  ast = push_eoe(ast, peek_eoe(parser))
                  ast
                end

              {{:., meta, [Kernel, :to_string]},
               [from_interpolation: true, closing: [line: cline, column: ccol]] ++ meta, [ast]}
          end
        end

      extra_meta =
        if indentation != nil do
          [indentation: indentation]
        else
          []
        end

      {{{:., meta, [List, :to_charlist]}, [{:delimiter, ~s|'''|} | extra_meta ++ meta], [args]},
       parser}
    end
  end

  defp parse_string(%{current_token: {:bin_string, _meta, [string]}} = parser)
       when is_binary(string) do
    trace "parse_string (bin_string)", trace_meta(parser) do
      string = encode_literal(parser, string)
      {string, parser}
    end
  end

  defp parse_string(%{current_token: {:bin_string, _, tokens}} = parser) do
    trace "parse_string (bin_string w/interpolation)", trace_meta(parser) do
      meta = current_meta(parser)

      {args, parser} = parse_interpolation(parser, tokens)

      {{:<<>>, [{:delimiter, "\""} | meta], args}, parser}
    end
  end

  defp parse_string(%{current_token: {:list_string, _meta, [string]}} = parser) do
    trace "parse_string (list_string)", trace_meta(parser) do
      string = encode_literal(parser, String.to_charlist(string))
      {string, parser}
    end
  end

  defp parse_string(%{current_token: {:list_string, _, tokens}} = parser) do
    trace "parse_string (list_string w/interpolation)", trace_meta(parser) do
      meta = current_meta(parser)

      args =
        for token <- tokens do
          case token do
            token when is_binary(token) ->
              token

            {{line, col, _}, {cline, ccol, _}, tokens} ->
              meta = put_meta_range([line: line, column: col], {{line, col}, {cline, ccol}})
              # construct a new parser
              ast =
                if tokens == [] do
                  {:__block__, [], []}
                else
                  parser =
                    %{
                      stream: Spitfire.TokenStream.from_tokens(tokens),
                      start_line: line,
                      start_column: col,
                      current_token: nil,
                      peek_token: nil,
                      nesting: 0,
                      fuel: 150,
                      errors: [],
                      last_span: nil,
                      literal_encoder: parser.literal_encoder,
                      interpolation_depth: 0,
                      saved_nesting_stack: []
                    }
                    |> next_token()
                    |> next_token()
                    |> eat_eol()

                  {ast, parser} = parse_expression(parser)
                  ast = push_eoe(ast, peek_eoe(parser))
                  ast
                end

              {{:., meta, [Kernel, :to_string]},
               [from_interpolation: true, closing: [line: cline, column: ccol]] ++ meta, [ast]}
          end
        end

      {{{:., meta, [List, :to_charlist]}, [{:delimiter, "'"} | meta], [args]}, parser}
    end
  end

  defp parse_char(%{current_token: {:char, {_, _, _token}, num}} = parser) do
    trace "parse_char", trace_meta(parser) do
      char = encode_literal(parser, num)
      {char, parser}
    end
  end

  defp parse_sigil(
         %{current_token: {:sigil, _meta, token, tokens, mods, indentation, delimiter}} = parser
       ) do
    trace "parse_sigil", trace_meta(parser) do
      meta = current_meta(parser)

      {args, parser} = parse_interpolation(parser, tokens)

      bs_meta =
        if indentation != nil do
          [{:indentation, indentation} | meta]
        else
          meta
        end

      ast = {token, Keyword.put(meta, :delimiter, delimiter), [{:<<>>, bs_meta, args}, mods]}
      {ast, parser}
    end
  end

  defp parse_alias(%{current_token: {:alias, _, alias}} = parser) do
    trace "parse_alias", trace_meta(parser) do
      range = token_range(parser.current_token)

      meta =
        parser
        |> current_meta()
        |> put_meta_range(range)

      Process.put(:alias_last_meta, meta)

      {aliases, parser} =
        while2 peek_token(parser) == :. && peek_token(next_token(parser)) == :alias <- parser do
          parser = next_token(parser)

          case parser.peek_token do
            {:alias, _, alias} ->
              parser = next_token(parser)
              meta = put_meta_range(current_meta(parser), token_range(parser.current_token))
              Process.put(:alias_last_meta, meta)
              {alias, parser}
          end
        end

      aliases = [alias | aliases]

      {{:__aliases__, [{:last, Process.get(:alias_last_meta)} | meta], aliases}, parser}
    end
  after
    Process.delete(:alias_last_meta)
  end

  defp parse_bitstring(%{current_token: {:"<<", _} = open_token} = parser) do
    trace "parse_bitstring", trace_meta(parser) do
      meta = current_meta(parser)
      open_range = token_range(open_token)
      orig_parser = parser
      newlines = get_newlines(parser)
      parser = parser |> next_token() |> eat_eol()

      cond do
        current_token(parser) == :">>" ->
          close_range = token_range(parser.current_token)
          container_range = container_range(open_range, close_range)
          {{:<<>>, put_meta_range(newlines ++ [{:closing, current_meta(parser)} | meta], container_range), []}, parser}

        current_token(parser) in [:end, :"}", :")", :"]"] ->
          # if the current token is the wrong kind of ending delimiter, we revert to the previous parser
          # state, put an error, and inject a closing bracket to simulate a completed list
          parser = put_error(orig_parser, {meta, "missing closing brackets for bitstring"})

          parser = next_token(parser)

          parser =
            parser
            |> put_in([:current_token], {:fake_closing_brackets, nil})
            |> put_in([:peek_token], parser.current_token)
            |> update_in([:stream], &Spitfire.TokenStream.push_back(&1, [parser.peek_token]))

          # For error recovery, use the error position as close_range
          close_range = token_range(parser.current_token)
          container_range = container_range(open_range, close_range)
          {{:<<>>, put_meta_range([{:closing, current_meta(parser)} | meta], container_range), []}, parser}

        true ->
          old_comma_list_parsers = Process.get(:comma_list_parsers)
          {pairs, parser} = parse_comma_list(parser, @list_comma, true, false)

          case peek_token_eat_eol(parser) do
            :">>" ->
              parser = eat_eol_at(parser, 1)
              parser = next_token(parser)
              close_range = token_range(parser.current_token)
              container_range = container_range(open_range, close_range, arg_range(pairs))

              {{:<<>>, put_meta_range(newlines ++ [{:closing, current_meta(parser)} | meta], container_range), pairs},
               eat_eol(parser)}

            _ ->
              all_pairs = pairs |> Enum.reverse() |> Enum.zip(Process.get(:comma_list_parsers))

              {pairs, parser} =
                with [{potential_error, parser}, {item, parser_for_errors} | rest] <- all_pairs,
                     {:__block__, [{:error, true} | _], []} <- potential_error do
                  {[{item, parser} | rest],
                   parser
                   |> put_in([:current_token], {:fake_closing_bracket, nil})
                   |> put_in([:peek_token], parser.current_token)
                   |> put_in([:errors], parser_for_errors.errors)
                   |> update_in(
                     [:stream],
                     &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                   )}
                else
                  _ ->
                    parser = next_token(parser)

                    {all_pairs,
                     parser
                     |> put_in([:current_token], {:">>", nil})
                     |> put_in([:peek_token], parser.current_token)
                     |> update_in(
                       [:stream],
                       &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                     )}
                end

              Process.put(:comma_list_parsers, old_comma_list_parsers)

              parser = put_error(parser, {meta, "missing closing brackets for bitstring"})

              {pairs, _} = pairs |> Enum.reverse() |> Enum.unzip()

              close_range = token_range(parser.current_token)
              container_range = container_range(open_range, close_range, arg_range(pairs))

              {{:<<>>, put_meta_range(newlines ++ [{:closing, current_meta(parser)} | meta], container_range), List.wrap(pairs)},
               parser}
          end
      end
    end
  end

  defp parse_map_literal(%{current_token: {:%{}, _} = open_token} = parser) do
    trace "parse_map_literal", trace_meta(parser) do
      meta = current_meta(parser)
      open_range = token_range(open_token)
      parser = next_token(parser)
      # we use a then to create lexical scoping to
      # hide manipulating incrementing the parser
      newlines = peek_newlines(parser)

      parser = parser |> next_token() |> eat_eol()
      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

      if current_token(parser) == :"}" do
        close_range = token_range(parser.current_token)
        container_range = container_range(open_range, close_range)
        closing = current_meta(parser)
        parser = Map.put(parser, :nesting, old_nesting)

        extra =
          if newlines do
            [{:newlines, newlines}, {:closing, closing}]
          else
            [{:closing, closing}]
          end

        {{:%{}, put_meta_range(extra ++ meta, container_range), []}, parser}
      else
        {pairs, parser} = parse_comma_list(parser, @list_comma, false, true)

        parser = eat_eol_at(parser, 1)

        parser =
          case peek_token(parser) do
            :"}" ->
              next_token(parser)

            _ ->
              put_error(parser, {current_meta(parser), "missing closing brace for map"})
          end

        close_range = token_range(parser.current_token)
        container_range = container_range(open_range, close_range, arg_range(pairs))
        closing = current_meta(parser)
        parser = Map.put(parser, :nesting, old_nesting)

        extra =
          if newlines do
            [{:newlines, newlines}, {:closing, closing}]
          else
            [{:closing, closing}]
          end

        {{:%{}, put_meta_range(extra ++ meta, container_range), pairs}, parser}
      end
    end
  end

  defp parse_struct_type(parser) do
    trace "parse_struct_type", trace_meta(parser) do
      # structs can only have certain expressions to denote the type,
      # so we special case them here rather than parse an arbitrary expression

      {associativity, precedence} = @lowest

      prefix =
        case current_token_type(parser) do
          :identifier -> &parse_lone_identifier/1
          :paren_identifier -> &parse_paren_identifier/1
          :atom -> &parse_atom/1
          :atom_quoted -> &parse_atom/1
          :atom_unsafe -> &parse_atom/1
          :atom_safe_start -> &parse_linearized_atom(&1, :safe)
          :atom_unsafe_start -> &parse_linearized_atom(&1, :unsafe)
          :alias -> &parse_alias/1
          :at_op -> &parse_lone_module_attr/1
          :unary_op -> &parse_prefix_lone_identifer/1
          _ -> nil
        end

      if prefix == nil do
        meta = current_meta(parser)
        ctype = current_token_type(parser)
        parser = put_error(parser, {meta, "unknown token: #{ctype}"})

        parser =
          case ctype do
            :")" -> parser
            :"]" -> parser
            :"}" -> parser
            :">>" -> parser
            :end -> parser
            _ -> next_token(parser)
          end

        {{:__block__, [], []}, parser}
      else
        {left, parser} = prefix.(parser)

        terminals = [:eol, :eof, :"}", :")", :"]", :">>"]

        {parser, is_valid} = validate_peek(parser, current_token_type(parser))

        if is_valid do
          while peek_token(parser) not in terminals &&
                  calc_prec(parser, associativity, precedence) <- {left, parser} do
            infix =
              case peek_token_type(parser) do
                :. -> &parse_dot_expression/2
                _ -> nil
              end

            case infix do
              nil ->
                {left, parser}

              _ ->
                infix.(next_token(parser), left)
            end
          end
        else
          {left, parser}
        end
      end
    end
  end

  defp parse_ellipsis_op(parser) do
    trace "parse_ellipsis_op", trace_meta(parser) do
      meta =
        parser
        |> current_meta()
        |> put_meta_range(token_range(parser.current_token))

      {{:..., meta, []}, parser}
    end
  end

  defp parse_struct_literal(%{current_token: {:%, _} = percent_token} = parser) do
    trace "parse_struct_literal", trace_meta(parser) do
      meta = current_meta(parser)
      percent_range = token_range(percent_token)
      parser = next_token(parser)
      {type, parser} = parse_struct_type(parser)

      parser = next_token(parser)

      brace_meta = current_meta(parser)
      brace_open_range = token_range(parser.current_token)

      # Fast-path empty struct: %Type{}
      if peek_token(parser) == :"}" do
        parser = next_token(parser)
        brace_close_range = token_range(parser.current_token)
        map_range = container_range(brace_open_range, brace_close_range)
        struct_range = merge_ranges([percent_range, map_range, ast_range(type)])
        closing = current_meta(parser)

        ast = {:%, put_meta_range(meta, struct_range), [type, {:%{}, put_meta_range([{:closing, closing} | brace_meta], map_range), []}]}

        {ast, parser}
      else
        parser = next_token(parser)

        newlines =
          case current_newlines(parser) do
            nil -> []
            nl -> [newlines: nl]
          end

        parser = eat_eol(parser)

      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

        if current_token(parser) == :"}" do
          brace_close_range = token_range(parser.current_token)
          map_range = container_range(brace_open_range, brace_close_range)
          struct_range = merge_ranges([percent_range, map_range, ast_range(type)])
          closing = current_meta(parser)
          ast = {:%, put_meta_range(meta, struct_range), [type, {:%{}, put_meta_range(newlines ++ [{:closing, closing} | brace_meta], map_range), []}]}
          parser = Map.put(parser, :nesting, old_nesting)
          {ast, parser}
        else
          {pairs, parser} = parse_comma_list(parser, @list_comma, false, true)

          parser = eat_eol_at(parser, 1)

          parser =
            case peek_token(parser) do
              :"}" ->
                next_token(parser)

              _ ->
                put_error(parser, {current_meta(parser), "missing closing brace for struct"})
            end

          brace_close_range = token_range(parser.current_token)
          map_range = container_range(brace_open_range, brace_close_range, arg_range(pairs))
          struct_range = merge_ranges([percent_range, map_range, ast_range(type)])
          closing = current_meta(parser)
          ast = {:%, put_meta_range(meta, struct_range), [type, {:%{}, put_meta_range(newlines ++ [{:closing, closing} | brace_meta], map_range), pairs}]}
          parser = Map.put(parser, :nesting, old_nesting)
          {ast, parser}
        end
      end
    end
  end

  defp parse_tuple_literal(%{current_token: {:"{", _orig_meta} = open_token} = parser) do
    trace "parse_tuple_literal", trace_meta(parser) do
      meta = current_meta(parser)
      open_range = token_range(open_token)
      orig_parser = parser
      newlines = peek_newlines(parser)

      parser = parser |> next_token() |> eat_eol()
      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

      cond do
        current_token(parser) == :"}" ->
        close_range = token_range(parser.current_token)
        container_range = container_range(open_range, close_range)
          closing = current_meta(parser)
          parser = Map.put(parser, :nesting, old_nesting)

          extra =
            if newlines do
              [{:newlines, newlines}, {:closing, closing}]
            else
              [{:closing, closing}]
            end

          {{:{}, put_meta_range(extra ++ meta, container_range), []}, parser}

        current_token(parser) in [:end, :"]", :")", :">>"] ->
          # if the current token is the wrong kind of ending delimiter, we revert to the previous parser
          # state, put an error, and inject a closing brace to simulate a completed tuple
          parser = put_error(orig_parser, {meta, "missing closing brace for tuple"})

          parser = next_token(parser)

          parser =
            parser
            |> put_in([:current_token], {:fake_closing_brace, nil})
            |> put_in([:peek_token], parser.current_token)
            |> update_in([:stream], &Spitfire.TokenStream.push_back(&1, [parser.peek_token]))

          # For error recovery, use the error position as close_range
          close_range = token_range(parser.current_token)
          container_range = container_range(open_range, close_range)
          parser = put_in(parser.nesting, old_nesting)
          {{:{}, put_meta_range(meta, container_range), []}, parser}

        true ->
          old_comma_list_parsers = Process.get(:comma_list_parsers)
          {pairs, parser} = parse_tuple_args_comma_list(parser)

          {pairs, parser} =
            case peek_token_eat_eol(parser) do
              :"}" ->
                parser = eat_eol_at(parser, 1)
                {pairs, parser |> next_token() |> eat_eol()}

              _ ->
                all_pairs = pairs |> Enum.reverse() |> Enum.zip(Process.get(:comma_list_parsers))

                {pairs, parser} =
                  with [{potential_error, parser}, {item, parser_for_errors} | rest] <- all_pairs,
                       {:__block__, [{:error, true} | _], []} <- potential_error do
                    {[{item, parser} | rest],
                     parser
                     |> put_in([:current_token], {:fake_closing_brace, nil})
                     |> put_in([:peek_token], parser.current_token)
                     |> put_in([:errors], parser_for_errors.errors)
                     |> update_in(
                       [:stream],
                       &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                     )}
                  else
                    _ ->
                      parser = next_token(parser)

                      {all_pairs,
                       parser
                       |> put_in([:current_token], {:"}", nil})
                       |> put_in([:peek_token], parser.current_token)
                       |> update_in(
                         [:stream],
                         &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                       )}
                  end

                Process.put(:comma_list_parsers, old_comma_list_parsers)

                parser = put_error(parser, {meta, "missing closing brace for tuple"})

                {pairs, _} = Enum.unzip(pairs)

                {Enum.reverse(pairs), parser}
            end

          if length(pairs) == 2 do
            close_range = token_range(parser.current_token)
            container_range = container_range(open_range, close_range, arg_range(pairs))
            closing_meta = current_meta(parser)

            tuple =
              %{parser | current_token: open_token}
              |> encode_literal(pairs |> List.wrap() |> List.to_tuple(), container_range)
              |> put_closing_meta(closing_meta)
              |> attach_range([container_range])

            parser = Map.put(parser, :nesting, old_nesting)
            {tuple, parser}
          else
            close_range = token_range(parser.current_token)
            container_range = container_range(open_range, close_range, arg_range(pairs))
            closing = current_meta(parser)
            parser = Map.put(parser, :nesting, old_nesting)

            extra =
              if newlines do
                [{:newlines, newlines}, {:closing, closing}]
              else
                [{:closing, closing}]
              end

            {{:{}, put_meta_range(extra ++ meta, container_range), List.wrap(pairs)}, parser}
          end
      end
    end
  end

  defp parse_list_literal(%{current_token: {:"[", _orig_meta} = open_token} = parser) do
    trace "parse_list_literal", trace_meta(parser) do
      meta = current_meta(parser)
      open_range = token_range(open_token)
      orig_parser = parser
      parser = parser |> next_token() |> eat_eol()
      old_nesting = parser.nesting
      parser = Map.put(parser, :nesting, 0)

      encode_list = fn values, parser_state, close_range, closing_meta ->
        container_range = container_range(open_range, close_range, arg_range(values))

        %{parser_state | current_token: open_token}
        |> encode_literal(values, container_range)
        |> put_closing_meta(closing_meta)
        |> attach_range([container_range])
      end

      cond do
        current_token(parser) == :"]" ->
          close_range = token_range(parser.current_token)
          closing_meta = current_meta(parser)
          parser = Map.put(parser, :nesting, old_nesting)
          {encode_list.([], parser, close_range, closing_meta), parser}

        current_token(parser) in [:end, :"}", :")", :">>"] ->
          # if the current token is the wrong kind of ending delimiter, we revert to the previous parser
          # state, put an error, and inject a closing bracket to simulate a completed list
          parser = put_error(orig_parser, {meta, "missing closing bracket for list"})

          parser = next_token(parser)

          parser =
            parser
            |> put_in([:current_token], {:fake_closing_bracket, nil})
            |> put_in([:peek_token], parser.current_token)
            |> update_in([:stream], &Spitfire.TokenStream.push_back(&1, [parser.peek_token]))

          parser = Map.put(parser, :nesting, old_nesting)
          close_range = token_range(parser.current_token)
          closing_meta = current_meta(parser)
          {encode_list.([], parser, close_range, closing_meta), parser}

        true ->
          old_comma_list_parsers = Process.get(:comma_list_parsers)
          {pairs, parser} = parse_comma_list(parser, @list_comma, true, false)

          case peek_token_eat_eol(parser) do
            :"]" ->
              parser = eat_eol_at(parser, 1)
              close_range = token_range(parser.peek_token)
              closing_meta = current_meta(%{parser | current_token: parser.peek_token})
              parser = Map.put(parser, :nesting, old_nesting)
              {encode_list.(pairs, parser, close_range, closing_meta), next_token(parser)}

            _ ->
              all_pairs = pairs |> Enum.reverse() |> Enum.zip(Process.get(:comma_list_parsers))

              {pairs, parser} =
                with [{potential_error, parser}, {item, parser_for_errors} | rest] <- all_pairs,
                     {:__block__, [{:error, true} | _meta], []} <- potential_error do
                  {[{item, parser} | rest],
                   parser
                   |> put_in([:current_token], {:fake_closing_bracket, nil})
                   |> put_in([:peek_token], parser.current_token)
                   |> put_in([:errors], parser_for_errors.errors)
                   |> update_in(
                     [:stream],
                     &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                   )}
                else
                  _ ->
                    parser = next_token(parser)

                    {all_pairs,
                     parser
                     |> put_in([:current_token], {:"]", nil})
                     |> put_in([:peek_token], parser.current_token)
                     |> update_in(
                       [:stream],
                       &Spitfire.TokenStream.push_back(&1, [parser.peek_token])
                     )}
                end

              Process.put(:comma_list_parsers, old_comma_list_parsers)

              parser = put_error(parser, {meta, "missing closing bracket for list"})

              {pairs, _} = Enum.unzip(pairs)

              pairs = Enum.reverse(pairs)
              parser = Map.put(parser, :nesting, old_nesting)
              close_range = token_range(parser.current_token)
              closing_meta = current_meta(parser)
              {encode_list.(pairs, parser, close_range, closing_meta), parser}
          end
      end
    end
  end

  defp parse_paren_identifier(%{current_token: {:paren_identifier, token_meta, token}} = parser) do
    trace "parse_paren_identifier", trace_meta(parser) do
      callee_range = token_range(parser.current_token)
      meta =
        parser
        |> current_meta()
        |> push_delimiter(token_meta)

      parser = next_token(parser)
      open_range = token_range(parser.current_token)
      newlines = get_newlines(parser)
      error_meta = current_meta(parser)

      if peek_token(parser) == :")" do
        parser = next_token(parser)
        closing = current_meta(parser)
        close_range = token_range(parser.current_token)
        ast = {token, newlines ++ [{:closing, closing} | meta], []}
        ast = attach_range(ast, [callee_range, open_range, close_range])

        if peek_token(parser) == :do and parser.nesting == 0 do
          parser = next_token(parser)
          parse_do_block(parser, ast)
        else
          {ast, parser}
        end
      else
        old_nesting = parser.nesting
        parser = Map.put(parser, :nesting, 0)

        {pairs, parser} =
          parser
          |> next_token()
          |> eat_eol()
          |> parse_fn_args_comma_list()

        parser = Map.put(parser, :nesting, old_nesting)

        parser = eat_eol_at(parser, 1)

        case peek_token(parser) do
          :")" ->
            parser = next_token(parser)
            closing = current_meta(parser)
            close_range = token_range(parser.current_token)

            ast = {token, newlines ++ [{:closing, closing} | meta], pairs}
            ast = attach_range(ast, [callee_range, open_range, close_range | Enum.map(pairs, &arg_range/1)])

            if peek_token(parser) == :do and parser.nesting == 0 do
              parser = next_token(parser)
              parse_do_block(parser, ast)
            else
              {ast, parser}
            end

          _ ->
            parser =
              put_error(
                parser,
                {error_meta, "missing closing parentheses for function invocation"}
              )

            ast = {token, newlines ++ meta, pairs}
            ast = attach_range(ast, [callee_range, open_range | Enum.map(pairs, &arg_range/1)])
            {ast, parser}
        end
      end
    end
  end

  @operators [
    :"=>",
    :->,
    :+,
    :**,
    :-,
    :/,
    :*,
    :|>,
    :++,
    :||,
    :&&,
    :and,
    :or,
    :**,
    :range_op,
    :power_op,
    :stab_op,
    :xor_op,
    :rel_op,
    :and_op,
    :or_op,
    :mult_op,
    :arrow_op,
    :assoc_op,
    :pipe_op,
    :concat_op,
    :dual_op,
    :ternary_op,
    :in_op,
    :in_match_op,
    :comp_op,
    :match_op,
    :type_op,
    :dot_call_op,
    :when_op
  ]

  @peeks MapSet.new(
           [:";", :eol, :eof, :end, :",", :")", :do, :., :"}", :"]", :">>"] ++ @operators
         )

  defp parse_identifier(%{current_token: {_identifier, _, token}} = parser)
       when token in [:__MODULE__, :__ENV__, :__DIR__, :__CALLER__] do
    trace "parse_identifier (__MODULE__, etc)", trace_meta(parser) do
      parse_lone_identifier(parser)
    end
  end

  defp parse_identifier(%{current_token: {identifier, _, token}} = parser)
       when identifier in [:identifier, :op_identifier] do
    trace "parse_identifier (#{identifier})", trace_meta(parser) do
      stop_peek? =
        MapSet.member?(@peeks, peek_token(parser)) ||
          (parser.interpolation_depth > 0 and peek_token_type(parser) == :end_interpolation)

      if identifier == :identifier && stop_peek? do
        parse_lone_identifier(parser)
      else
        meta = current_meta(parser)
        callee_range = token_range(parser.current_token)
        parser = next_token(parser)

        parser = push_nesting(parser)
        {first_arg, first_is_kw, parser} = parse_fn_arg_item(parser)

        {rest_items, parser} =
          while2 peek_token(parser) == :"," <- parser do
            parser = next_token(parser)
            parser = next_token(parser)
            {item, is_kw, parser} = parse_fn_arg_item(parser)
            {{item, is_kw}, parser}
          end

        items = [{first_arg, first_is_kw} | rest_items]

        {trailing_kw_rev, rest_rev} =
          items
          |> Enum.reverse()
          |> Enum.split_while(fn {_it, is_kw} -> is_kw end)

        args =
          case trailing_kw_rev do
            [] ->
              Enum.map(items, &elem(&1, 0))

            _ ->
              trailing_kw = Enum.reverse(trailing_kw_rev) |> Enum.map(&elem(&1, 0))
              leading = Enum.reverse(rest_rev) |> Enum.map(&elem(&1, 0))
              leading ++ [trailing_kw]
          end

        parser = pop_nesting(parser)

        # In no-parens calls followed by a do-block, ensure :do is the current token.
        parser =
          if parser.nesting == 0 and current_token(parser) != :do and peek_token(parser) == :do do
            next_token(parser)
          else
            parser
          end

        ast =
          if parser.nesting == 0 && current_token(parser) == :do do
            {token, meta, args}
          else
            meta =
              if identifier == :op_identifier && length(args) == 1 do
                [{:ambiguous_op, nil} | meta]
              else
                meta
              end

            {token, meta, args}
          end
          |> attach_range([callee_range | Enum.map(args, &arg_range/1)])

        if parser.nesting == 0 && current_token(parser) == :do do
          parse_do_block(parser, ast)
        else
          {ast, parser}
        end
      end
    end
  end

  defp parse_do_identifier(%{current_token: {:do_identifier, _, token}} = parser) do
    trace "parse_do_identifier - nesting[#{parser.nesting}]", trace_meta(parser) do
      meta =
        parser
        |> current_meta()
        |> put_meta_range(token_range(parser.current_token))

      parser = next_token(parser)

      # if nesting is 0, that means we are not currently an argument for a function call
      # and can assume we are a "lone do_identifier" and parse the block
      # foo do
      #   :ok
      # end

      if parser.nesting == 0 do
        parse_do_block(parser, {token, meta, []})
      else
        {{token, meta, nil}, parser}
      end
    end
  end

  defp parse_call_expression(%{current_token: {:"(", _}} = parser, lhs) do
    trace "parse_call_expression", trace_meta(parser) do
      # this might be wrong, but its how Code.string_to_quoted works
      {_, meta, _} = lhs
      meta = Keyword.delete(meta, :closing)

      newlines = get_newlines(parser)
      callee_range = ast_range(lhs)
      open_range = token_range(parser.current_token)

      if peek_token(parser) == :")" do
        parser = next_token(parser)
        closing = current_meta(parser)
        close_range = token_range(parser.current_token)

        ast = {lhs, newlines ++ [{:closing, closing} | meta], []}

        ast =
          attach_range(ast, [callee_range, open_range, close_range])

        {ast, parser}
      else
        {pairs, parser} =
          parser
          |> next_token()
          |> eat_eol()
          |> parse_fn_args_comma_list()

        parser = eat_eol_at(parser, 1)

        parser =
          case peek_token(parser) do
            :")" ->
              next_token(parser)

            _ ->
              put_error(parser, {meta, "missing closing parentheses for function invocation"})
          end

        closing = current_meta(parser)
        close_range = token_range(parser.current_token)

        ast = {lhs, newlines ++ [{:closing, closing} | meta], pairs}

        ast =
          attach_range(ast, [callee_range, open_range, close_range | Enum.map(pairs, &arg_range/1)])

        {ast, parser}
      end
    end
  end

  defp parse_lone_identifier(%{current_token: {_type, token_meta, token}} = parser) do
    trace "parse_lone_identifier", trace_meta(parser) do
      range = token_range(parser.current_token)

      meta =
        parser
        |> current_meta()
        |> push_delimiter(token_meta)
        |> put_meta_range(range)

      {{token, meta, nil}, parser}
    end
  end

  defp parse_lone_module_attr(%{current_token: {:at_op, _, token}} = parser) do
    trace "parse_lone_module_attr", trace_meta(parser) do
      meta =
        parser
        |> current_meta()
        |> put_meta_range(token_range(parser.current_token))

      parser = next_token(parser)
      {ident, parser} = parse_lone_identifier(parser)
      {{token, meta, [ident]}, parser}
    end
  end

  # Legacy string interpolation parsing (for non-Toxic tokenizer tokens)
  # Ranges ARE attached via put_meta_range for each interpolated expression
  # This is only used in non-linearized string contexts (legacy heredocs/strings)
  defp parse_interpolation(parser, tokens) do
    trace "parse_interpolation", trace_meta(parser) do
      args =
        for token <- tokens do
          case token do
            token when is_binary(token) ->
              token

            {{line, col, _}, {cline, ccol, _}, tokens} ->
              meta = put_meta_range([line: line, column: col], {{line, col}, {cline, ccol}})

              # construct a new parser
              ast =
                if tokens == [] do
                  {:__block__, [], []}
                else
                  parser =
                    %{
                      stream: Spitfire.TokenStream.from_tokens(tokens),
                      start_line: line,
                      start_column: col,
                      current_token: nil,
                      peek_token: nil,
                      nesting: 0,
                      fuel: 150,
                      errors: [],
                      last_span: nil,
                      literal_encoder: parser.literal_encoder,
                      interpolation_depth: 0,
                      saved_nesting_stack: []
                    }
                    |> next_token()
                    |> next_token()
                    |> eat_eol()

                  {ast, parser} = parse_expression(parser)
                  ast = push_eoe(ast, peek_eoe(parser))
                  ast
                end

              {:"::", meta,
               [
                 {{:., meta, [Kernel, :to_string]},
                  [from_interpolation: true, closing: [line: cline, column: ccol]] ++ meta,
                  [ast]},
                 {:binary, meta, nil}
               ]}
          end
        end

      {args, parser}
    end
  end

  # Linearized token parsing functions for Toxic integration

  # Shared scanner for linearized constructs (strings, atoms, sigils, etc.)
  # end_tokens may be a single atom or a list of acceptable end token types.
  defp scan_linearized(parser, end_tokens, kind, opts \\ []) do
    trace "scan_linearized (#{inspect(end_tokens)})", trace_meta(parser) do
      accumulator = []
      scan_loop(parser, accumulator, List.wrap(end_tokens), kind, opts)
    end
  end

  defp scan_loop(parser, accumulator, end_tokens, kind, opts) do
    case current_token_type(parser) do
      :string_fragment ->
        # Grab fragment content from the full token tuple, not the token type
        {:string_fragment, _tok_meta, content} = parser.current_token
        meta = current_meta(parser)

        # Unescape content unless it's a sigil
        content = if opts[:no_unescape], do: content, else: unescape_fragment(content)

        # For heredocs, trim whitespace using indent from end token (handled later)
        parser = next_token(parser)
        scan_loop(parser, [{:fragment, meta, content} | accumulator], end_tokens, kind, opts)

      :begin_interpolation ->
        # 1. Push interpolation depth
        parser = %{parser | interpolation_depth: parser.interpolation_depth + 1}

        # 2. Save and reset nesting
        saved_nesting = parser.nesting

        parser = %{
          parser
          | nesting: 0,
            saved_nesting_stack: [saved_nesting | parser.saved_nesting_stack]
        }

        # 3. Consume :begin_interpolation token
        open_meta = current_meta(parser)
        open_range = token_range(parser.current_token)
        parser = next_token(parser)
        # Eat any immediate EOLs after opening interpolation
        parser = eat_eol(parser)

        # 4. Parse expression with :end_interpolation as terminal (unless empty)
        empty_interp? = current_token_type(parser) == :end_interpolation

        {expr, parser} =
          if empty_interp? do
            {{:__block__, [], []}, parser}
          else
            {e, p} = parse_expression(parser)
            # Attach end_of_expression metadata for fidelity with legacy (non-empty only)
            {push_eoe(e, peek_eoe(p)), p}
          end

        # 5. Skip any trailing EOLs (for non-empty), then expect and consume :end_interpolation
        parser = if empty_interp?, do: parser, else: eat_eol_at(parser, 1)

        {end_meta, end_range, parser} =
          cond do
            current_token_type(parser) == :end_interpolation ->
              # Current is the closing marker (empty interpolation)
              {current_meta(parser), token_range(parser.current_token), next_token(parser)}

            peek_token_type(parser) == :end_interpolation ->
              # Closing marker is at peek; advance to it and then past it
              parser = next_token(parser)
              {current_meta(parser), token_range(parser.current_token), next_token(parser)}

            true ->
              # Error: expected :end_interpolation
              parser = put_error(parser, {current_meta(parser), "expected end of interpolation"})
              # Synthesize a closing meta/range from current position for recovery
              {current_meta(parser), token_range(parser.current_token), parser}
          end

        # 6. Restore nesting and pop depth
        [saved | rest] = parser.saved_nesting_stack

        parser = %{
          parser
          | nesting: saved,
            saved_nesting_stack: rest,
            interpolation_depth: parser.interpolation_depth - 1
        }

        # 7. Build interpolation AST based on kind
        interp_ast = build_interpolation_ast(expr, open_meta, end_meta || open_meta, open_range, end_range, kind)

        scan_loop(
          parser,
          [{:interpolation, end_meta || open_meta, interp_ast} | accumulator],
          end_tokens,
          kind,
          opts
        )

      token ->
        if token in end_tokens do
          # Found the end token - extract metadata and return WITHOUT consuming it.
          # Leaving the end token as current allows callers to make context-specific
          # decisions (e.g., parse keyword value, check sigil modifiers, or parse infix).
          end_meta = current_meta(parser)

          end_info =
            case parser.current_token do
              {t, _m, _delim, indent}
              when t in [:bin_heredoc_end, :list_heredoc_end, :sigil_end] ->
                %{indentation: indent}

              _ ->
                %{}
            end

          {Enum.reverse(accumulator), parser, end_meta, token, end_info}
        else
          # Unexpected token - error recovery
          parser =
            put_error(
              parser,
              {current_meta(parser), "unexpected token in #{kind}: #{current_token_type(parser)}"}
            )

          {Enum.reverse(accumulator), parser, nil, nil, %{}}
        end
    end
  end

  # Helper function to build interpolation AST based on construct type
  defp build_interpolation_ast(expr, open_meta, end_meta, open_range, end_range, kind) do
    interp_range = merge_ranges([open_range, end_range, ast_range(expr)])
    range_meta = put_meta_range(open_meta, interp_range)
    call_meta = [from_interpolation: true, closing: end_meta] ++ range_meta

    case kind do
      :binary ->
        {:"::", range_meta,
         [
           {{:., range_meta, [Kernel, :to_string]}, call_meta, [expr]},
           {:binary, range_meta, nil}
         ]}
        |> attach_range([interp_range])

      :charlist ->
        {{:., range_meta, [Kernel, :to_string]}, call_meta, [expr]}
        |> attach_range([interp_range])

      :atom ->
        {:"::", range_meta,
         [
           {{:., range_meta, [Kernel, :to_string]}, call_meta, [expr]},
           {:binary, range_meta, nil}
         ]}
        |> attach_range([interp_range])

      :sigil ->
        {:"::", range_meta,
         [
           {{:., range_meta, [Kernel, :to_string]}, call_meta, [expr]},
           {:binary, range_meta, nil}
         ]}
        |> attach_range([interp_range])

      _ ->
        expr
    end
  end

  # Helper function to unescape string fragments (placeholder for now)
  defp unescape_fragment(content) do
    # TODO: error handling
    Macro.unescape_string(content)
  end

  # Helper function to build string parts from scanned fragments and interpolations
  defp build_string_parts(parts, _kind) do
    for part <- parts do
      case part do
        {:fragment, _meta, content} when is_binary(content) ->
          # String fragment - return as literal
          content

        {:interpolation, _meta, ast} ->
          # Interpolation - return the AST
          ast

        _ ->
          # Unexpected part type
          ""
      end
    end
  end

  # Helper function to trim whitespace from heredoc parts based on indentation
  # This needs to process all parts together to track line start state correctly
  defp trim_heredoc_parts(parts, indentation) do
    indent = indentation || 0

    if indent <= 0 do
      parts
    else
      {trimmed_parts, _at_line_start, _spaces_left} =
        trim_heredoc_parts_loop(parts, indent, true, indent, [])

      Enum.reverse(trimmed_parts)
    end
  end

  # Process parts sequentially, maintaining line start state across fragments and interpolations
  defp trim_heredoc_parts_loop([part | rest], indent, at_line_start, spaces_left, acc) do
    case part do
      {:fragment, meta, content} ->
        {trimmed_content, new_at_line_start, new_spaces_left} =
          trim_heredoc_fragment(content, indent, at_line_start, spaces_left)

        new_part = {:fragment, meta, trimmed_content}

        trim_heredoc_parts_loop(rest, indent, new_at_line_start, new_spaces_left, [new_part | acc])

      interpolation ->
        # Interpolation counts as content on this line; no more trimming after it on this line
        new_at_line_start = false
        trim_heredoc_parts_loop(rest, indent, new_at_line_start, 0, [interpolation | acc])
    end
  end

  defp trim_heredoc_parts_loop([], _indent, at_line_start, spaces_left, acc) do
    {acc, at_line_start, spaces_left}
  end

  # Trim up to `indentation` leading spaces/tabs from each line, maintaining state
  defp trim_heredoc_fragment(content, indent, at_line_start, spaces_left) do
    chars = :binary.bin_to_list(content)

    {rev_chars, final_at_line_start, final_spaces_left} =
      trim_chars(chars, indent, at_line_start, spaces_left, [])

    trimmed_content = rev_chars |> Enum.reverse() |> :erlang.list_to_binary()
    {trimmed_content, final_at_line_start, final_spaces_left}
  end

  defp trim_chars([?\n | rest], indent, _at_line_start, _spaces_left, acc) do
    # Newline resets indentation trimming for next characters
    trim_chars(rest, indent, true, indent, [?\n | acc])
  end

  defp trim_chars([ch | rest], indent, true, spaces_left, acc)
       when spaces_left > 0 and (ch == ?\s or ch == ?\t) do
    # Trim up to indent horizontal spaces at start of line
    trim_chars(rest, indent, true, spaces_left - 1, acc)
  end

  defp trim_chars([ch | rest], indent, _at_line_start, spaces_left, acc) do
    # Regular character - keep and mark that we're no longer at line start
    trim_chars(rest, indent, false, spaces_left, [ch | acc])
  end

  defp trim_chars([], _indent, at_line_start, spaces_left, acc) do
    {acc, at_line_start, spaces_left}
  end

  # Special scanner for identifiers that can have multiple end token types
  defp scan_linearized_identifier(parser) do
    accumulator = []
    scan_identifier_loop(parser, accumulator)
  end

  defp scan_identifier_loop(parser, accumulator) do
    case current_token_type(parser) do
      :string_fragment ->
        {:string_fragment, _tok_meta, content} = parser.current_token
        meta = current_meta(parser)
        content = unescape_fragment(content)
        parser = next_token(parser)
        scan_identifier_loop(parser, [{:fragment, meta, content} | accumulator])

      :begin_interpolation ->
        # Handle interpolation (simplified for identifiers)
        open_meta = current_meta(parser)
        open_range = token_range(parser.current_token)
        parser = next_token(parser)
        {expr, parser} = parse_expression(parser)

        if peek_token_type(parser) == :end_interpolation do
          parser = next_token(parser)
          end_meta = current_meta(parser)
          end_range = token_range(parser.current_token)
          parser = next_token(parser)
          interp_ast = build_interpolation_ast(expr, open_meta, end_meta, open_range, end_range, :identifier)
          scan_identifier_loop(parser, [{:interpolation, end_meta, interp_ast} | accumulator])
        else
          parser =
            put_error(
              parser,
              {current_meta(parser), "expected end of interpolation in identifier"}
            )

          {Enum.reverse(accumulator), parser, :quoted_identifier_end}
        end

      end_token
      when end_token in [
             :quoted_identifier_end,
             :quoted_paren_identifier_end,
             :quoted_bracket_identifier_end,
             :quoted_op_identifier_end,
             :quoted_do_identifier_end
           ] ->
        # Do NOT consume the end token here; leave it as current so callers can
        # decide how to handle/look ahead without skipping the following token.
        {Enum.reverse(accumulator), parser, end_token}

      _ ->
        # Unexpected token
        parser =
          put_error(
            parser,
            {current_meta(parser),
             "unexpected token in identifier: #{current_token_type(parser)}"}
          )

        {Enum.reverse(accumulator), parser, :quoted_identifier_end}
    end
  end

  # Helper function to build identifier content from parts
  defp build_identifier_content(parts) do
    case parts do
      [{:fragment, _meta, content}] when is_binary(content) ->
        # Simple case - just a string
        content

      _ ->
        # Complex case with interpolations - for now just concatenate fragments
        # TODO: Handle interpolations properly
        Enum.map_join(parts, "", fn
          {:fragment, _meta, content} -> content
          {:interpolation, _meta, _ast} -> "#{:interpolated}"
        end)
    end
  end

  defp parse_linearized_string(parser, kind) do
    trace "parse_linearized_string (#{kind})", trace_meta(parser) do
      start_token = parser.current_token
      start_meta = current_meta(parser)
      open_range = token_range(start_token)

      # Consume the start token
      parser = next_token(parser)

      # Determine end token based on kind
      end_token =
        case kind do
          :binary -> :bin_string_end
          :charlist -> :list_string_end
        end

      # Scan the linearized content; accept kw_identifier_*_end for strings used as keyword keys
      end_tokens =
        case kind do
          :binary -> [:kw_identifier_safe_end, :kw_identifier_unsafe_end, end_token]
          :charlist -> [:kw_identifier_safe_end, :kw_identifier_unsafe_end, end_token]
        end

      {parts, parser, _end_meta, end_type, _end_info} = scan_linearized(parser, end_tokens, kind)
      close_range = token_range(parser.current_token)
      container_range = container_range(open_range, close_range)

      cond do
        end_type in [:kw_identifier_safe_end, :kw_identifier_unsafe_end] ->
          # Quoted keyword identifier: build atom key and parse the value, return a pair
          has_only_fragments =
            Enum.all?(parts, fn
              {:fragment, _m, _c} -> true
              _ -> false
            end)

          key_ast =
            if has_only_fragments do
              merged = parts |> Enum.map(fn {:fragment, _m, c} -> c end) |> IO.iodata_to_binary()
              atom_value = String.to_atom(merged)
              encode_literal(parser, atom_value, container_range)
            else
              args = build_string_parts(parts, :atom)
              binary_ast = {:<<>>, start_meta, args}
              meta_with_delimiter = [{:delimiter, ~S'"'}, {:format, :keyword} | start_meta]

              {{:., start_meta, [:erlang, :binary_to_atom]}, meta_with_delimiter,
               [binary_ast, :utf8]}
            end
            |> put_start_position(start_meta)
            |> attach_range([container_range])

          # We left the end token as current; consume it and eat EOLs before the value
          parser = parser |> next_token() |> eat_eol()
          # Parse the value with kw_identifier precedence
          {value, parser} = parse_expression(parser, @kw_identifier, false, false, false)

          parser =
            parser |> Map.put(:produced_kw_pair, true) |> Map.put(:produced_kw_source, :string)

          {{key_ast, value}, parser}

        parts == [] ->
          # Empty string
          literal = if kind == :binary, do: "", else: []
          ast = encode_literal(parser, literal, container_range) |> put_start_position(start_meta)
          {attach_range(ast, [container_range]), parser}

        Enum.all?(parts, fn
          {:fragment, _m, _c} -> true
          _ -> false
        end) ->
          # Only fragments, no interpolation: return literal to match s2q
          merged =
            parts
            |> Enum.map(fn {:fragment, _m, c} -> c end)
            |> IO.iodata_to_binary()

          literal = if kind == :binary, do: merged, else: String.to_charlist(merged)
          ast = encode_literal(parser, literal, container_range) |> put_start_position(start_meta)
          {attach_range(ast, [container_range]), parser}

        true ->
          # Interpolated or multi-part: build AST
          args = build_string_parts(parts, kind)

          case kind do
            :binary ->
              meta_with_delimiter = [{:delimiter, "\""} | start_meta]
              {{:<<>>, meta_with_delimiter, args}, parser}

            :charlist ->
              meta_with_delimiter = [{:delimiter, "'"} | start_meta]
              {{{:., start_meta, [List, :to_charlist]}, meta_with_delimiter, [args]}, parser}
          end
      end
    end
  end

  defp parse_linearized_heredoc(parser, kind) do
    trace "parse_linearized_heredoc (#{kind})", trace_meta(parser) do
      start_token = parser.current_token
      start_meta = current_meta(parser)
      open_range = token_range(start_token)

      # Consume the start token
      parser = next_token(parser)

      # Determine end token based on kind
      end_token =
        case kind do
          :binary -> :bin_heredoc_end
          :charlist -> :list_heredoc_end
        end

      # Scan the linearized content; avoid unescape so we can trim first
      {parts, parser, _end_meta, _end_type, end_info} =
        scan_linearized(parser, end_token, kind, no_unescape: true)

      close_range = token_range(parser.current_token)
      container_range = container_range(open_range, close_range)

      # Extract indentation from end token
      indentation = Map.fetch!(end_info, :indentation)

      # Apply indentation trimming to fragments
      trimmed_parts = trim_heredoc_parts(parts, indentation)

      # Unescape all binary fragments after trimming
      unescaped_parts =
        Enum.map(trimmed_parts, fn
          {:fragment, m, c} -> {:fragment, m, unescape_fragment(c)}
          other -> other
        end)

      # If only fragments and no interpolation, return a literal like s2q
      if Enum.all?(unescaped_parts, fn
           {:fragment, _m, _c} -> true
           _ -> false
         end) do
        merged =
          unescaped_parts
          |> Enum.map(fn {:fragment, _m, c} -> c end)
          |> IO.iodata_to_binary()

        literal = if kind == :binary, do: merged, else: String.to_charlist(merged)
        ast = encode_literal(parser, literal, container_range) |> put_start_position(start_meta)
        {attach_range(ast, [container_range]), parser}
      else
        # Build AST from parts
        args = build_string_parts(unescaped_parts, kind)

        # Add metadata with correct order: delimiter first, then indentation (if any)
        meta_with_indent =
          [
            {:delimiter, if(kind == :binary, do: ~s|"""|, else: ~s|'''|)},
            {:indentation, indentation} | start_meta
          ]

        case kind do
          :binary ->
            # Build binary heredoc: {:<<>>, meta, args}
            {{:<<>>, meta_with_indent, args}, parser}

          :charlist ->
            # Build charlist wrapped in List.to_charlist
            {{{:., start_meta, [List, :to_charlist]}, meta_with_indent, [args]}, parser}
        end
      end
    end
  end

  defp parse_linearized_sigil(parser) do
    trace "parse_linearized_sigil", trace_meta(parser) do
      # Extract sigil information from the start token
      {:sigil_start, _start_meta_raw, sigil_atom, delimiter} = parser.current_token
      base_meta = current_meta(parser)
      parser = next_token(parser)

      # Scan the sigil content (without unescaping). We leave :sigil_end as current.
      {parts, parser, _end_meta, _end_type, end_info} =
        scan_linearized(parser, :sigil_end, :sigil, no_unescape: true)

      # Check for optional modifiers. Since current is :sigil_end, look at peek.
      {modifiers, parser} =
        case peek_token_type(parser) do
          :sigil_modifiers ->
            parser = next_token(parser)
            {:sigil_modifiers, _meta, mods} = parser.current_token

            {mods, parser}

          _ ->
            {[], parser}
        end

      # Trim heredoc-like indentation for triple-quoted sigils
      parts =
        case Map.get(end_info, :indentation) do
          nil -> parts
          indent -> trim_heredoc_parts(parts, indent)
        end

      # Build sigil content as a binary node even when only fragments
      bs_args =
        case parts do
          [] -> [""]
          _ -> build_string_parts(parts, :sigil)
        end

      # Build the final sigil AST
      meta_with_delimiter = [{:delimiter, delimiter} | base_meta]

      bs_meta =
        case Map.get(end_info, :indentation) do
          nil -> base_meta
          indent -> [{:indentation, indent} | base_meta]
        end

      sigil_ast = {sigil_atom, meta_with_delimiter, [{:<<>>, bs_meta, bs_args}, modifiers]}

      {sigil_ast, parser}
    end
  end

  defp parse_linearized_atom(parser, safety) do
    trace "parse_linearized_atom (#{safety})", trace_meta(parser) do
      start_token = parser.current_token
      start_meta = current_meta(parser)
      open_range = token_range(start_token)
      # Capture the delimiter used for the quoted atom (" or ')
      {_kind, _m, h} = parser.current_token
      delim_str = <<h>>

      # Consume the start token
      parser = next_token(parser)

      # Determine end token based on safety
      end_token =
        case safety do
          :safe -> :atom_safe_end
          :unsafe -> :atom_unsafe_end
        end

      # Scan the atom content
      {parts, parser, _end_meta, _end_type, _end_info} = scan_linearized(parser, end_token, :atom)
      close_range = token_range(parser.current_token)
      container_range = container_range(open_range, close_range)

      cond do
        parts == [] ->
          # Empty quoted atom (edge case)
          ast = encode_literal(parser, :"", container_range) |> put_start_position(start_meta)
          {attach_range(ast, [container_range]), parser}

        Enum.all?(parts, fn
          {:fragment, _m, _c} -> true
          _ -> false
        end) ->
          # Only fragments, no interpolation: return literal atom regardless of safety
          merged =
            parts
            |> Enum.map(fn {:fragment, _m, c} -> c end)
            |> IO.iodata_to_binary()

          atom_value = String.to_atom(merged)
          ast = encode_literal(parser, atom_value, container_range) |> put_start_position(start_meta)
          {attach_range(ast, [container_range]), parser}

        true ->
          # Interpolated atom – build binary_to_atom({:<<>>,...}, :utf8)
          args = build_string_parts(parts, :atom)
          range_meta = put_meta_range(start_meta, container_range)
          binary_ast = {:<<>>, range_meta, args}
          delimiter_meta = put_meta_range([{:delimiter, delim_str} | start_meta], container_range)

          atom_ast =
            {{:., range_meta, [:erlang, :binary_to_atom]}, delimiter_meta, [binary_ast, :utf8]}

          {atom_ast, parser}
      end
    end
  end

  defp new(code, opts) do
    %{
      stream: Spitfire.TokenStream.new(code, opts[:line] || 1, opts[:column] || 1, opts),
      start_line: opts[:line] || 1,
      start_column: opts[:column] || 1,
      fuel: 150,
      current_token: nil,
      peek_token: nil,
      nesting: 0,
      literal_encoder: Keyword.get(opts, :literal_encoder),
      # Track interpolation nesting level
      interpolation_depth: 0,
      # Stack to save/restore nesting during interpolations
      saved_nesting_stack: [],
      errors: [],
      last_span: nil
    }
  end

  defp next_token(%{stream: stream, current_token: nil, peek_token: nil} = parser) do
    {tok, stream1} = Spitfire.TokenStream.next(stream)
    %{parser | stream: stream1, peek_token: tok, fuel: 150}
  end

  defp next_token(%{stream: stream} = parser) do
    last_span =
      case token_range(parser.current_token) do
        {{_sl, _sc}, {_el, _ec}} = span -> span
        _ -> parser.last_span
      end

    current = parser.peek_token
    {tok, stream1} = Spitfire.TokenStream.next(stream)

    %{
      parser
      | stream: stream1,
        current_token: current,
        peek_token: tok,
        fuel: 150,
        last_span: last_span
    }
  end

  defp consume_fuel(parser) do
    parser = Map.update!(parser, :fuel, &(&1 - 1))

    if parser.fuel < 1 do
      raise Spitfire.NoFuelRemaining
    end

    parser
  end

  defp eat(edibles, parser) when is_map(edibles) do
    if is_map_key(edibles, current_token_type(parser)) do
      next_token(parser)
    else
      parser
    end
  end

  defp eat(_edibles, parser), do: parser

  defp eat_eol(parser) do
    eat(%{:eol => true, :";" => true}, parser)
  end

  defp eat_eol_at(parser, idx) do
    eat_at(parser, [:eol, :";"], idx)
  end

  defp eat_at(parser, tokens, idx) when is_list(tokens),
    do: eat_at(parser, Map.new(tokens, &{&1, true}), idx)

  defp eat_at(%{stream: stream} = parser, tokens, 1) when is_map(tokens) do
    if tokens[peek_token_type(parser)] do
      {tok, stream1} = Spitfire.TokenStream.next(stream)
      %{parser | stream: stream1, peek_token: tok}
    else
      parser
    end
  end

  defp eat_at(parser, _tokens, _idx), do: parser

  defp peek_token(%{peek_token: {:stab_op, _, token}}) do
    token
  end

  defp peek_token(%{peek_token: {type, _, _, _}}) when type in [:list_heredoc, :bin_heredoc] do
    type
  end

  defp peek_token(%{peek_token: {token, _, _, _}}) do
    token
  end

  defp peek_token(%{peek_token: {token, _, _}}) do
    token
  end

  defp peek_token(%{peek_token: {token, _}}) do
    token
  end

  defp peek_token(%{peek_token: {token, _, _, _, _, _, _}}) do
    token
  end

  defp peek_token(%{peek_token: :eof}) do
    :eof
  end

  defp peek_token_eat_eol(%{peek_token: {:eol, _token}} = parser) do
    peek_token_eat_eol(next_token(parser))
  end

  defp peek_token_eat_eol(%{peek_token: {:";", _token}} = parser) do
    peek_token_eat_eol(next_token(parser))
  end

  defp peek_token_eat_eol(%{peek_token: {:";", _, _token}} = parser) do
    peek_token_eat_eol(next_token(parser))
  end

  defp peek_token_eat_eol(%{peek_token: {:stab_op, _, token}}) do
    token
  end

  defp peek_token_eat_eol(%{peek_token: {type, _, _, _}})
       when type in [:list_heredoc, :bin_heredoc] do
    type
  end

  defp peek_token_eat_eol(%{peek_token: {token, _, _, _}}) do
    token
  end

  defp peek_token_eat_eol(%{peek_token: {token, _, _}}) do
    token
  end

  defp peek_token_eat_eol(%{peek_token: {token, _}}) do
    token
  end

  defp peek_token_eat_eol(%{peek_token: {token, _, _, _, _, _, _}}) do
    token
  end

  defp peek_token_eat_eol(%{peek_token: :eof}) do
    :eof
  end

  defp current_token_type(%{tokens: :eof}) do
    :eof
  end

  defp current_token_type(%{current_token: :eof}) do
    :eof
  end

  defp current_token_type(%{current_token: nil}) do
    :eof
  end

  defp current_token_type(%{
         current_token: {:sigil, _meta, _token, _tokens, _mods, _, _delimiter}
       }) do
    :sigil
  end

  defp current_token_type(%{current_token: {:bin_heredoc, _meta, _indent, _tokens}}) do
    :bin_heredoc
  end

  defp current_token_type(%{current_token: {:list_heredoc, _meta, _indent, _tokens}}) do
    :list_heredoc
  end

  defp current_token_type(%{current_token: {type, _, _, _, _, _, _}}) do
    type
  end

  defp current_token_type(%{current_token: {type, _, _, _}}) do
    type
  end

  defp current_token_type(%{current_token: {type, _}}) do
    type
  end

  defp current_token_type(%{current_token: {type, _, _}}) do
    type
  end

  defp peek_token_type(%{peek_token: {type, _, _, _, _, _, _}}) do
    type
  end

  defp peek_token_type(%{peek_token: {type, _, _, _}}) do
    type
  end

  defp peek_token_type(%{peek_token: {type, _}}) do
    type
  end

  defp peek_token_type(%{peek_token: {type, _, _}}) do
    type
  end

  defp peek_token_type(%{peek_token: :eof}) do
    :eof
  end

  defp peek_token_type(_) do
    :no_peek
  end

  defp current_token(%{current_token: nil}) do
    :eof
  end

  defp current_token(%{current_token: :eof}) do
    :eof
  end

  defp current_token(%{
         current_token: {:sigil, _meta, token, _tokens, _mods, _indent, _delimiter}
       }) do
    token
  end

  defp current_token(%{current_token: {:bin_heredoc, _meta, _indent, _tokens}}) do
    :bin_heredoc
  end

  defp current_token(%{current_token: {:list_heredoc, _meta, _indent, _tokens}}) do
    :list_heredoc
  end

  # Elixir 1.19+: "not in" is tokenized as {:in_op, not_meta, :"not in", in_meta}
  # Normalize it so downstream parsing can key on the combined operator.
  defp current_token(%{current_token: {:in_op, _meta, :"not in", _info}}) do
    :"not in"
  end

  defp current_token(%{current_token: {token, _, _, _}}) do
    token
  end

  for op <- [
        :arrow_op,
        :pipe_op,
        :when_op,
        :ternary_op,
        :range_op,
        :xor_op,
        :in_match_op,
        :type_op,
        :capture_op,
        :capture_int,
        :block_identifier,
        :in_op,
        :or_op,
        :and_op,
        :comp_op,
        :rel_op,
        :assoc_op,
        :at_op,
        :concat_op,
        :dual_op,
        :mult_op,
        :stab_op,
        :power_op,
        :match_op,
        :unary_op
      ] do
    defp current_token(%{current_token: {unquote(op), _, token}}) do
      token
    end
  end

  defp current_token(%{current_token: {token, _, _}}) do
    token
  end

  defp current_token(%{current_token: {token, _}}) do
    token
  end

  defp current_meta(%{
         current_token: {:sigil, {line, col, _}, _token, _tokens, _mods, _, _delimiter}
       })
       when is_integer(line) and is_integer(col) do
    [line: line, column: col]
  end

  defp current_meta(%{
         current_token:
           {:sigil, {{line, col}, {_end_line, _end_col}, _extra}, _token, _tokens, _mods, _,
            _delimiter}
       }) do
    [line: line, column: col]
  end

  defp current_meta(%{
         current_token:
           {:sigil_start, {{line, col}, {_end_line, _end_col}, _extra}, _sigil, _delimiter}
       }) do
    [line: line, column: col]
  end

  defp current_meta(%{current_token: {:sigil_start, {line, col, _}, _sigil, _delimiter}}) do
    [line: line, column: col]
  end

  defp current_meta(%{current_token: {:bin_heredoc, {line, col, _}, _indent, _tokens}}) do
    [line: line, column: col]
  end

  defp current_meta(%{current_token: {:list_heredoc, {line, col, _}, _indent, _tokens}}) do
    [line: line, column: col]
  end

  # Legacy 4-tuple operator tokens (e.g. {:in_op, {line, col, extra}, op, info})
  defp current_meta(%{current_token: {:in_op, {line, col, _extra}, _op, _info}})
       when is_integer(line) and is_integer(col) do
    [line: line, column: col]
  end

  # Toxic 4-tuple operator tokens with ranged meta
  defp current_meta(%{
         current_token: {:in_op, {{line, col}, {_end_line, _end_col}, _extra}, _op, _info}
       }) do
    [line: line, column: col]
  end

  # Ranged meta from Toxic for 2- and 3-tuple tokens:
  #   {token, {{line, col}, {end_line, end_col}, extra}}
  #   {token, {{line, col}, {end_line, end_col}, extra}, value}
  defp current_meta(%{current_token: {_token, {{line, col}, {_end_line, _end_col}, _extra}}}) do
    [line: line, column: col]
  end

  defp current_meta(%{
         current_token: {_token, {{line, col}, {_end_line, _end_col}, _extra}, _value}
       }) do
    [line: line, column: col]
  end

  defp current_meta(%{current_token: {token, _}})
       when token in [:fake_closing_brace, :fake_closing_bracket, :fake_closing_brackets] do
    []
  end

  defp current_meta(%{current_token: {_token, {line, col, _}, _}}) do
    [line: line, column: col]
  end

  defp current_meta(%{current_token: {_token, {line, col, _}}}) do
    [line: line, column: col]
  end

  defp current_meta(_) do
    []
  end

  # Extract full ranged metadata from Toxic tokens. Legacy tokens return nil so
  # legacy mode remains unchanged.
  defp token_range({_, {{sl, sc}, {el, ec}, _extra}}), do: {{sl, sc}, {el, ec}}
  defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _value}), do: {{sl, sc}, {el, ec}}
  defp token_range({_, {{sl, sc}, {el, ec}, _extra}, _, _}), do: {{sl, sc}, {el, ec}}
  defp token_range({_, {_, _, _}}), do: nil
  defp token_range({_, {_, _, _}, _}), do: nil
  defp token_range({_, {_, _, _}, _, _}), do: nil
  defp token_range(_), do: nil

  # Position helpers
  defp pos_leq?({l1, c1}, {l2, c2}), do: l1 < l2 or (l1 == l2 and c1 <= c2)
  defp pos_geq?({l1, c1}, {l2, c2}), do: l1 > l2 or (l1 == l2 and c1 >= c2)
  defp pos_min(p1, p2), do: if(pos_leq?(p1, p2), do: p1, else: p2)
  defp pos_max(p1, p2), do: if(pos_geq?(p1, p2), do: p1, else: p2)

  defp meta_range(meta) do
    case Keyword.get(meta, :range) do
      {{_sl, _sc}, {_el, _ec}} = r -> r
      _ -> nil
    end
  end

  # CONVENTION: Use put_meta_range/2 when attaching a single range to raw metadata (low-level helper)
  defp put_meta_range(meta, nil), do: meta
  defp put_meta_range(meta, range) do
    if Application.get_env(:spitfire, :strip_ranges, false) do
      meta
    else
      Keyword.put(meta, :range, range)
    end
  end

  # Merge multiple ranges into a single spanning range.
  # Nil ranges are filtered out, allowing error recovery with fake tokens to work correctly.
  # For example, if a container has [open_range, nil (fake closer), child_range], the result
  # is a range spanning from open through the last valid child - no approximation.
  defp merge_ranges(ranges) do
    ranges
    |> Enum.filter(& &1)
    |> case do
      [] ->
        nil

      [single] ->
        single

      [first | rest] ->
        Enum.reduce(rest, first, fn {{sl2, sc2}, {el2, ec2}}, {{sl1, sc1}, {el1, ec1}} ->
          {pos_min({sl1, sc1}, {sl2, sc2}), pos_max({el1, ec1}, {el2, ec2})}
        end)
    end
  end

  defp ast_range({_, meta, _}) when is_list(meta), do: meta_range(meta)
  defp ast_range(_), do: nil

  # Helper to compute spanning ranges for AST nodes and collections
  # For lists: recursively extracts ranges from all elements and merges them into a spanning range
  # For tuples: extracts ranges from both elements and merges them
  # For other nodes: delegates to ast_range/1 to extract from metadata
  defp arg_range(list) when is_list(list), do: merge_ranges(Enum.map(list, &arg_range/1))
  defp arg_range({left, right}), do: merge_ranges([arg_range(left), arg_range(right)])
  defp arg_range(ast), do: ast_range(ast)

  # CONVENTION: Use attach_op_range/2 for operators - merges operator range with operand ranges
  defp attach_op_range({form, meta, args}, op_range) do
    ranges =
      args
      |> Enum.map(&arg_range/1)
      |> List.insert_at(0, op_range)

    {form, put_meta_range(meta, merge_ranges(ranges)), args}
  end

  defp attach_op_range(ast, _op_range), do: ast

  # Test-only helper: verify that ranges are in a reasonable order
  # This helps catch logic errors where ranges might be passed in unexpected order
  defp verify_range_order(ranges) do
    ranges
    |> List.wrap()
    |> Enum.filter(& &1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [{{sl1, sc1}, {el1, ec1}}, {{sl2, sc2}, _}] ->
      # Check that ranges are either in order or overlapping
      # We allow overlaps because that's valid (e.g., parent and child ranges)
      # We just want to catch cases where ranges are in completely wrong order
      unless pos_leq?({sl1, sc1}, {sl2, sc2}) or pos_leq?({sl1, sc1}, {el1, ec1}) do
        raise "Range order validation failed: ranges appear to be in unexpected order. " <>
                "First range ends at #{inspect({el1, ec1})}, second starts at #{inspect({sl2, sc2})}"
      end
    end)

    :ok
  end

  # CONVENTION: Use attach_range/2 for nodes where you're merging child + delimiter ranges
  # (containers, calls, blocks). Merges all provided ranges into a single spanning range.
  defp attach_range({form, meta, args}, ranges) do
    # Development mode assertion: verify ranges are in reasonable order
    if Application.get_env(:spitfire, :verify_range_order, false) do
      verify_range_order(ranges)
    end

    {form, put_meta_range(meta, merge_ranges(List.wrap(ranges))), args}
  end

  defp attach_range(ast, _ranges), do: ast

  defp container_range(open_range, close_range, extra_ranges \\ []) do
    merge_ranges([open_range, close_range | List.wrap(extra_ranges)])
  end

  defp put_closing_meta({form, meta, args}, closing_meta) do
    {form, Keyword.put(meta, :closing, closing_meta), args}
  end

  defp put_closing_meta(ast, _closing_meta), do: ast

  defp put_start_position({form, meta, args}, start_meta) do
    line = Keyword.get(start_meta, :line)
    column = Keyword.get(start_meta, :column)
    meta =
      Enum.map(meta, fn
        {:line, _} -> {:line, line}
        {:column, _} -> {:column, column}
        other -> other
      end)
      |> maybe_put(:line, line)
      |> maybe_put(:column, column)

    {form, meta, args}
  end

  defp put_start_position(ast, _start_meta), do: ast

  defp maybe_put(meta, key, value) do
    if Keyword.has_key?(meta, key) do
      meta
    else
      meta ++ [{key, value}]
    end
  end

  defp strip_ranges_if_needed(ast, opts) do
    if Keyword.get(opts, :strip_ranges, false) do
      strip_ranges(ast)
    else
      ast
    end
  end

  defp strip_ranges(ast) do
    Macro.postwalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.delete(meta, :range), args}

      list when is_list(list) ->
        if Keyword.keyword?(list), do: Keyword.delete(list, :range), else: list

      node ->
        node
    end)
  end

  if @trace? do
    defp trace_meta(parser) do
      [{:token, "'#{current_token(parser)}'"}, {:nesting, parser.nesting} | current_meta(parser)]
    end
  end

  # Ranged meta from Toxic
  defp current_eoe(%{current_token: {token, {{line, col}, {_end_line, _end_col}, newlines}}})
       when token in [:eol, :";"] and is_integer(newlines) do
    [newlines: newlines, line: line, column: col]
  end

  defp current_eoe(%{current_token: {token, {{line, col}, _end_pos, _extra}, _}})
       when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp current_eoe(%{current_token: {token, {{line, col}, _end_pos}, _}})
       when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp current_eoe(%{current_token: {token, {line, col, newlines}}})
       when token in [:eol, :";"] and is_integer(newlines) do
    [newlines: newlines, line: line, column: col]
  end

  defp current_eoe(%{current_token: {token, {line, col, _}, _}}) when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp current_eoe(%{current_token: {token, {line, col, _}}}) when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp current_eoe(_) do
    nil
  end

  # Ranged meta from Toxic
  defp peek_eoe(%{peek_token: {token, {{line, col}, {_end_line, _end_col}, newlines}}})
       when token in [:eol, :";"] and is_integer(newlines) do
    [newlines: newlines, line: line, column: col]
  end

  defp peek_eoe(%{peek_token: {token, {{line, col}, _end_pos, _extra}, _}})
       when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp peek_eoe(%{peek_token: {token, {{line, col}, _end_pos}, _}}) when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp peek_eoe(%{peek_token: {token, {line, col, newlines}}})
       when token in [:eol, :";"] and is_integer(newlines) do
    [newlines: newlines, line: line, column: col]
  end

  defp peek_eoe(%{peek_token: {token, {line, col, _}, _}}) when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp peek_eoe(%{peek_token: {token, {line, col, _}}}) when token in [:eol, :";"] do
    [line: line, column: col]
  end

  defp peek_eoe(_) do
    nil
  end

  defp current_newlines(%{current_token: {_token, {_line, _col, newlines}, _}})
       when is_integer(newlines) do
    newlines
  end

  defp current_newlines(%{current_token: {_token, {_line, _col, newlines}}})
       when is_integer(newlines) do
    newlines
  end

  defp current_newlines(_) do
    nil
  end

  defp peek_newlines(%{peek_token: {:eol, {_line, _col, newlines}}}) when is_integer(newlines) do
    newlines
  end

  defp peek_newlines(_) do
    nil
  end

  defp peek_newlines(%{peek_token: {token, {_line, _col, newlines}}}, token)
       when is_integer(newlines) do
    newlines
  end

  defp peek_newlines(_, _) do
    nil
  end

  defp current_precedence(parser) do
    Map.get(@precedences, current_token_type(parser), @lowest)
  end

  defp peek_precedence(parser) do
    Map.get(@precedences, peek_token_type(parser), @lowest)
  end

  defp pop_nesting(%{nesting: nesting} = parser) do
    %{parser | nesting: nesting - 1}
  end

  defp push_nesting(%{nesting: nesting} = parser) do
    %{parser | nesting: nesting + 1}
  end

  defp encode_literal(parser, literal, range_override \\ nil)

  defp encode_literal(%{literal_encoder: encoder} = parser, literal, range_override)
       when is_function(encoder) do
    base_meta = current_meta(parser)

    range = range_override || token_range(parser.current_token)

    base_meta = put_meta_range(base_meta, range)

    meta = additional_meta(literal, parser) ++ base_meta

    case encoder.(literal, meta) do
      {:ok, ast} ->
        ast

      {:error, reason} ->
        Logger.error(reason)
        literal
    end
  end

  defp encode_literal(_parser, literal, _range_override) do
    literal
  end

  defp additional_meta(_literal, %{current_token: {:list_string, _, _}}) do
    [delimiter: "'"]
  end

  defp additional_meta(_literal, %{current_token: {:kw_identifier, _, _}}) do
    [format: :keyword]
  end

  defp additional_meta(_, %{current_token: {type, _, indent, _token}})
       when type in [:list_heredoc] do
    [delimiter: ~s"'''", indentation: indent]
  end

  defp additional_meta(literal, %{current_token: {:list_string_end, _, _}})
       when is_list(literal) do
    [delimiter: "'"]
  end

  defp additional_meta(_, %{current_token: {:bin_string_end, _, _}}) do
    [delimiter: ~s'"']
  end

  defp additional_meta(_, %{current_token: {:bin_heredoc_end, _, _delim, indent}}) do
    [delimiter: ~s'"""', indentation: indent]
  end

  defp additional_meta(_, %{current_token: {:list_heredoc_end, _, _delim, indent}}) do
    [delimiter: ~s"'''", indentation: indent]
  end

  defp additional_meta(_, %{current_token: {type, _, h}})
       when type in [:atom_safe_end, :atom_unsafe_end] and is_integer(h) do
    [delimiter: <<h>>]
  end

  defp additional_meta(literal, parser) when is_list(literal) do
    parser = next_token(parser)
    closing = current_meta(parser)
    [closing: closing]
  end

  defp additional_meta(literal, parser) when is_tuple(literal) do
    closing = current_meta(parser)
    [closing: closing]
  end

  defp additional_meta(_, %{current_token: {type, _, token}}) when type in [:int, :flt] do
    [token: to_string(token)]
  end

  defp additional_meta(_, %{current_token: {type, _, _token}})
       when type in [:bin_string, :atom_quoted] do
    [delimiter: ~s'"']
  end

  defp additional_meta(_, %{current_token: {type, _, indent, _token}})
       when type in [:bin_heredoc] do
    [delimiter: ~s'"""', indentation: indent]
  end

  defp additional_meta(_literal, %{current_token: {:char, _, token}}) do
    [token: "?" <> List.to_string([token])]
  end

  defp additional_meta(literal, _) when is_atom(literal) do
    []
  end

  defp additional_meta(_, %{current_token: {type, _, _}})
       when type in [:do, :atom, :identifier, :block_identifier] do
    []
  end

  defp additional_meta(_, %{current_token: {type, _}}) when type in [:do, nil] do
    []
  end

  defp put_error(parser, error) do
    update_in(parser.errors, &[error | &1])
  end

  @braces MapSet.new([:")", :"]", :"}", :">>"])
  defp validate_peek(parser, current_type) do
    peek = peek_token_type(parser)

    # Inside an interpolation, :end_interpolation is a valid terminal peek.
    # Do not treat it as a syntax error or advance tokens.
    if parser.interpolation_depth > 0 and peek == :end_interpolation do
      {parser, true}
    else
      if not valid_peek?(current_type, peek) && peek != :no_peek do
        parser =
          if MapSet.member?(@braces, peek) do
            parser
          else
            next_token(parser)
          end

        {put_error(parser, {current_meta(parser), "syntax error"}), false}
      else
        {parser, true}
      end
    end
  end

  defp valid_peek?(ctype, _ptype) when ctype in [:identifier, :paren_identifier, :"["] do
    true
  end

  defp valid_peek?(_ctype, :"[") do
    true
  end

  defp valid_peek?(:")", :"(") do
    true
  end

  defp valid_peek?(:")", :"{") do
    true
  end

  @ops MapSet.new(
         @operators ++ [:"[", :";", :eol, :eof, :",", :")", :do, :., :"}", :"]", :">>", :end]
       )
  defp valid_peek?(:"}", ptype) do
    MapSet.member?(@ops, ptype)
  end

  defp valid_peek?(:alias, ptype) when ptype in [:"{"] do
    true
  end

  defp valid_peek?(ctype, :"{" )
       when ctype in [
              :atom,
              :atom_quoted,
              :atom_unsafe,
              :atom_safe_start,
              :atom_unsafe_start,
              :atom_safe_end,
              :atom_unsafe_end
            ] do
    true
  end

  @ops MapSet.new(
         @operators ++
           [
             :";",
             :eol,
             :eof,
             :",",
             :")",
             :do,
             :.,
             :"}",
             :"]",
             :">>",
             :end,
             :block_identifier,
             :end_interpolation
           ]
       )
  defp valid_peek?(_ctype, ptype) do
    MapSet.member?(@ops, ptype)
  end

  # metadata describing how mnay newlines are present following the start of an expression
  # eg: foo(
  #       arg
  #     )
  # will have 1 newling due to the newline after the opening paren
  defp get_newlines(parser) do
    case peek_newlines(parser) do
      nil -> []
      nl -> [newlines: nl]
    end
  end

  defp inject_newlines(meta, []), do: meta

  defp inject_newlines(meta, [newlines: nl]) do
    meta = Enum.reject(meta, fn {k, _} -> k == :newlines end)
    {parens, rest} = Enum.split_with(meta, fn {k, _} -> k == :parens end)
    parens ++ [{:newlines, nl} | rest]
  end

  defp reorder_parens_newlines(meta) do
    parens = Enum.filter(meta, &match?({:parens, _}, &1))
    newlines = Enum.filter(meta, &match?({:newlines, _}, &1))

    if parens == [] or newlines == [] do
      meta
    else
      rest = Enum.reject(meta, fn {k, _} -> k in [:parens, :newlines] end)
      parens ++ newlines ++ rest
    end
  end

  defp push_eoe(ast, eoe) do
    case ast do
      {t, meta, a} when not is_nil(eoe) and t != :-> ->
        {t, [{:end_of_expression, eoe} | meta], a}

      literal ->
        literal
    end
  end

  # Build a block node from expressions, attaching ranges that span all children
  # For multiple expressions, creates a {:__block__, meta, exprs} node with a range
  # spanning from the first to the last expression (computed via arg_range/1).
  defp build_block_nr(exprs, parser \\ nil) do
    case exprs do
      {:->, _, _} ->
        [exprs]

      [{:->, _, _} | _] ->
        exprs

      [{:unquote_splicing, _, [_]}] ->
        {:__block__, [], exprs}
        |> attach_range([arg_range(exprs)])

      [expr] ->
        expr

      [] ->
        meta =
          if parser do
            [line: parser.start_line, column: parser.start_column]
          else
            []
          end

        {:__block__, meta, []}

      _ ->
        {:__block__, [], exprs}
        |> attach_range([arg_range(exprs)])
    end
  end

  # Code taken from Code.string_to_quoted_with_comments in Elixir core
  # Check it out here: https://github.com/elixir-lang/elixir/blob/12f62e49ca2399a15976d2051a2d7743dae48449/lib/elixir/lib/code.ex#L1327
  # Consult Elixir's license here: https://github.com/elixir-lang/elixir/blob/main/LICENSE
  defp preserve_comments(line, column, tokens, comment, rest) do
    comments = Process.get(:code_formatter_comments)

    comment = %{
      line: line,
      column: column,
      previous_eol_count: previous_eol_count(tokens),
      next_eol_count: next_eol_count(rest, 0),
      text: List.to_string(comment)
    }

    Process.put(:code_formatter_comments, [comment | comments])
  end

  defp next_eol_count([?\s | rest], count), do: next_eol_count(rest, count)
  defp next_eol_count([?\t | rest], count), do: next_eol_count(rest, count)
  defp next_eol_count([?\n | rest], count), do: next_eol_count(rest, count + 1)
  defp next_eol_count([?\r, ?\n | rest], count), do: next_eol_count(rest, count + 1)
  defp next_eol_count(_, count), do: count

  defp previous_eol_count([{token, {_, _, count}} | _])
       when token in [:eol, :",", :";"] and count > 0 do
    count
  end

  defp previous_eol_count([]), do: 1
  defp previous_eol_count(_), do: 0

  defp push_delimiter(meta, {_, _, delimiter}) when is_integer(delimiter) do
    [{:delimiter, "#{[delimiter]}"} | meta]
  end

  defp push_delimiter(meta, _token_meta) do
    meta
  end
end
