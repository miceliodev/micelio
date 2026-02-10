defmodule MicelioWeb.Browser.OpenGraphImageController do
  use MicelioWeb, :controller

  alias MicelioWeb.OpenGraphImage

  def show(conn, %{"hash" => hash} = params) do
    cache_key = normalize_cache_key(hash, Map.get(params, "v"))
    etag = ~s|"#{cache_key}"|

    if Enum.member?(get_req_header(conn, "if-none-match"), etag) do
      conn
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("etag", etag)
      |> send_resp(304, "")
    else
      token = Map.get(params, "token")

      case OpenGraphImage.fetch_or_create(hash, token) do
        {:ok, %{content_type: content_type, content: content}} ->
          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
          |> put_resp_header("etag", etag)
          |> send_resp(200, content)

        {:error, :invalid_token} ->
          send_resp(conn, 404, "Not found")

        {:error, :not_found} ->
          send_resp(conn, 404, "Not found")

        {:error, _reason} ->
          send_resp(conn, 500, "Error")
      end
    end
  end

  defp normalize_cache_key(hash, cache_key) when is_binary(hash) do
    cache_key = if is_binary(cache_key), do: cache_key, else: ""

    if cache_key != "" and String.starts_with?(cache_key, hash) do
      cache_key
    else
      hash
    end
  end
end
