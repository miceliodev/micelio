defmodule MicelioWeb.Markdown do
  @moduledoc false

  @options [escape: true]
  @admonition_titles %{
    "NOTE" => "Note",
    "TIP" => "Tip",
    "IMPORTANT" => "Important",
    "WARNING" => "Warning",
    "CAUTION" => "Caution"
  }

  @spec render(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def render(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, @options) do
      {:ok, html, _messages} ->
        {:ok, html |> transform_admonitions() |> highlight_code_blocks()}

      {:error, html, _messages} ->
        {:error, html |> transform_admonitions() |> highlight_code_blocks()}
    end
  end

  defp transform_admonitions(html) do
    html
    |> transform_blockquote_admonitions()
    |> transform_paragraph_admonitions()
  end

  defp transform_blockquote_admonitions(html) do
    Regex.replace(
      ~r/<blockquote>\s*<p>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*?)<\/p>(.*?)<\/blockquote>/si,
      html,
      fn _, type, first, rest ->
        body =
          case String.trim(first) do
            "" -> rest
            _ -> "<p>" <> first <> "</p>" <> rest
          end

        build_admonition_html(type, body)
      end
    )
  end

  defp transform_paragraph_admonitions(html) do
    Regex.replace(
      ~r/<p>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*?)<\/p>/si,
      html,
      fn _, type, body ->
        body =
          case String.trim(body) do
            "" -> ""
            _ -> "<p>" <> body <> "</p>"
          end

        build_admonition_html(type, body)
      end
    )
  end

  defp build_admonition_html(type, body) do
    normalized = String.upcase(type)
    title = Map.get(@admonition_titles, normalized, "Note")
    class = "admonition admonition-#{String.downcase(normalized)}"

    "<div class=\"" <>
      class <>
      "\"><p class=\"admonition-title\">" <> title <> "</p>" <> body <> "</div>"
  end

  defp highlight_code_blocks(html) do
    Regex.replace(
      ~r/<pre><code class="([^"]+)">(.*?)<\/code><\/pre>/si,
      html,
      fn full_match, lang, code ->
        try do
          case Makeup.Registry.get_lexer_by_name(lang) do
            nil ->
              full_match

            {lexer, lexer_options} ->
              unescaped = unescape_html(code)

              highlighted =
                Makeup.highlight_inner_html(unescaped, lexer: lexer, lexer_options: lexer_options)

              "<pre><code class=\"makeup #{lang}\">#{highlighted}</code></pre>"
          end
        rescue
          _ -> full_match
        end
      end
    )
  end

  defp unescape_html(html) do
    html
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end
end
