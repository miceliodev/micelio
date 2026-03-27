defmodule MicelioWeb.RequireAdminPlug do
  @moduledoc """
  Plug that requires the current user to be an instance admin.
  """
  use MicelioWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Micelio.Accounts.User
  alias Micelio.Admin

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %User{} = user ->
        if Admin.admin_user?(user) do
          conn
        else
          conn
          |> put_flash(:error, "You do not have access to that page.")
          |> redirect(to: ~p"/")
          |> halt()
        end

      _ ->
        conn
        |> put_flash(:error, "You do not have access to that page.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end
end
