defmodule Spitfire.TokenStream do
  @moduledoc false

  # Compatibility adapter that presents a Toxic-like streaming interface
  # backed by the legacy tokenizer for now. When the Toxic dependency is
  # available, this module can delegate to it transparently.

  defstruct backend: :legacy, state: nil

  @type t :: %__MODULE__{backend: :legacy | :toxic, state: term()}

  @spec new(String.t(), non_neg_integer(), non_neg_integer(), Keyword.t()) :: t()
  def new(code, line, column, opts \\ []) do
    # Prefer Toxic if available, otherwise fall back to legacy
    backend = if Code.ensure_loaded?(Toxic.TokenStream), do: :toxic, else: :legacy

    case backend do
      :toxic ->
        # Defer integrating token-shape adaptation until Phase 2.
        # For Phase 1, use legacy to avoid changing parser semantics.
        %__MODULE__{backend: :legacy, state: Spitfire.LegacyTokenizer.new(code, line, column, opts)}

      :legacy ->
        %__MODULE__{backend: :legacy, state: Spitfire.LegacyTokenizer.new(code, line, column, opts)}
    end
  end

  @spec from_tokens(list()) :: t()
  def from_tokens(tokens) do
    %__MODULE__{backend: :legacy, state: Spitfire.LegacyTokenizer.from_tokens(tokens)}
  end

  @spec next(t()) :: {term(), t()}
  def next(%__MODULE__{backend: :legacy, state: s} = ts) do
    {tok, s1} = Spitfire.LegacyTokenizer.next(s)
    {tok, %__MODULE__{ts | state: s1}}
  end

  def next(%__MODULE__{backend: :toxic, state: s} = ts) do
    # Not used yet; placeholder for future integration
    {tok, s1} = Toxic.TokenStream.next(s)
    {tok, %__MODULE__{ts | state: s1}}
  end

  @spec push_back(t(), list()) :: t()
  def push_back(%__MODULE__{backend: :legacy, state: s} = ts, toks) do
    %__MODULE__{ts | state: Spitfire.LegacyTokenizer.push_back(s, toks)}
  end

  def push_back(%__MODULE__{backend: :toxic, state: s} = ts, toks) do
    # Toxic path: expect a pushback API; if absent, emulate later
    apply_if_exported(Toxic.TokenStream, :push_back, [s, toks], fn -> ts end)
  end

  defp apply_if_exported(mod, fun, args, fallback) do
    if function_exported?(mod, fun, length(args)) do
      state = apply(mod, fun, args)
      %__MODULE__{backend: :toxic, state: state}
    else
      fallback.()
    end
  end
end
