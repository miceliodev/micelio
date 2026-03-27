defmodule MicelioWeb.Plugs.Metrics do
  @moduledoc """
  Protects the `/metrics` endpoint with bearer token authentication.

  Wraps `PromEx.Plug` and only serves metrics when the request includes
  a valid `Authorization: Bearer <token>` header. When no token is
  configured (dev/test), metrics are served without auth.
  """

  import Plug.Conn

  def init(opts), do: PromEx.Plug.init(opts)

  def call(%{request_path: "/metrics"} = conn, opts) do
    token = Application.get_env(:micelio, __MODULE__)[:bearer_token]

    if token do
      case get_req_header(conn, "authorization") do
        ["Bearer " <> provided] when provided == token ->
          PromEx.Plug.call(conn, opts)

        _ ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(401, "Unauthorized")
          |> halt()
      end
    else
      PromEx.Plug.call(conn, opts)
    end
  end

  def call(conn, _opts), do: conn
end
