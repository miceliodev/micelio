defmodule MicelioWeb.Browser.TotpControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Repo

  test "starts TOTP setup", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("totp-start@example.com")

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/account/totp/start")

    assert redirected_to(conn) == ~p"/account"
    assert is_binary(get_session(conn, :totp_setup_secret))
  end

  test "verifies TOTP setup and enables 2FA", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("totp-verify@example.com")

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/account/totp/start")

    secret = conn |> get_session(:totp_setup_secret) |> Base.decode64!()
    code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

    conn = post(conn, ~p"/account/totp/verify", %{code: code})

    assert redirected_to(conn) == ~p"/account"
    assert Accounts.get_user(user.id).totp_enabled_at
  end

  test "disables TOTP with valid code", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("totp-disable@example.com")
    secret = Accounts.generate_totp_secret()
    code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

    {:ok, user} = Accounts.enable_totp(user, secret, code)
    {:ok, user} = Repo.update(Ecto.Changeset.change(user, totp_last_used_at: nil))

    disable_code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/account/totp/disable", %{code: disable_code})

    assert redirected_to(conn) == ~p"/account"

    user = Accounts.get_user(user.id)
    assert user.totp_secret == nil
    assert user.totp_enabled_at == nil
  end

  test "completes login with TOTP", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("totp-login@example.com")
    secret = Accounts.generate_totp_secret()
    code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

    {:ok, user} = Accounts.enable_totp(user, secret, code)
    {:ok, user} = Repo.update(Ecto.Changeset.change(user, totp_last_used_at: nil))

    login_code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

    conn =
      conn
      |> init_test_session(%{totp_pending_user_id: user.id, totp_pending_redirect: "/"})
      |> post(~p"/auth/totp", %{code: login_code})

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_id) == user.id
  end
end
