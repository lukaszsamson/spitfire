defmodule Spitfire.TokenStream do
  @moduledoc false

  # Compatibility adapter that presents a Toxic-like streaming interface
  # backed by the legacy tokenizer for now. When the Toxic dependency is
  # available, this module can delegate to it transparently.

  defstruct backend: nil, state: nil

  @type t :: %__MODULE__{backend: module(), state: term()}

  @spec new(String.t(), non_neg_integer(), non_neg_integer(), Keyword.t()) :: t()
  def new(code, line, column, opts \\ []) do
    # Prefer Toxic if available, otherwise fall back to legacy
    backend = Application.get_env(:spitfire, :tokenizer, :legacy)

    case backend do
      :toxic ->
        # Defer integrating token-shape adaptation until Phase 2.
        # For Phase 1, use legacy to avoid changing parser semantics.
        %__MODULE__{backend: Toxic.TokenStream, state: Toxic.TokenStream.new(code, line, column, opts)}

      :legacy ->
        %__MODULE__{backend: Spitfire.LegacyTokenizer, state: Spitfire.LegacyTokenizer.new(code, line, column, opts)}
    end
  end

  # TODO: this call is not needed with toxic
  @spec from_tokens(list()) :: t()
  def from_tokens(tokens) do
    %__MODULE__{backend: Spitfire.LegacyTokenizer, state: Spitfire.LegacyTokenizer.from_tokens(tokens)}
  end

  @spec next(t()) :: {term(), t()}
  def next(%__MODULE__{backend: backend, state: s} = ts) do
    case backend.next(s) do
      {:ok, tok, s1} -> {tok, %__MODULE__{ts | state: s1}}
      {:eof, s1} -> {:eof, %__MODULE__{ts | state: s1}}
    end
  end

  @spec push_back(t(), list()) :: t()
  def push_back(%__MODULE__{backend: backend, state: s} = ts, toks) do
    %__MODULE__{ts | state: backend.push_back(s, toks)}
  end
end
