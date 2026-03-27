defmodule MicelioWeb.RequireAuthPlug do
  @moduledoc """
  Plug that requires a user to be authenticated.
  Redirects to login if not authenticated.
  """
  use MicelioWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: ~p"/auth/login")
      |> halt()
    end
  end
end
