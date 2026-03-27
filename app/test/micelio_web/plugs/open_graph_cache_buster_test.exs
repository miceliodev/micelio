defmodule MicelioWeb.Plugs.OpenGraphCacheBusterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias MicelioWeb.PageMeta
  alias MicelioWeb.Plugs.OpenGraphCacheBuster

  test "uses platform override cache buster when configured" do
    conn =
      conn(:get, "/")
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call(cache_busters: %{twitter: "42"})

    meta = PageMeta.from_assigns(conn.assigns)

    assert meta.open_graph[:cache_buster] == "twitter-42"
  end

  test "uses default override when only default is configured" do
    conn =
      conn(:get, "/")
      |> put_req_header("user-agent", "Discordbot/2.0")
      |> OpenGraphCacheBuster.call(cache_busters: %{default: "99"})

    meta = PageMeta.from_assigns(conn.assigns)

    assert meta.open_graph[:cache_buster] == "discord-99"
  end

  test "falls back to built-in cache buster when no overrides exist" do
    conn =
      conn(:get, "/")
      |> put_req_header("user-agent", "Slackbot 1.0")
      |> OpenGraphCacheBuster.call([])

    meta = PageMeta.from_assigns(conn.assigns)

    assert meta.open_graph[:cache_buster] == "slack-1"
  end

  test "adds vary user-agent header to avoid cached crawler mixups" do
    conn =
      conn(:get, "/")
      |> OpenGraphCacheBuster.call([])

    vary =
      conn
      |> Plug.Conn.get_resp_header("vary")
      |> Enum.join(", ")
      |> String.downcase()

    assert String.contains?(vary, "user-agent")
  end

  test "sets no-cache headers for crawler responses when missing" do
    conn =
      conn(:get, "/")
      |> delete_resp_header("cache-control")
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call([])

    assert Plug.Conn.get_resp_header(conn, "cache-control") == [
             "no-cache, max-age=0, must-revalidate"
           ]
  end

  test "does not override existing cache-control headers for crawlers" do
    conn =
      conn(:get, "/")
      |> put_resp_header("cache-control", "public, max-age=60")
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call([])

    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["public, max-age=60"]
  end

  test "propagates cache buster into og image query version" do
    conn =
      conn(:get, "/")
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call(cache_busters: %{twitter: "21"})
      |> PageMeta.put(
        canonical_url: "https://example.com/projects/demo",
        title_parts: ["Demo"],
        description: "Demo project"
      )

    meta = PageMeta.from_assigns(conn.assigns)
    og = PageMeta.open_graph(meta)
    image = Map.get(og, :image) || Map.get(og, "image") || Map.get(og, "og:image")

    assert image

    uri = URI.parse(image)
    assert %{"v" => version} = URI.decode_query(uri.query || "")
    assert String.ends_with?(version, "-twitter-21")
  end

  test "stores cache buster in session for LiveView mounts" do
    conn =
      conn(:get, "/")
      |> init_test_session(%{})
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call(cache_busters: %{twitter: "7"})

    assert get_session(conn, "og_cache_buster") == "twitter-7"
  end

  test "uses explicit og_cache_buster query param for manual invalidation" do
    conn =
      conn(:get, "/?og_cache_buster=manual-44")
      |> put_req_header("user-agent", "Twitterbot/1.0")
      |> OpenGraphCacheBuster.call([])

    meta = PageMeta.from_assigns(conn.assigns)

    assert meta.open_graph[:cache_buster] == "manual-44"
  end
end
