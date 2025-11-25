defmodule Spitfire.Property do
  @moduledoc false

  @ignored_meta_keys [:range, :delimiter, :closing, :indentation, :end_of_expression]

  def normalize_ast(ast) do
    Macro.postwalk(ast, fn
      {tag, meta, args} when is_list(meta) ->
        {tag, Keyword.drop(meta, @ignored_meta_keys), args}

      keyword when is_list(keyword) ->
        if Keyword.keyword?(keyword) do
          Keyword.drop(keyword, @ignored_meta_keys)
        else
          keyword
        end

      node ->
        node
    end)
  end

  def touch_atom_pools do
    _ =
      Spitfire.Property.Generators.atom_pool() ++
        Spitfire.Property.Generators.keyword_pool() ++
        Spitfire.Property.Generators.operator_atoms()

    Enum.each(Spitfire.Property.Generators.alias_pool(), fn alias_atom ->
      _ = Module.concat([alias_atom])
    end)

    :ok
  end
end

defmodule Spitfire.Property.TargetTokens do
  @moduledoc false

  @target_token_kinds MapSet.new([
                        # Literals
                        :int,
                        :flt,
                        :char,
                        :atom,

                        # Identifiers
                        :identifier,
                        :paren_identifier,
                        :bracket_identifier,
                        :do_identifier,
                        :op_identifier,
                        :alias,
                        :block_identifier,
                        :kw_identifier,

                        # Linearized strings/heredocs
                        :bin_string_start,
                        :bin_string_end,
                        :list_string_start,
                        :list_string_end,
                        :string_fragment,
                        :bin_heredoc_start,
                        :bin_heredoc_end,
                        :list_heredoc_start,
                        :list_heredoc_end,

                        # Interpolation
                        :begin_interpolation,
                        :end_interpolation,

                        # Sigils
                        :sigil_start,
                        :sigil_end,
                        :sigil_modifiers,

                        # Quoted atoms
                        :atom_safe_start,
                        :atom_safe_end,
                        :atom_unsafe_start,
                        :atom_unsafe_end,

                        # Quoted identifiers
                        :quoted_identifier_start,
                        :quoted_identifier_end,
                        :quoted_paren_identifier_end,
                        :quoted_bracket_identifier_end,
                        :quoted_do_identifier_end,
                        :quoted_op_identifier_end,

                        # Keyword identifier ends
                        :kw_identifier_safe_end,
                        :kw_identifier_unsafe_end,

                        # Operators
                        :dual_op,
                        :mult_op,
                        :power_op,
                        :concat_op,
                        :range_op,
                        :xor_op,
                        :ternary_op,
                        :and_op,
                        :or_op,
                        :comp_op,
                        :rel_op,
                        :arrow_op,
                        :in_op,
                        :in_match_op,
                        :type_op,
                        :pipe_op,
                        :stab_op,
                        :when_op,
                        :match_op,
                        :assoc_op,
                        :capture_op,
                        :capture_int,
                        :at_op,
                        :unary_op,
                        :ellipsis_op,
                        :dot_call_op,

                        # Delimiters and structural
                        :"(",
                        :")",
                        :"[",
                        :"]",
                        :"{",
                        :"}",
                        :"<<",
                        :">>",
                        :%{},
                        :%,
                        :fn,
                        :do,
                        :end,
                        :eol,
                        :";",
                        :",",
                        :.,

                        # EOF and special
                        :eof
                      ])

  def target, do: @target_token_kinds
  def phase3_target, do: @target_token_kinds

  @phase1_token_kinds MapSet.new([
                        :int,
                        :atom,
                        :alias,
                        :identifier,
                        :kw_identifier,
                        :kw_identifier_safe_end,
                        :bin_string_start,
                        :bin_string_end,
                        :string_fragment,
                        :begin_interpolation,
                        :end_interpolation,
                        :bin_heredoc_start,
                        :bin_heredoc_end,
                        :sigil_start,
                        :sigil_end,
                        :dual_op,
                        :pipe_op,
                        :comp_op,
                        :and_op,
                        :or_op,
                        :fn,
                        :end,
                        :eol,
                        :"[",
                        :"]",
                        :"(",
                        :")",
                        :"{",
                        :"}",
                        :%{},
                        :.,
                        :dot_call_op,
                        :eof
                      ])

  def phase1_target, do: @phase1_token_kinds

  @phase2_token_kinds MapSet.new([
                        :int,
                        :flt,
                        :char,
                        :atom,
                        :identifier,
                        :paren_identifier,
                        :bracket_identifier,
                        :do_identifier,
                        :op_identifier,
                        :alias,
                        :block_identifier,
                        :kw_identifier,
                        :kw_identifier_safe_end,
                        :kw_identifier_unsafe_end,
                        :bin_string_start,
                        :bin_string_end,
                        :list_string_start,
                        :list_string_end,
                        :string_fragment,
                        :begin_interpolation,
                        :end_interpolation,
                        :bin_heredoc_start,
                        :bin_heredoc_end,
                        :list_heredoc_start,
                        :list_heredoc_end,
                        :sigil_start,
                        :sigil_end,
                        :sigil_modifiers,
                        :atom_safe_start,
                        :atom_safe_end,
                        :atom_unsafe_start,
                        :atom_unsafe_end,
                        :quoted_identifier_start,
                        :quoted_identifier_end,
                        :quoted_paren_identifier_end,
                        :quoted_bracket_identifier_end,
                        :quoted_do_identifier_end,
                        :quoted_op_identifier_end,
                        :dual_op,
                        :mult_op,
                        :power_op,
                        :concat_op,
                        :range_op,
                        :and_op,
                        :or_op,
                        :comp_op,
                        :rel_op,
                        :arrow_op,
                        :in_op,
                        :type_op,
                        :pipe_op,
                        :stab_op,
                        :when_op,
                        :match_op,
                        :assoc_op,
                        :capture_op,
                        :capture_int,
                        :at_op,
                        :unary_op,
                        :ellipsis_op,
                        :dot_call_op,
                        :"(",
                        :")",
                        :"[",
                        :"]",
                        :"{",
                        :"}",
                        :"<<",
                        :">>",
                        :%{},
                        :%,
                        :fn,
                        :do,
                        :end,
                        :eol,
                        :";",
                        :",",
                        :.,
                        :eof
                      ])

  def phase2_target, do: @phase2_token_kinds
end

defmodule Spitfire.Property.TokenIntrospection do
  @moduledoc false

  def collect_tokens(stream) do
    stream
    |> Toxic.to_stream()
    |> Enum.to_list()
  end

  def collect_types_and_ranges(code, opts \\ []) do
    stream = Toxic.new(code, 1, 1, opts)
    tokens = collect_tokens(stream)

    Enum.map(tokens, fn
      {kind, {{sl, sc}, {el, ec}, _extra}, _} -> {kind, {{sl, sc}, {el, ec}}}
      {kind, {{sl, sc}, {el, ec}, _extra}} -> {kind, {{sl, sc}, {el, ec}}}
      {kind, {{sl, sc}, {el, ec}, _extra}, _, _} -> {kind, {{sl, sc}, {el, ec}}}
      other -> {elem(other, 0), nil}
    end)
  end
end
