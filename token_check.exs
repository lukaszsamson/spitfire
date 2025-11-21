
defmodule TokenCheck do
  def check do
    code = "[a: 1]"
    IO.puts "--- Elixir Tokenizer ---"
    stream = Spitfire.TokenStream.new(code, 1, 1, tokenizer: :legacy)
    {tok, _} = Spitfire.TokenStream.next(stream)
    IO.inspect(tok)

    IO.puts "--- Toxic Tokenizer ---"
    stream = Spitfire.TokenStream.new(code, 1, 1, tokenizer: :toxic)
    {tok, _} = Spitfire.TokenStream.next(stream)
    IO.inspect(tok)
  end
end

TokenCheck.check()
