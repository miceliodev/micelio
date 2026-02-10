defmodule MicelioWeb.RequireAdminPlugTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias MicelioWeb.RequireAdminPlug

  test "allows admin users", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    conn =
      conn
      |> Plug.Conn.assign(:current_user, admin)
      |> RequireAdminPlug.call(RequireAdminPlug.init([]))

    refute conn.halted
  end

  test "redirects non-admin users", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("user@example.com")

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> Plug.Conn.assign(:current_user, user)
      |> RequireAdminPlug.call(RequireAdminPlug.init([]))

    assert conn.halted
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You do not have access to that page."
  end

  test "redirects when no current user", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> RequireAdminPlug.call(RequireAdminPlug.init([]))

    assert conn.halted
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You do not have access to that page."
  end
end
