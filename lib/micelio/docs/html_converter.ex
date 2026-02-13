defmodule Micelio.Docs.HtmlConverter do
  @moduledoc """
  Custom HTML converter for NimblePublisher that adds GitHub-style admonition support,
  heading anchor IDs, and interactive API "try it" blocks.

  Delegates markdown-to-HTML conversion to Earmark, then applies transforms
  using the shared logic from MicelioWeb.Markdown.
  """

  def convert(_filepath, body, _attrs, opts) do
    highlighters = Keyword.get(opts, :highlighters, [])

    body
    |> Earmark.as_html!()
    |> MicelioWeb.Markdown.transform_admonitions()
    |> add_heading_ids()
    |> transform_try_it_blocks()
    |> NimblePublisher.highlight(highlighters)
  end

  @doc """
  Extracts a table of contents from the page body HTML.
  Returns a list of maps with level, id, and text for h2 and h3 headings.
  """
  def extract_toc(html) do
    Regex.scan(~r/<h([23])\s+id="([^"]+)"[^>]*>(.*?)<\/h\1>/si, html)
    |> Enum.map(fn [_, level, id, text] ->
      %{level: String.to_integer(level), id: id, text: strip_tags(text)}
    end)
  end

  defp add_heading_ids(html) do
    Regex.replace(~r/<h([23])>(.*?)<\/h\1>/si, html, fn _, level, content ->
      id = slugify(strip_tags(content))
      "<h#{level} id=\"#{id}\">#{content}</h#{level}>"
    end)
  end

  defp transform_try_it_blocks(html) do
    Regex.replace(
      ~r/<pre><code class="try-it">(.*?)<\/code><\/pre>/si,
      html,
      fn _, json_content ->
        json =
          json_content
          |> String.replace("&amp;", "&")
          |> String.replace("&lt;", "<")
          |> String.replace("&gt;", ">")
          |> String.replace("&quot;", "\"")
          |> String.trim()

        build_try_it_html(json)
      end
    )
  end

  defp build_try_it_html(json) do
    case Jason.decode(json) do
      {:ok, config} ->
        method = Map.get(config, "method", "GET")
        path = Map.get(config, "path", "")
        description = Map.get(config, "description", "")
        params = Map.get(config, "params", [])
        body = Map.get(config, "body")

        method_lower = String.downcase(method)
        escaped_config = json |> String.replace("\"", "&quot;")

        params_html = build_params_html(params)
        body_html = build_body_html(body)

        """
        <div class="api-try-it" data-config="#{escaped_config}">
          <div class="api-try-it-header">
            <span class="api-try-it-method api-try-it-method-#{method_lower}">#{method}</span>
            <span class="api-try-it-path">#{path}</span>
            <span class="api-try-it-description">#{description}</span>
          </div>
          #{params_html}#{body_html}<div class="api-try-it-actions">
            <button class="api-try-it-send repository-button" type="button">Send request</button>
          </div>
          <div class="api-try-it-response" style="display:none;">
            <div class="api-try-it-response-status"></div>
            <pre class="api-try-it-response-body"><code></code></pre>
          </div>
        </div>
        """

      _ ->
        "<pre><code>#{json}</code></pre>"
    end
  end

  defp build_params_html([]), do: ""

  defp build_params_html(params) do
    inputs =
      Enum.map_join(params, "\n", fn param ->
        name = Map.get(param, "name", "")
        placeholder = Map.get(param, "placeholder", "")
        desc = Map.get(param, "description", "")

        """
        <div class="api-try-it-param">
          <label class="api-try-it-param-label" for="param-#{name}">#{name}</label>
          <input class="api-try-it-param-input" type="text" data-param="#{name}" placeholder="#{placeholder}" title="#{desc}">
        </div>
        """
      end)

    "<div class=\"api-try-it-params\">#{inputs}</div>"
  end

  defp build_body_html(nil), do: ""

  defp build_body_html(body) do
    json = Jason.encode!(body, pretty: true) |> String.replace("\"", "&quot;")

    """
    <div class="api-try-it-body">
      <label class="api-try-it-body-label">Request body</label>
      <textarea class="api-try-it-body-editor">#{json}</textarea>
    </div>
    """
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp strip_tags(html) do
    String.replace(html, ~r/<[^>]+>/, "")
  end
end
