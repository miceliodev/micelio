defmodule MicelioWeb.OpenGraphImageControllerTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias Micelio.Storage
  alias MicelioWeb.OpenGraphImage

  test "home page includes og:image URL", %{conn: conn} do
    html = html_response(get(conn, ~p"/"), 200)
    doc = LazyHTML.from_document(html)

    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    [_, "og", hash] = String.split(uri.path || "", "/", parts: 3)

    assert %{"token" => token, "v" => v} = URI.decode_query(uri.query || "")
    assert is_binary(token) and token != ""
    assert v == hash
  end

  test "returns 404 for unknown hash when OG rendering is disabled", %{conn: conn} do
    conn = get(conn, ~p"/og/unknown-hash")
    assert conn.status == 404
  end

  describe "fetch_or_create with pre-stored images" do
    test "serves a pre-stored JPEG by hash" do
      attrs = %{
        "title" => "Test",
        "site_name" => "Micelio",
        "canonical_url" => "https://micelio.dev/test"
      }

      hash = OpenGraphImage.hash(attrs)
      jpeg_key = OpenGraphImage.storage_key(hash, "jpeg")

      jpeg_content = <<0xFF, 0xD8, 0xFF, 0xE0, "test-jpeg">>
      {:ok, _} = Storage.put(jpeg_key, jpeg_content)

      assert {:ok, %{content_type: "image/jpeg", content: ^jpeg_content}} =
               OpenGraphImage.fetch_existing(hash)

      _ = Storage.delete(jpeg_key)
    end

    test "returns not_found when no image exists" do
      assert {:error, :not_found} = OpenGraphImage.fetch_existing("nonexistent-hash")
    end
  end

  describe "hash and token" do
    test "hash is deterministic" do
      attrs = %{"title" => "Hello", "site_name" => "Micelio"}
      assert OpenGraphImage.hash(attrs) == OpenGraphImage.hash(attrs)
    end

    test "token round-trips through verify" do
      attrs = %{"title" => "Hello", "site_name" => "Micelio"}
      token = OpenGraphImage.token(attrs)
      assert {:ok, verified} = OpenGraphImage.verify_token(token)
      assert verified == attrs
    end

    test "verify_token rejects tampered tokens" do
      assert {:error, :invalid_token} = OpenGraphImage.verify_token("garbage")
    end
  end

  test "og:image URL uses content hash as version", %{conn: conn} do
    html = html_response(get(conn, ~p"/"), 200)
    doc = LazyHTML.from_document(html)

    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    [_, "og", hash] = String.split(uri.path || "", "/", parts: 3)

    assert %{"v" => v} = URI.decode_query(uri.query || "")
    assert v == hash
  end
end
