defmodule MicelioWeb.OpenGraphImage do
  @moduledoc """
  Lazy Open Graph image generation persisted via `Micelio.Storage`.

  Images are content-addressed: we hash the attributes required to render the image,
  and store the resulting artifact under that hash. The first request to the image
  endpoint generates and persists it.
  """

  alias Micelio.Storage
  alias MicelioWeb.PageMeta

  @width 1200
  @height 630
  @template_version 2

  @storage_prefix "open-graph/og"

  def width, do: @width
  def height, do: @height

  @doc """
  Returns the Open Graph image URL for the given page meta, or `nil`.
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

    %{
      "v" => @template_version,
      "site_name" => PageMeta.site_name(),
      "title" => PageMeta.og_title(meta),
      "description" => PageMeta.description(meta),
      "canonical_url" => meta.canonical_url,
      "type" => PageMeta.og_type(meta),
      "image_template" => image_template,
      "image_stats" => image_stats
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

  Prefers a stored PNG when available; otherwise serves SVG.
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
    png_key = storage_key(hash, "png")
    svg_key = storage_key(hash, "svg")

    case Storage.get(png_key) do
      {:ok, content} ->
        {:ok, %{content_type: "image/png", content: content}}

      {:error, :not_found} ->
        case Storage.get(svg_key) do
          {:ok, svg} ->
            case svg_to_png(svg) do
              {:ok, png} ->
                _ = Storage.put_if_none_match(png_key, png)
                {:ok, %{content_type: "image/png", content: png}}

              {:error, _reason} ->
                {:ok, %{content_type: "image/svg+xml", content: svg}}
            end

          {:error, :not_found} ->
            {:error, :not_found}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp create_and_store(hash, token) do
    with token when is_binary(token) and token != "" <- token,
         {:ok, attrs} <- verify_token(token),
         true <- hash(attrs) == hash do
      svg = render_svg(attrs)
      _ = Storage.put_if_none_match(storage_key(hash, "svg"), svg)

      case svg_to_png(svg) do
        {:ok, png} ->
          _ = Storage.put_if_none_match(storage_key(hash, "png"), png)
          {:ok, %{content_type: "image/png", content: png}}

        {:error, _reason} ->
          {:ok, %{content_type: "image/svg+xml", content: svg}}
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  @spec render_svg(map()) :: binary()
  def render_svg(attrs) when is_map(attrs) do
    case normalize_text(attrs["image_template"]) do
      "agent_progress" -> render_agent_progress_svg(attrs)
      "agent_session" -> render_agent_session_svg(attrs)
      "commit" -> render_commit_svg(attrs)
      "pull_request" -> render_pull_request_svg(attrs)
      _ -> render_default_svg(attrs)
    end
  end

  defp render_default_svg(attrs) do
    title = normalize_text(attrs["title"]) || PageMeta.site_name()
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])

    title_lines = wrap_lines(title, 38, 2)
    description_lines = wrap_lines(description, 62, 3)
    url_line = canonical_url && display_url(canonical_url)

    title_y = 220
    title_line_height = 76

    description_y =
      title_y + title_line_height * length(title_lines) + 26

    description_line_height = 44
    footer_y = 565

    [
      ~s|<svg width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Open Graph image">|,
      ~s|<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">|,
      ~s|<stop offset="0%" stop-color="#0b0f14"/><stop offset="100%" stop-color="#111827"/>|,
      ~s|</linearGradient></defs>|,
      ~s|<rect width="#{@width}" height="#{@height}" fill="url(#bg)"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="#{@height - 80}" rx="28" fill="#0f172a" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="40" y="40" width="10" height="#{@height - 80}" rx="5" fill="#7c3aed"/>|,
      text_el(80, 130, site_name, "28", "600", "#a7b2c8"),
      title_text(80, title_y, title_lines, "64", "700", "#f8fafc", title_line_height),
      description_text(
        80,
        description_y,
        description_lines,
        "30",
        "500",
        "#cbd5e1",
        description_line_height
      ),
      footer_text(80, footer_y, url_line, "24", "500", "#94a3b8"),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_agent_progress_svg(attrs) do
    title = normalize_text(attrs["title"]) || "Agent progress"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])
    commits = stat_value(stats, "commits")
    files = stat_value(stats, "files")

    title_lines = wrap_lines(title, 30, 2)
    description_lines = wrap_lines(description, 52, 3)
    url_line = canonical_url && display_url(canonical_url)

    title_y = 210
    title_line_height = 72

    description_y =
      title_y + title_line_height * length(title_lines) + 18

    description_line_height = 40
    footer_y = 560

    [
      ~s|<svg width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Agent progress Open Graph image">|,
      ~s|<defs><linearGradient id="bg-agent" x1="0" y1="0" x2="1" y2="1">|,
      ~s|<stop offset="0%" stop-color="#0a0f18"/><stop offset="100%" stop-color="#0f172a"/>|,
      ~s|</linearGradient></defs>|,
      ~s|<rect width="#{@width}" height="#{@height}" fill="url(#bg-agent)"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="#{@height - 80}" rx="30" fill="#0b1220" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="10" rx="5" fill="#22c55e"/>|,
      text_el(80, 120, "#{site_name} / Agents", "26", "600", "#94a3b8"),
      title_text(80, title_y, title_lines, "60", "700", "#f8fafc", title_line_height),
      description_text(
        80,
        description_y,
        description_lines,
        "28",
        "500",
        "#cbd5f5",
        description_line_height
      ),
      ~s|<rect x="740" y="160" width="380" height="330" rx="26" fill="#0f172a" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="740" y="160" width="6" height="330" rx="3" fill="#22c55e"/>|,
      text_el(780, 205, "ACTIVITY SNAPSHOT", "20", "700", "#a5b4fc"),
      ~s|<line x1="780" y1="230" x2="1080" y2="230" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="770" y="250" width="330" height="90" rx="18" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 285, "COMMITS", "20", "700", "#7dd3fc"),
      text_el(790, 325, commits, "54", "700", "#e2e8f0"),
      ~s|<rect x="770" y="360" width="330" height="110" rx="18" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 400, "FILES CHANGED", "20", "700", "#7dd3fc"),
      text_el(790, 445, files, "54", "700", "#e2e8f0"),
      footer_text(80, footer_y, url_line, "24", "500", "#94a3b8"),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_agent_session_svg(attrs) do
    title = normalize_text(attrs["title"]) || "Agent session"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])
    files = stat_value(stats, "files")
    added = stat_value(stats, "added")
    modified = stat_value(stats, "modified")
    deleted = stat_value(stats, "deleted")

    title_lines = wrap_lines(title, 32, 2)
    description_lines = wrap_lines(description, 56, 3)
    url_line = canonical_url && display_url(canonical_url)

    title_y = 200
    title_line_height = 70

    description_y =
      title_y + title_line_height * length(title_lines) + 22

    description_line_height = 38
    footer_y = 560

    [
      ~s|<svg width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Agent session Open Graph image">|,
      ~s|<defs><linearGradient id="bg-session" x1="0" y1="0" x2="1" y2="1">|,
      ~s|<stop offset="0%" stop-color="#0b0f14"/><stop offset="100%" stop-color="#0c1f24"/>|,
      ~s|</linearGradient></defs>|,
      ~s|<rect width="#{@width}" height="#{@height}" fill="url(#bg-session)"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="#{@height - 80}" rx="28" fill="#0b1220" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="10" rx="5" fill="#38bdf8"/>|,
      text_el(80, 120, "#{site_name} / Sessions", "26", "600", "#93c5fd"),
      title_text(80, title_y, title_lines, "58", "700", "#f8fafc", title_line_height),
      description_text(
        80,
        description_y,
        description_lines,
        "28",
        "500",
        "#cbd5f5",
        description_line_height
      ),
      ~s|<rect x="740" y="160" width="380" height="330" rx="26" fill="#0f172a" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="740" y="160" width="6" height="330" rx="3" fill="#38bdf8"/>|,
      text_el(780, 205, "SESSION STATS", "20", "700", "#7dd3fc"),
      ~s|<line x1="780" y1="230" x2="1080" y2="230" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="770" y="250" width="330" height="80" rx="18" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 282, "FILES", "20", "700", "#7dd3fc"),
      text_el(790, 318, files, "44", "700", "#e2e8f0"),
      ~s|<rect x="770" y="340" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 370, "ADDED", "18", "700", "#7dd3fc"),
      text_el(960, 370, added, "26", "700", "#e2e8f0"),
      ~s|<rect x="770" y="410" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 440, "MODIFIED", "18", "700", "#7dd3fc"),
      text_el(960, 440, modified, "26", "700", "#e2e8f0"),
      ~s|<rect x="770" y="480" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 510, "DELETED", "18", "700", "#7dd3fc"),
      text_el(960, 510, deleted, "26", "700", "#e2e8f0"),
      footer_text(80, footer_y, url_line, "24", "500", "#94a3b8"),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_commit_svg(attrs) do
    title = normalize_text(attrs["title"]) || "Commit"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])
    files = stat_value(stats, "files")
    additions = stat_value(stats, "additions")
    deletions = stat_value(stats, "deletions")

    title_lines = wrap_lines(title, 32, 2)
    description_lines = wrap_lines(description, 54, 3)
    url_line = canonical_url && display_url(canonical_url)

    title_y = 200
    title_line_height = 70

    description_y =
      title_y + title_line_height * length(title_lines) + 22

    description_line_height = 38
    footer_y = 560

    [
      ~s|<svg width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Commit Open Graph image">|,
      ~s|<defs><linearGradient id="bg-commit" x1="0" y1="0" x2="1" y2="1">|,
      ~s|<stop offset="0%" stop-color="#0b1220"/><stop offset="100%" stop-color="#111827"/>|,
      ~s|</linearGradient></defs>|,
      ~s|<rect width="#{@width}" height="#{@height}" fill="url(#bg-commit)"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="#{@height - 80}" rx="28" fill="#0b1220" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="10" rx="5" fill="#60a5fa"/>|,
      text_el(80, 120, "#{site_name} / Commit", "26", "600", "#93c5fd"),
      title_text(80, title_y, title_lines, "58", "700", "#f8fafc", title_line_height),
      description_text(
        80,
        description_y,
        description_lines,
        "28",
        "500",
        "#cbd5f5",
        description_line_height
      ),
      ~s|<rect x="740" y="180" width="380" height="300" rx="26" fill="#0f172a" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="740" y="180" width="6" height="300" rx="3" fill="#60a5fa"/>|,
      text_el(780, 225, "CHANGESET", "20", "700", "#7dd3fc"),
      ~s|<line x1="780" y1="250" x2="1080" y2="250" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="770" y="270" width="330" height="70" rx="18" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 300, "FILES", "20", "700", "#7dd3fc"),
      text_el(790, 330, files, "38", "700", "#e2e8f0"),
      ~s|<rect x="770" y="350" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 380, "ADDITIONS", "18", "700", "#7dd3fc"),
      text_el(980, 380, additions, "26", "700", "#e2e8f0"),
      ~s|<rect x="770" y="420" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 450, "DELETIONS", "18", "700", "#7dd3fc"),
      text_el(980, 450, deletions, "26", "700", "#e2e8f0"),
      footer_text(80, footer_y, url_line, "24", "500", "#94a3b8"),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_pull_request_svg(attrs) do
    title = normalize_text(attrs["title"]) || "Pull request"
    site_name = normalize_text(attrs["site_name"]) || PageMeta.site_name()
    description = normalize_text(attrs["description"])
    canonical_url = normalize_text(attrs["canonical_url"])
    stats = normalize_image_stats(attrs["image_stats"])
    commits = stat_value(stats, "commits")
    files = stat_value(stats, "files")
    comments = stat_value(stats, "comments")

    title_lines = wrap_lines(title, 32, 2)
    description_lines = wrap_lines(description, 54, 3)
    url_line = canonical_url && display_url(canonical_url)

    title_y = 200
    title_line_height = 70

    description_y =
      title_y + title_line_height * length(title_lines) + 22

    description_line_height = 38
    footer_y = 560

    [
      ~s|<svg width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Pull request Open Graph image">|,
      ~s|<defs><linearGradient id="bg-pr" x1="0" y1="0" x2="1" y2="1">|,
      ~s|<stop offset="0%" stop-color="#0f172a"/><stop offset="100%" stop-color="#1f2937"/>|,
      ~s|</linearGradient></defs>|,
      ~s|<rect width="#{@width}" height="#{@height}" fill="url(#bg-pr)"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="#{@height - 80}" rx="28" fill="#0f172a" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="40" y="40" width="#{@width - 80}" height="10" rx="5" fill="#f59e0b"/>|,
      text_el(80, 120, "#{site_name} / Pull Requests", "26", "600", "#fcd34d"),
      title_text(80, title_y, title_lines, "58", "700", "#f8fafc", title_line_height),
      description_text(
        80,
        description_y,
        description_lines,
        "28",
        "500",
        "#e5e7eb",
        description_line_height
      ),
      ~s|<rect x="740" y="180" width="380" height="300" rx="26" fill="#111827" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="740" y="180" width="6" height="300" rx="3" fill="#f59e0b"/>|,
      text_el(780, 225, "REVIEW SNAPSHOT", "20", "700", "#fcd34d"),
      ~s|<line x1="780" y1="250" x2="1080" y2="250" stroke="#1f2a44" stroke-width="2"/>|,
      ~s|<rect x="770" y="270" width="330" height="70" rx="18" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 300, "COMMITS", "20", "700", "#fcd34d"),
      text_el(790, 330, commits, "38", "700", "#f8fafc"),
      ~s|<rect x="770" y="350" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 380, "FILES", "18", "700", "#fcd34d"),
      text_el(980, 380, files, "26", "700", "#f8fafc"),
      ~s|<rect x="770" y="420" width="330" height="60" rx="16" fill="#111c2f" stroke="#1f2a44" stroke-width="2"/>|,
      text_el(790, 450, "COMMENTS", "18", "700", "#fcd34d"),
      text_el(980, 450, comments, "26", "700", "#f8fafc"),
      footer_text(80, footer_y, url_line, "24", "500", "#9ca3af"),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp title_text(_x, _y, [], _size, _weight, _fill, _line_height), do: ""

  defp title_text(x, y, lines, size, weight, fill, line_height) do
    tspans =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        dy = if idx == 0, do: "0", else: Integer.to_string(line_height)
        ~s|<tspan x="#{x}" dy="#{dy}">#{escape(line)}</tspan>|
      end)

    [
      ~s|<text x="#{x}" y="#{y}" fill="#{fill}" font-family="#{font_family()}" font-size="#{size}" font-weight="#{weight}">|,
      tspans,
      "</text>"
    ]
    |> IO.iodata_to_binary()
  end

  defp description_text(_x, _y, [], _size, _weight, _fill, _line_height), do: ""

  defp description_text(x, y, lines, size, weight, fill, line_height) do
    tspans =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        dy = if idx == 0, do: "0", else: Integer.to_string(line_height)
        ~s|<tspan x="#{x}" dy="#{dy}">#{escape(line)}</tspan>|
      end)

    [
      ~s|<text x="#{x}" y="#{y}" fill="#{fill}" font-family="#{font_family()}" font-size="#{size}" font-weight="#{weight}">|,
      tspans,
      "</text>"
    ]
    |> IO.iodata_to_binary()
  end

  defp footer_text(_x, _y, nil, _size, _weight, _fill), do: ""

  defp footer_text(x, y, line, size, weight, fill) do
    text_el(x, y, line, size, weight, fill)
  end

  defp text_el(x, y, content, size, weight, fill) do
    ~s|<text x="#{x}" y="#{y}" fill="#{fill}" font-family="#{font_family()}" font-size="#{size}" font-weight="#{weight}">#{escape(content)}</text>|
  end

  defp font_family do
    "ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
  end

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

  defp wrap_lines(nil, _max_chars, _max_lines), do: []

  defp wrap_lines(text, max_chars, max_lines) when is_binary(text) do
    words =
      text
      |> String.split(~r/\s+/, trim: true)

    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        candidate =
          if current == "" do
            word
          else
            current <> " " <> word
          end

        if String.length(candidate) <= max_chars do
          {lines, candidate}
        else
          {[current | lines], word}
        end
      end)

    lines =
      [current | lines]
      |> Enum.reverse()
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] ->
        []

      _ ->
        if length(lines) > max_lines do
          {head, tail} = Enum.split(lines, max_lines)

          List.replace_at(
            head,
            max_lines - 1,
            truncate_ellipsis(Enum.at(tail, 0) || Enum.at(head, max_lines - 1))
          )
        else
          lines
        end
    end
  end

  defp truncate_ellipsis(text) when is_binary(text) do
    max = 60

    if String.length(text) <= max do
      text <> "…"
    else
      String.slice(text, 0, max) <> "…"
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

  defp svg_to_png(svg) when is_binary(svg) do
    case find_svg_converter() do
      {:ok, exec} ->
        args = [
          "-w",
          Integer.to_string(@width),
          "-h",
          Integer.to_string(@height),
          "-f",
          "png",
          temp_svg_path()
        ]

        path = List.last(args)

        try do
          :ok = File.write(path, svg)
          {png, status} = System.cmd(exec, args)
          if status == 0, do: {:ok, png}, else: {:error, :convert_failed}
        after
          _ = File.rm(path)
        end

      :error ->
        {:error, :no_converter}
    end
  rescue
    _ -> {:error, :convert_failed}
  end

  defp temp_svg_path do
    suffix =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    Path.join(System.tmp_dir!(), "micelio-og-#{suffix}.svg")
  end

  defp find_svg_converter do
    case System.find_executable("rsvg-convert") do
      nil ->
        ["/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert", "/usr/bin/rsvg-convert"]
        |> Enum.find(&File.regular?/1)
        |> case do
          nil -> :error
          path -> {:ok, path}
        end

      path ->
        {:ok, path}
    end
  end

  defp secret do
    MicelioWeb.Endpoint.config(:secret_key_base) ||
      raise "MicelioWeb.Endpoint secret_key_base is required to sign OG image tokens"
  end
end
