defmodule MicelioWeb.Plugs.OpenGraphCacheBuster do
  @moduledoc """
  Adds a cache-buster key for social crawlers so OG image URLs can be invalidated per platform.
  """

  import Plug.Conn

  alias MicelioWeb.PageMeta

  @default_cache_busters %{
    "discord" => "1",
    "facebook" => "1",
    "linkedin" => "1",
    "pinterest" => "1",
    "slack" => "1",
    "telegram" => "1",
    "twitter" => "1"
  }

  @platform_user_agents [
    {"twitter", ~r/Twitterbot/i},
    {"linkedin", ~r/LinkedInBot|LinkedIn/i},
    {"facebook", ~r/facebookexternalhit|Facebot/i},
    {"slack", ~r/Slackbot/i},
    {"discord", ~r/Discordbot/i},
    {"telegram", ~r/TelegramBot/i},
    {"pinterest", ~r/Pinterest/i}
  ]

  def init(opts), do: opts

  def call(conn, opts) do
    conn = ensure_vary_user_agent(conn)
    conn = fetch_query_params(conn)
    cache_busters = normalize_cache_busters(opts)

    manual_cache_buster = cache_buster_from_params(conn)
    platform = crawler_platform(conn)
    conn = maybe_disable_crawler_cache(conn, platform)

    og_cache_buster =
      cond do
        is_binary(manual_cache_buster) and manual_cache_buster != "" ->
          manual_cache_buster

        is_binary(platform) ->
          cache_buster = cache_buster_for(platform, cache_busters)
          if is_binary(cache_buster) and cache_buster != "", do: "#{platform}-#{cache_buster}"

        true ->
          nil
      end

    if is_binary(og_cache_buster) and og_cache_buster != "" do
      conn
      |> maybe_put_session("og_cache_buster", og_cache_buster)
      |> PageMeta.put(open_graph: %{cache_buster: og_cache_buster})
    else
      conn
    end
  end

  defp crawler_platform(conn) do
    conn
    |> get_req_header("user-agent")
    |> List.first()
    |> case do
      nil ->
        nil

      user_agent ->
        Enum.find_value(@platform_user_agents, fn {platform, regex} ->
          if Regex.match?(regex, user_agent), do: platform
        end)
    end
  end

  defp cache_buster_for(platform, cache_busters) do
    Map.get(cache_busters, platform) ||
      Map.get(cache_busters, "default") ||
      Map.get(@default_cache_busters, platform) ||
      Map.get(@default_cache_busters, "default")
  end

  defp normalize_cache_busters(opts) do
    opts
    |> Keyword.get(:cache_busters, Application.get_env(:micelio, :open_graph_cache_busters, %{}))
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp cache_buster_from_params(conn) do
    conn.query_params
    |> Map.get("og_cache_buster")
    |> normalize_cache_buster()
  end

  defp normalize_cache_buster(nil), do: nil

  defp normalize_cache_buster(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_cache_buster(_value), do: nil

  defp maybe_disable_crawler_cache(conn, platform) when is_binary(platform) do
    case get_resp_header(conn, "cache-control") do
      [] -> put_resp_header(conn, "cache-control", "no-cache, max-age=0, must-revalidate")
      _ -> conn
    end
  end

  defp maybe_disable_crawler_cache(conn, _platform), do: conn

  defp ensure_vary_user_agent(conn) do
    existing =
      conn
      |> get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.any?(existing, &(String.downcase(&1) == "user-agent")) do
      conn
    else
      updated =
        case existing do
          [] -> "User-Agent"
          _ -> Enum.join(existing ++ ["User-Agent"], ", ")
        end

      put_resp_header(conn, "vary", updated)
    end
  end

  defp maybe_put_session(conn, key, value) do
    if Map.has_key?(conn.private, :plug_session) do
      put_session(conn, key, value)
    else
      conn
    end
  end
end
