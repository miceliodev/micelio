defmodule MicelioWeb.Browser.DeviceAuthControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts

  setup :register_and_log_in_user

  test "stores user_code in session and reuses it", %{conn: conn} do
    conn = get(conn, "/device/auth", %{user_code: "ABCD-1234"})
    assert get_session(conn, :device_user_code) == "ABCD-1234"

    conn = get(conn, "/device/auth")
    assert html_response(conn, 200) =~ "ABCD-1234"
  end

  test "redirects to device auth after login when device code present", %{conn: conn} do
    conn = Plug.Test.init_test_session(conn, device_user_code: "ABCD-1234")
    {:ok, token} = Accounts.initiate_login("device-auth@example.com")

    conn = get(conn, "/auth/verify/#{token.token}")
    assert redirected_to(conn) == "/device/auth"
  end
end
