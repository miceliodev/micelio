defmodule MicelioWeb.PageMeta do
  @moduledoc """
  Runtime API for setting per-request page metadata (title, description, Open Graph).

  Controllers can call `put/2` and LiveViews can call `assign/2`. The root layout
  reads `:page_meta` assigns and renders `<title>` and meta tags accordingly.
  """

  alias Phoenix.LiveView.Socket
  alias Plug.Conn

  @site_name "Micelio"
  @separator " · "

  defstruct title_parts: [],
            description: nil,
            canonical_url: nil,
            type: nil,
            open_graph: %{},
            author: nil

  def site_name, do: @site_name

  @doc """
  Put page metadata into a controller conn.
  """
  @spec put(Conn.t(), keyword() | map()) :: Conn.t()
  def put(%Conn{} = conn, opts) do
    meta = merge(from_assigns(conn.assigns), opts)
    Conn.assign(conn, :page_meta, meta)
  end

  @doc """
  Assign page metadata into a LiveView socket.
  """
  @spec assign(Socket.t(), keyword() | map()) :: Socket.t()
  def assign(%Socket{} = socket, opts) do
    meta = merge(from_assigns(socket.assigns), opts)
    Phoenix.Component.assign(socket, :page_meta, meta)
  end

  @doc """
  Reads metadata from assigns (supports legacy `:page_title` for compatibility).
  """
  @spec from_assigns(map()) :: t()
  def from_assigns(assigns) when is_map(assigns) do
    base =
      case assigns do
        %{page_meta: %__MODULE__{} = meta} -> meta
        _ -> %__MODULE__{}
      end

    case assigns do
      %{page_title: title} when is_binary(title) and title != "" and base.title_parts == [] ->
        %{base | title_parts: title_parts(title)}

      _ ->
        base
    end
  end

  @type t :: %__MODULE__{
          title_parts: [String.t()],
          description: String.t() | nil,
          canonical_url: String.t() | nil,
          type: String.t() | nil,
          open_graph: map(),
          author: map() | nil
        }

  @doc """
  Returns the full document title, following GitHub's `A · B · Site` convention.
  """
  @spec title(t()) :: String.t()
  def title(%__MODULE__{} = meta) do
    parts =
      meta.title_parts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    parts =
      case parts do
        [] -> [@site_name]
        _ -> maybe_append_site(parts)
      end

    Enum.join(parts, @separator)
  end

  @spec description(t()) :: String.t() | nil
  def description(%__MODULE__{} = meta) do
    case meta.description do
      nil -> nil
      "" -> nil
      desc -> desc |> String.trim() |> String.replace(~r/\s+/, " ")
    end
  end

  @spec og_title(t()) :: String.t()
  def og_title(%__MODULE__{} = meta) do
    case meta.title_parts |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [first | _] -> first
      [] -> @site_name
    end
  end

  @spec og_type(t()) :: String.t()
  def og_type(%__MODULE__{} = meta) do
    case meta.type do
      nil -> "website"
      "" -> "website"
      type -> type
    end
  end

  @spec open_graph(t()) :: map()
  def open_graph(%__MODULE__{} = meta) do
    og =
      meta.open_graph
      |> normalize_map()
      |> Map.drop([
        :title,
        :description,
        :type,
        :url,
        :site_name,
        :image_template,
        :image_stats,
        :cache_buster,
        "image_template",
        "image_stats",
        "cache_buster"
      ])

    if has_og_image?(og) do
      maybe_apply_cache_buster(og, meta)
    else
      case MicelioWeb.OpenGraphImage.url(meta) do
        nil ->
          og

        url ->
          defaults = %{
            "og:image:alt" => title(meta),
            "og:image:width" => Integer.to_string(MicelioWeb.OpenGraphImage.width()),
            "og:image:height" => Integer.to_string(MicelioWeb.OpenGraphImage.height()),
            image: url
          }

          Map.merge(defaults, og)
      end
    end
  end

  defp has_og_image?(og) when is_map(og) do
    Map.has_key?(og, :image) or Map.has_key?(og, "image") or Map.has_key?(og, "og:image")
  end

  @spec og_extra_tags(t()) :: [{String.t(), String.t()}]
  def og_extra_tags(%__MODULE__{} = meta) do
    meta
    |> open_graph()
    |> Enum.map(fn {key, value} -> {to_og_property(key), to_string(value)} end)
  end

  @doc """
  Returns the Twitter Card type. Uses "summary_large_image" when an OG image is present.
  """
  @spec twitter_card(t()) :: String.t()
  def twitter_card(%__MODULE__{} = meta) do
    og = open_graph(meta)

    if has_og_image?(og) do
      "summary_large_image"
    else
      "summary"
    end
  end

  @doc """
  Returns Twitter-specific extra tags (image, creator, etc.).
  """
  @spec twitter_extra_tags(t()) :: [{String.t(), String.t()}]
  def twitter_extra_tags(%__MODULE__{} = meta) do
    og = open_graph(meta)

    tags = []

    tags =
      case Map.get(og, :image) || Map.get(og, "image") || Map.get(og, "og:image") do
        nil -> tags
        url -> [{"twitter:image", to_string(url)} | tags]
      end

    tags =
      case Map.get(og, "og:image:alt") do
        nil -> tags
        alt -> [{"twitter:image:alt", to_string(alt)} | tags]
      end

    # Add twitter:creator if author has X handle
    tags =
      case meta.author do
        %{x_handle: handle} when is_binary(handle) and handle != "" ->
          [{"twitter:creator", "@" <> handle} | tags]

        _ ->
          tags
      end

    Enum.reverse(tags)
  end

  @doc """
  Returns Fediverse/Mastodon author tag if author has a Mastodon handle.
  """
  @spec fediverse_creator(t()) :: String.t() | nil
  def fediverse_creator(%__MODULE__{author: %{mastodon_handle: handle}})
      when is_binary(handle) and handle != "" do
    handle
  end

  def fediverse_creator(_meta), do: nil

  @spec merge(t(), keyword() | map()) :: t()
  def merge(%__MODULE__{} = meta, opts) when is_list(opts) or is_map(opts) do
    opts = normalize_map(opts)

    meta
    |> maybe_put(:title_parts, opts, fn value -> title_parts(value) end)
    |> maybe_put(:description, opts, & &1)
    |> maybe_put(:canonical_url, opts, & &1)
    |> maybe_put(:type, opts, & &1)
    |> maybe_put(:author, opts, & &1)
    |> maybe_merge_open_graph(opts)
  end

  defp maybe_merge_open_graph(%__MODULE__{} = meta, opts) do
    og =
      opts
      |> Map.get(:open_graph, %{})
      |> normalize_map()

    if map_size(og) == 0 do
      meta
    else
      %{meta | open_graph: Map.merge(meta.open_graph, og)}
    end
  end

  defp maybe_put(%__MODULE__{} = meta, key, opts, transform) do
    case Map.fetch(opts, key) do
      {:ok, nil} -> meta
      {:ok, value} -> Map.put(meta, key, transform.(value))
      :error -> meta
    end
  end

  defp title_parts(value) when is_binary(value), do: [value]
  defp title_parts(value) when is_list(value), do: Enum.map(value, &to_string/1)

  defp maybe_append_site(parts) do
    case List.last(parts) do
      @site_name -> parts
      _ -> parts ++ [@site_name]
    end
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)

  defp to_og_property(key) when is_atom(key), do: "og:" <> Atom.to_string(key)

  defp to_og_property(key) when is_binary(key) do
    if String.contains?(key, ":") do
      key
    else
      "og:" <> key
    end
  end

  defp maybe_apply_cache_buster(og, %__MODULE__{} = meta) when is_map(og) do
    case cache_buster(meta.open_graph) do
      nil -> og
      cache_buster -> update_og_image_urls(og, cache_buster)
    end
  end

  defp maybe_apply_cache_buster(og, _meta), do: og

  defp cache_buster(open_graph) when is_map(open_graph) do
    open_graph
    |> Map.get(:cache_buster)
    |> case do
      nil -> Map.get(open_graph, "cache_buster")
      value -> value
    end
    |> normalize_cache_buster()
  end

  defp cache_buster(_open_graph), do: nil

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

  defp update_og_image_urls(og, cache_buster) when is_map(og) and is_binary(cache_buster) do
    keys = [
      :image,
      "image",
      "og:image",
      :"og:image",
      "og:image:secure_url",
      :"og:image:secure_url"
    ]

    Enum.reduce(keys, og, fn key, acc ->
      case Map.fetch(acc, key) do
        {:ok, value} -> Map.put(acc, key, append_cache_buster(value, cache_buster))
        :error -> acc
      end
    end)
  end

  defp update_og_image_urls(og, _cache_buster), do: og

  defp append_cache_buster(url, cache_buster) when is_binary(url) and is_binary(cache_buster) do
    with %URI{} = uri <- URI.parse(url),
         false <- uri.scheme == "data" do
      query =
        uri.query
        |> case do
          nil -> %{}
          "" -> %{}
          existing -> URI.decode_query(existing)
        end
        |> Map.put("v", cache_buster)

      uri
      |> Map.put(:query, URI.encode_query(query))
      |> URI.to_string()
    else
      _ -> url
    end
  rescue
    _ -> url
  end

  defp append_cache_buster(url, _cache_buster), do: url
end
