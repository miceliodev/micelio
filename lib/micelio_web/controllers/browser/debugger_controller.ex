defmodule MicelioWeb.Browser.DebuggerController do
  use MicelioWeb, :controller

  def method_not_allowed(conn, _params) do
    conn
    |> put_status(:method_not_allowed)
    |> put_resp_header("allow", "POST")
    |> send_resp(:method_not_allowed, "")
  end
end
