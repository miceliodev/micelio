defmodule MicelioWeb.CodeHighlighter do
  @moduledoc false

  @extension_aliases %{
    "eex" => "ex",
    "heex" => "ex",
    "leex" => "ex"
  }

  @fallback_lexers %{
    "ex" => Makeup.Lexers.ElixirLexer,
    "exs" => Makeup.Lexers.ElixirLexer,
    "erl" => Makeup.Lexers.ErlangLexer,
    "hrl" => Makeup.Lexers.ErlangLexer
  }

  @spec highlight(String.t(), String.t()) :: {:ok, String.t()} | :no_lexer
  def highlight(file_path, content) when is_binary(file_path) and is_binary(content) do
    case lexer_for(file_path) do
      nil ->
        :no_lexer

      {lexer, lexer_options} ->
        {:ok, Makeup.highlight_inner_html(content, lexer: lexer, lexer_options: lexer_options)}
    end
  end

  defp lexer_for(file_path) do
    extension =
      file_path
      |> Path.extname()
      |> String.trim_leading(".")
      |> String.downcase()

    extension = Map.get(@extension_aliases, extension, extension)

    case Makeup.Registry.get_lexer_by_extension(extension) do
      nil -> fallback_lexer(extension)
      lexer -> lexer
    end
  end

  defp fallback_lexer(extension) do
    case Map.get(@fallback_lexers, extension) do
      nil ->
        nil

      lexer ->
        if Code.ensure_loaded?(lexer) do
          {lexer, []}
        end
    end
  end
end
