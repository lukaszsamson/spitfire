defmodule Spitfire.LegacyTokenizer do
  @moduledoc false

  # Lightweight wrapper that mimics a streaming tokenizer API
  # over Spitfire's existing Erlang tokenizer output.

  defstruct tokens: [], pushback: [], eof?: false

  @type t :: %__MODULE__{tokens: list(), pushback: list(), eof?: boolean()}

  # Public: Build a stream from source code using the legacy tokenizer
  @spec new(String.t(), non_neg_integer(), non_neg_integer(), Keyword.t()) :: t()
  def new(code, line, column, opts \\ []) do
    %__MODULE__{tokens: tokenize(code, line, column, opts)}
  end

  # Public: Build a stream from a pre-tokenized list (e.g., for interpolation)
  @spec from_tokens(list()) :: t()
  def from_tokens(tokens) when is_list(tokens) do
    %__MODULE__{tokens: tokens ++ [:eof]}
  end

  # Public: Advance and return next token plus updated stream
  @spec next(t()) :: {:ok, term(), t()} | {:eof, t()}
  def next(%__MODULE__{pushback: [tok | rest]} = s) do
    {:ok, tok, %__MODULE__{s | pushback: rest}}
  end

  def next(%__MODULE__{tokens: [tok | rest]} = s) do
    {:ok, tok, %__MODULE__{s | tokens: rest}}
  end

  def next(%__MODULE__{tokens: [], eof?: false} = s) do
    {:eof, %__MODULE__{s | eof?: true}}
  end

  def next(%__MODULE__{tokens: [], eof?: true} = s) do
    {:eof, s}
  end

  # Public: Push tokens back so they are returned before the remaining stream
  @spec push_back(t(), list()) :: t()
  def push_back(%__MODULE__{} = s, toks) when is_list(toks) do
    %__MODULE__{s | pushback: Enum.reverse(toks, s.pushback)}
  end

  # Internal: legacy tokenize ported from Spitfire.tokenize/2 with minimal changes
  defp tokenize(code, line, column, opts) do
    opts =
      opts
      |> Keyword.put_new(:cursor_completion, false)
      |> Keyword.put_new(:check_terminators, false)

    tokens =
      case code
           |> String.to_charlist()
           |> :spitfire_tokenizer.tokenize(line || 1, column || 1, opts) do
        {:ok, _, _, _, tokens, []} ->
          Enum.reverse(tokens)

        {:ok, line, column, _, rev_tokens, rev_terminators} ->
          {rev_tokens, rev_terminators} =
            with [close, open, {_, _, :__cursor__} = cursor | rev_tokens] <- rev_tokens,
                 {_, [_ | after_fn]} <- Enum.split_while(rev_terminators, &(elem(&1, 0) != :fn)),
                 true <- maybe_missing_stab?(rev_tokens, false),
                 [_ | rev_tokens] <- Enum.drop_while(rev_tokens, &(elem(&1, 0) != :fn)) do
              {[close, open, cursor | rev_tokens], after_fn}
            else
              _ -> {rev_tokens, rev_terminators}
            end

          reverse_tokens(line, column, rev_tokens, rev_terminators)

        {:error, _, _, _, tokens} ->
          Enum.reverse(tokens)
      end

    tokens ++ [:eof]
  end

  # Vendored helpers from Spitfire (duplicated here to avoid cross-module deps)
  defp maybe_missing_stab?([{:after, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:do, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:fn, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:else, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:catch, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:rescue, _} | _], _stab_choice?), do: true
  defp maybe_missing_stab?([{:stab_op, _, :->} | _], stab_choice?), do: stab_choice?
  defp maybe_missing_stab?([_ | tail], stab_choice?), do: maybe_missing_stab?(tail, stab_choice?)
  defp maybe_missing_stab?([], _stab_choice?), do: false

  defp reverse_tokens(line, column, tokens, terminators) do
    {terminators, _} =
      Enum.map_reduce(terminators, column, fn {start, _, _}, column ->
        atom = :spitfire_tokenizer.terminator(start)

        {{atom, {line, column, nil}}, column + length(Atom.to_charlist(atom))}
      end)

    Enum.reverse(tokens, terminators)
  end
end
