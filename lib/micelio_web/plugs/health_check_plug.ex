defmodule MicelioWeb.HealthCheckPlug do
  @moduledoc """
  A plug that handles health check requests for Kamal deployments.

  This plug intercepts requests to `/up` and returns a 200 response immediately,
  bypassing all other plugs including SSL redirects. This is necessary because
  Kamal's health checks hit containers directly over HTTP.
  """
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["up"]} = conn, _opts) do
    conn
    |> put_resp_content_type("application/html")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
