defmodule MicelioWeb.OpenGraphImageControllerTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias Micelio.Storage
  alias MicelioWeb.OpenGraphImage

  test "home page includes og:image and it generates lazily", %{conn: conn} do
    html = html_response(get(conn, ~p"/"), 200)
    doc = LazyHTML.from_document(html)

    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    [_, "og", hash] = String.split(uri.path || "", "/", parts: 3)

    assert %{"token" => token, "v" => v} = URI.decode_query(uri.query || "")
    assert is_binary(token) and token != ""
    assert v == hash

    svg_key = OpenGraphImage.storage_key(hash, "svg")
    png_key = OpenGraphImage.storage_key(hash, "png")
    _ = Storage.delete(svg_key)
    _ = Storage.delete(png_key)

    refute Storage.exists?(svg_key)
    refute Storage.exists?(png_key)

    conn = get(build_conn(), uri.path <> "?" <> uri.query)
    assert conn.status == 200

    content_type = conn |> get_resp_header("content-type") |> List.first()

    assert String.starts_with?(content_type, "image/png") or
             String.starts_with?(content_type, "image/svg+xml")

    assert Storage.exists?(svg_key) or Storage.exists?(png_key)

    conn =
      build_conn()
      |> put_req_header("if-none-match", ~s|"#{hash}"|)
      |> get(uri.path <> "?" <> uri.query)

    assert conn.status == 304
  end

  test "social crawlers receive cache-busted og:image URLs", %{conn: conn} do
    conn = put_req_header(conn, "user-agent", "Twitterbot/1.0")
    html = html_response(get(conn, ~p"/"), 200)
    doc = LazyHTML.from_document(html)

    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    [_, "og", hash] = String.split(uri.path || "", "/", parts: 3)

    assert %{"v" => v} = URI.decode_query(uri.query || "")
    assert v == "#{hash}-twitter-1"
  end

  test "cache-buster changes etag for social crawlers", %{conn: conn} do
    conn = put_req_header(conn, "user-agent", "Twitterbot/1.0")
    html = html_response(get(conn, ~p"/"), 200)
    doc = LazyHTML.from_document(html)

    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    [_, "og", hash] = String.split(uri.path || "", "/", parts: 3)

    assert %{"token" => _token, "v" => v} = URI.decode_query(uri.query || "")
    assert v == "#{hash}-twitter-1"

    svg_key = OpenGraphImage.storage_key(hash, "svg")
    png_key = OpenGraphImage.storage_key(hash, "png")
    _ = Storage.delete(svg_key)
    _ = Storage.delete(png_key)

    refute Storage.exists?(svg_key)
    refute Storage.exists?(png_key)

    conn = get(build_conn(), uri.path <> "?" <> uri.query)
    assert conn.status == 200

    conn =
      build_conn()
      |> put_req_header("if-none-match", ~s|"#{hash}"|)
      |> get(uri.path <> "?" <> uri.query)

    assert conn.status == 200

    conn =
      build_conn()
      |> put_req_header("if-none-match", ~s|"#{v}"|)
      |> get(uri.path <> "?" <> uri.query)

    assert conn.status == 304
    assert Storage.exists?(svg_key) or Storage.exists?(png_key)
  end
end
