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
      {:ok, html, _messages} -> {:ok, transform_admonitions(html)}
      {:error, html, _messages} -> {:error, transform_admonitions(html)}
    end
  end

  defp transform_admonitions(html) do
    html
    |> transform_blockquote_admonitions()
    |> transform_paragraph_admonitions()
  end

  defp transform_blockquote_admonitions(html) do
    Regex.replace(
      ~r/<blockquote>\s*<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*?)<\/p>(.*?)<\/blockquote>/si,
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
      ~r/<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*?)<\/p>/si,
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
end
