defmodule MicelioWeb.WellKnownController do
  use MicelioWeb, :controller

  def micelio(conn, _params) do
    web_url = web_url()
    grpc_url = grpc_url(web_url)

    payload =
      %{
        service: "micelio",
        web_url: web_url,
        grpc_url: grpc_url,
        client_id: Micelio.OAuth.cli_client_id(),
        api_base_path: "/api",
        rest_api_base: "#{web_url}/api",
        grpc_enabled: grpc_enabled?()
      }
      |> maybe_put(:cdn_url, cdn_base_url())

    json(conn, payload)
  end

  defp web_url do
    MicelioWeb.Endpoint.struct_url()
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp grpc_url(web_url) do
    case System.get_env("MICELIO_GRPC_URL") do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: default_grpc_url(web_url), else: value

      _ ->
        default_grpc_url(web_url)
    end
  end

  defp default_grpc_url(web_url) do
    grpc_config = Application.get_env(:micelio, Micelio.GRPC, [])
    port = Keyword.get(grpc_config, :port, 50_051)
    tls_mode = Keyword.get(grpc_config, :tls_mode, :required)
    scheme = if tls_mode in [:disabled, :insecure], do: "http", else: "https"
    host = URI.parse(web_url).host || "localhost"
    "#{scheme}://#{host}:#{port}"
  end

  defp grpc_enabled? do
    Application.get_env(:micelio, Micelio.GRPC, [])
    |> Keyword.get(:enabled, false)
  end

  defp cdn_base_url do
    config = Application.get_env(:micelio, Micelio.Storage, [])

    case Keyword.get(config, :cdn_base_url) do
      base when is_binary(base) and base != "" -> String.trim_trailing(base, "/")
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
