defmodule Micelio.Docs.HtmlConverter do
  @moduledoc """
  Custom HTML converter for NimblePublisher that adds GitHub-style admonition support.

  Delegates markdown-to-HTML conversion to Earmark, then applies admonition transforms
  using the shared logic from MicelioWeb.Markdown.
  """

  def convert(_filepath, body, _attrs, opts) do
    highlighters = Keyword.get(opts, :highlighters, [])

    body
    |> Earmark.as_html!()
    |> MicelioWeb.Markdown.transform_admonitions()
    |> NimblePublisher.highlight(highlighters)
  end
end
