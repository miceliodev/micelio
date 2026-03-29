defmodule MicelioWeb.OpenGraphImage do
  @moduledoc """
  Lazy Open Graph image generation persisted via `Micelio.Storage`.

  Images are content-addressed: we hash the attributes required to render the image,
  and store the resulting artifact under that hash. The first request to the image
  endpoint generates and persists it.

  When `MICELIO_OG_ENABLED=true`, images are rendered using Carta (HTML to JPEG via
  a headless Chromium pool). When disabled, OG image URLs are not generated.
  """

  alias Micelio.Storage
  alias MicelioWeb.PageMeta

  @width 1200
  @height 630
  @template_version 5

  @storage_prefix "open-graph/og"

  def width, do: @width
  def height, do: @height

  @doc """
  Returns true if OG image generation is enabled.
  """
  def enabled? do
    Application.get_env(:micelio, :open_graph, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Returns the Open Graph image URL for the given page meta, or `nil`.

  URLs are always generated regardless of whether OG image rendering is enabled.
  When disabled, the `/og/:hash` endpoint will return 404 for uncached images
  but will still serve any previously generated images from storage.
  """
  @spec url(PageMeta.t()) :: String.t() | nil
  def url(%PageMeta{} = meta) do
    case meta.canonical_url do
      canonical_url when is_binary(canonical_url) and canonical_url != "" ->
        attrs = attrs_from_meta(meta)
        hash = hash(attrs)
        token = token(attrs)
        cache_key = cache_key(hash, meta.open_graph)

        canonical_url
        |> URI.parse()
        |> Map.put(:path, "/og/#{hash}")
        |> Map.put(:query, URI.encode_query(%{"token" => token, "v" => cache_key}))
        |> Map.put(:fragment, nil)
        |> URI.to_string()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp cache_key(hash, open_graph) when is_binary(hash) and is_map(open_graph) do
    case cache_buster_from_meta(open_graph) do
      nil -> hash
      cache_buster -> hash <> "-" <> cache_buster
    end
  end

  defp cache_key(hash, _open_graph), do: hash

  defp cache_buster_from_meta(open_graph) when is_map(open_graph) do
    open_graph
    |> Map.get(:cache_buster)
    |> case do
      nil -> Map.get(open_graph, "cache_buster")
      value -> value
    end
    |> normalize_cache_buster()
  end

  defp cache_buster_from_meta(_), do: nil

  defp normalize_cache_buster(nil), do: nil

  defp normalize_cache_buster(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  @doc """
  Builds the attributes used both for hashing and rendering.
  """
  @spec attrs_from_meta(PageMeta.t()) :: map()
  def attrs_from_meta(%PageMeta{} = meta) do
    image_template = image_template_from_meta(meta.open_graph)
    image_stats = image_stats_from_meta(meta.open_graph)
    author_attrs = author_attrs_from_meta(meta)

    %{
      "v" => @template_version,
      "site_name" => PageMeta.site_name(),
      "title" => PageMeta.og_title(meta),
      "description" => PageMeta.description(meta),
      "canonical_url" => meta.canonical_url,
      "type" => PageMeta.og_type(meta),
      "image_template" => image_template,
      "image_stats" => image_stats,
      "author" => author_attrs
    }
    |> drop_nil_and_blank()
  end

  @doc """
  Returns the content-addressed hash for the given attrs.
  """
  @spec hash(map()) :: String.t()
  def hash(attrs) when is_map(attrs) do
    attrs
    |> drop_nil_and_blank()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns a stable signed token for the attrs, used to lazily generate images.
  """
  @spec token(map()) :: String.t()
  def token(attrs) when is_map(attrs) do
    attrs
    |> drop_nil_and_blank()
    |> Jason.encode!()
    |> Plug.Crypto.MessageVerifier.sign(secret())
  end

  @doc """
  Verifies a token and returns the decoded attrs.
  """
  @spec verify_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def verify_token(token) when is_binary(token) do
    with {:ok, json} <- Plug.Crypto.MessageVerifier.verify(token, secret()),
         {:ok, attrs} <- Jason.decode(json),
         true <- is_map(attrs) do
      {:ok, drop_nil_and_blank(attrs)}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Returns a storage key for a given hash and extension.
  """
  @spec storage_key(String.t(), String.t()) :: String.t()
  def storage_key(hash, ext) when is_binary(hash) and is_binary(ext) do
    Path.join([@storage_prefix, "#{hash}.#{ext}"])
  end

  @doc """
  Fetches an existing OG image, or generates and stores it if missing.
  """
  @spec fetch_or_create(String.t(), String.t() | nil) ::
          {:ok, %{content_type: String.t(), content: binary()}} | {:error, term()}
  def fetch_or_create(hash, token) when is_binary(hash) do
    case fetch_existing(hash) do
      {:ok, result} -> {:ok, result}
      {:error, :not_found} -> create_and_store(hash, token)
      {:error, _} = error -> error
    end
  end

  @spec fetch_existing(String.t()) ::
          {:ok, %{content_type: String.t(), content: binary()}} | {:error, term()}
  def fetch_existing(hash) do
    jpeg_key = storage_key(hash, "jpeg")

    case Storage.get(jpeg_key) do
      {:ok, content} ->
        {:ok, %{content_type: "image/jpeg", content: content}}

      {:error, :not_found} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  defp create_and_store(hash, token) do
    with true <- enabled?(),
         token when is_binary(token) and token != "" <- token,
         {:ok, attrs} <- verify_token(token),
         true <- hash(attrs) == hash do
      html = render_html(attrs)

      case Carta.render(Micelio.OG.BrowserPool, html, width: @width, height: @height) do
        {:ok, jpeg} ->
          _ = Storage.put_if_none_match(storage_key(hash, "jpeg"), jpeg)
          {:ok, %{content_type: "image/jpeg", content: jpeg}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :disabled}
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Renders the HTML template for the given attrs.
  """
  @spec render_html(map()) :: String.t()
  def render_html(attrs) when is_map(attrs) do
    case normalize_text(attrs["image_template"]) do
      "agent_progress" -> render_agent_progress_html(attrs)
      "agent_session" -> render_agent_session_html(attrs)
      "commit" -> render_commit_html(attrs)
      "pull_request" -> render_pull_request_html(attrs)
      _ -> render_default_html(attrs)
    end
  end

  defp render_default_html(attrs) do
    title = normalize_text(attrs["title"]) || PageMeta.site_name()
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    url_line = canonical_url && display_url(canonical_url)

    base_html(
      accent_color: "#2f7c4c",
      site_label: site_name,
      title: title,
      description: description,
      url_line: url_line,
      sidebar: nil,
      author: attrs["author"]
    )
  end

  defp render_agent_progress_html(attrs) do
    title = normalize_text(attrs["title"]) || "Agent progress"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])

    sidebar = """
    <div class="sidebar">
      <div class="sidebar-accent" style="background: #5bbf7a;"></div>
      <div class="sidebar-label">ACTIVITY SNAPSHOT</div>
      <div class="sidebar-divider"></div>
      #{stat_card("COMMITS", stat_value(stats, "commits"))}
      #{stat_card("FILES CHANGED", stat_value(stats, "files"))}
    </div>
    """

    base_html(
      accent_color: "#5bbf7a",
      site_label: "#{site_name} / Agents",
      title: title,
      description: description,
      url_line: canonical_url && display_url(canonical_url),
      sidebar: sidebar,
      author: attrs["author"]
    )
  end

  defp render_agent_session_html(attrs) do
    title = normalize_text(attrs["title"]) || "Agent session"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])

    sidebar = """
    <div class="sidebar">
      <div class="sidebar-accent" style="background: #4a9ecc;"></div>
      <div class="sidebar-label">SESSION STATS</div>
      <div class="sidebar-divider"></div>
      #{stat_card("FILES", stat_value(stats, "files"))}
      #{stat_row("ADDED", stat_value(stats, "added"))}
      #{stat_row("MODIFIED", stat_value(stats, "modified"))}
      #{stat_row("DELETED", stat_value(stats, "deleted"))}
    </div>
    """

    base_html(
      accent_color: "#4a9ecc",
      site_label: "#{site_name} / Sessions",
      title: title,
      description: description,
      url_line: canonical_url && display_url(canonical_url),
      sidebar: sidebar
    )
  end

  defp render_commit_html(attrs) do
    title = normalize_text(attrs["title"]) || "Commit"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])

    sidebar = """
    <div class="sidebar">
      <div class="sidebar-accent" style="background: #6a9fd8;"></div>
      <div class="sidebar-label">CHANGESET</div>
      <div class="sidebar-divider"></div>
      #{stat_card("FILES", stat_value(stats, "files"))}
      #{stat_row("ADDITIONS", stat_value(stats, "additions"))}
      #{stat_row("DELETIONS", stat_value(stats, "deletions"))}
    </div>
    """

    base_html(
      accent_color: "#6a9fd8",
      site_label: "#{site_name} / Commit",
      title: title,
      description: description,
      url_line: canonical_url && display_url(canonical_url),
      sidebar: sidebar
    )
  end

  defp render_pull_request_html(attrs) do
    title = normalize_text(attrs["title"]) || "Pull request"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])

    sidebar = """
    <div class="sidebar">
      <div class="sidebar-accent" style="background: #d4a03a;"></div>
      <div class="sidebar-label" style="color: #d4a03a;">REVIEW SNAPSHOT</div>
      <div class="sidebar-divider"></div>
      #{stat_card("COMMITS", stat_value(stats, "commits"))}
      #{stat_row("FILES", stat_value(stats, "files"))}
      #{stat_row("COMMENTS", stat_value(stats, "comments"))}
    </div>
    """

    base_html(
      accent_color: "#d4a03a",
      site_label: "#{site_name} / Pull Requests",
      title: title,
      description: description,
      url_line: canonical_url && display_url(canonical_url),
      sidebar: sidebar,
      author: attrs["author"]
    )
  end

  defp base_html(opts) do
    accent_color = Keyword.fetch!(opts, :accent_color)
    site_label = Keyword.fetch!(opts, :site_label)
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    url_line = Keyword.get(opts, :url_line)
    sidebar = Keyword.get(opts, :sidebar)
    author = Keyword.get(opts, :author)

    description_html =
      if description do
        ~s|<p class="description">#{escape(description)}</p>|
      else
        ""
      end

    footer_html = render_footer(url_line, author)

    sidebar_html = sidebar || ""

    has_sidebar = sidebar != nil

    content_style =
      if has_sidebar do
        "max-width: 660px;"
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
          width: #{@width}px;
          height: #{@height}px;
          background: #f6f8f5;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: hidden;
        }

        .card {
          position: relative;
          width: #{@width - 80}px;
          height: #{@height - 80}px;
          background: #ffffff;
          border: 1px solid #d0d7ce;
          border-radius: 12px;
          display: flex;
          overflow: hidden;
        }

        .accent-bar {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 5px;
          background: #{accent_color};
        }

        .content {
          flex: 1;
          padding: 48px 48px 40px;
          display: flex;
          flex-direction: column;
          justify-content: center;
          #{content_style}
        }

        .site-label {
          font-size: 22px;
          font-weight: 600;
          color: #2f7c4c;
          margin-bottom: 20px;
          letter-spacing: 0.02em;
        }

        .title {
          font-size: 52px;
          font-weight: 700;
          color: #1f2d23;
          line-height: 1.15;
          margin-bottom: 16px;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }

        .description {
          font-size: 24px;
          font-weight: 400;
          color: #5a6b58;
          line-height: 1.4;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }

        .footer {
          position: absolute;
          bottom: 36px;
          left: 48px;
          right: 48px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 18px;
          font-weight: 400;
          color: #8fa891;
        }

        .footer-url {
          font-size: 18px;
          color: #8fa891;
        }

        .author {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .author-avatar {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          border: 2px solid #d0d7ce;
        }

        .author-name {
          font-size: 16px;
          font-weight: 600;
          color: #5a6b58;
        }

        .sidebar {
          position: absolute;
          right: 40px;
          top: 50%;
          transform: translateY(-50%);
          width: 340px;
          background: #f6f8f5;
          border: 1px solid #d0d7ce;
          border-radius: 10px;
          padding: 24px;
          overflow: hidden;
        }

        .sidebar-accent {
          position: absolute;
          top: 0;
          left: 0;
          width: 4px;
          height: 100%;
        }

        .sidebar-label {
          font-size: 16px;
          font-weight: 700;
          color: #2f7c4c;
          letter-spacing: 0.08em;
          margin-bottom: 12px;
          padding-left: 8px;
        }

        .sidebar-divider {
          height: 1px;
          background: #d0d7ce;
          margin-bottom: 16px;
        }

        .stat-card {
          background: #ffffff;
          border: 1px solid #d0d7ce;
          border-radius: 10px;
          padding: 14px 16px;
          margin-bottom: 12px;
        }

        .stat-card-label {
          font-size: 14px;
          font-weight: 700;
          color: #2f7c4c;
          letter-spacing: 0.06em;
          margin-bottom: 4px;
        }

        .stat-card-value {
          font-size: 40px;
          font-weight: 700;
          color: #1f2d23;
          line-height: 1.1;
        }

        .stat-row {
          background: #ffffff;
          border: 1px solid #d0d7ce;
          border-radius: 8px;
          padding: 10px 16px;
          margin-bottom: 8px;
          display: flex;
          align-items: center;
          justify-content: space-between;
        }

        .stat-row-label {
          font-size: 13px;
          font-weight: 700;
          color: #2f7c4c;
          letter-spacing: 0.06em;
        }

        .stat-row-value {
          font-size: 20px;
          font-weight: 700;
          color: #1f2d23;
        }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="accent-bar"></div>
        <div class="content">
          <div class="site-label">#{escape(site_label)}</div>
          <div class="title">#{escape(title)}</div>
          #{description_html}
        </div>
        #{sidebar_html}
        #{footer_html}
      </div>
    </body>
    </html>
    """
  end

  defp render_footer(nil, nil), do: ""

  defp render_footer(url_line, author) do
    url_html =
      if url_line do
        ~s|<span class="footer-url">#{escape(url_line)}</span>|
      else
        "<span></span>"
      end

    author_html =
      case author do
        %{"name" => name, "avatar_url" => avatar_url} when is_binary(avatar_url) ->
          ~s|<div class="author"><img class="author-avatar" src="#{escape(avatar_url)}" /><span class="author-name">#{escape(name)}</span></div>|

        %{"name" => name} ->
          ~s|<div class="author"><span class="author-name">#{escape(name)}</span></div>|

        _ ->
          ""
      end

    ~s|<div class="footer">#{url_html}#{author_html}</div>|
  end

  defp stat_card(label, value) do
    """
    <div class="stat-card">
      <div class="stat-card-label">#{escape(label)}</div>
      <div class="stat-card-value">#{escape(value)}</div>
    </div>
    """
  end

  defp stat_row(label, value) do
    """
    <div class="stat-row">
      <span class="stat-row-label">#{escape(label)}</span>
      <span class="stat-row-value">#{escape(value)}</span>
    </div>
    """
  end

  defp author_attrs_from_meta(%PageMeta{author: %{name: name} = author}) when is_binary(name) do
    avatar_url = Micelio.Blog.People.gravatar_url(author, 120)

    %{"name" => name, "avatar_url" => avatar_url}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> case do
      attrs when map_size(attrs) > 0 -> attrs
      _ -> nil
    end
  end

  defp author_attrs_from_meta(_), do: nil

  defp image_template_from_meta(open_graph) when is_map(open_graph) do
    normalize_text(Map.get(open_graph, "image_template") || Map.get(open_graph, :image_template))
  end

  defp image_template_from_meta(_), do: nil

  defp image_stats_from_meta(open_graph) when is_map(open_graph) do
    open_graph
    |> Map.get("image_stats")
    |> case do
      nil -> Map.get(open_graph, :image_stats)
      stats -> stats
    end
    |> normalize_image_stats()
    |> case do
      %{} = stats when map_size(stats) > 0 -> stats
      _ -> nil
    end
  end

  defp image_stats_from_meta(_), do: nil

  defp normalize_image_stats(nil), do: %{}

  defp normalize_image_stats(stats) when is_map(stats) do
    Enum.reduce(stats, %{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp normalize_image_stats(_), do: %{}

  defp stat_value(stats, key) when is_map(stats) do
    case Map.get(stats, key) do
      nil -> "0"
      value when is_integer(value) -> Integer.to_string(value)
      value when is_binary(value) -> value
      value -> to_string(value)
    end
  end

  defp display_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) ->
        path = path || "/"
        host <> path

      _ ->
        url
    end
  rescue
    _ -> url
  end

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(text) when is_binary(text) do
    text =
      text
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    if text != "", do: text
  end

  defp drop_nil_and_blank(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp secret do
    MicelioWeb.Endpoint.config(:secret_key_base) ||
      raise "MicelioWeb.Endpoint secret_key_base is required to sign OG image tokens"
  end
end
