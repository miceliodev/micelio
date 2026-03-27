defmodule MicelioWeb.Browser.AuthControllerTest do
  use MicelioWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias Micelio.Accounts.OAuthIdentity
  alias Micelio.Repo

  test "redirects to GitHub with state", %{conn: conn} do
    conn = get(conn, ~p"/auth/github")

    assert redirected_to(conn, 302) =~ "https://github.com/login/oauth/authorize?"
    assert is_binary(get_session(conn, :github_oauth_state))
  end

  test "redirects to GitLab with state", %{conn: conn} do
    conn = get(conn, ~p"/auth/gitlab")

    assert redirected_to(conn, 302) =~ "https://gitlab.com/oauth/authorize?"
    assert is_binary(get_session(conn, :gitlab_oauth_state))
  end

  test "github callback signs in user and stores identity", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{github_oauth_state: "state-token"})
      |> get(~p"/auth/github/callback?code=valid-code&state=state-token")

    user_id = get_session(conn, :user_id)
    assert is_binary(user_id)

    identity =
      Repo.get_by(OAuthIdentity,
        provider: "github",
        provider_user_id: "4242"
      )

    assert identity.user_id == user_id
  end

  test "gitlab callback signs in user and stores identity", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{gitlab_oauth_state: "state-token"})
      |> get(~p"/auth/gitlab/callback?code=valid-code&state=state-token")

    user_id = get_session(conn, :user_id)
    assert is_binary(user_id)

    identity =
      Repo.get_by(OAuthIdentity,
        provider: "gitlab",
        provider_user_id: "7331"
      )

    assert identity.user_id == user_id
  end

  test "github callback rejects mismatched state", %{conn: conn} do
    capture_log(fn ->
      conn =
        conn
        |> init_test_session(%{github_oauth_state: "state-token"})
        |> get(~p"/auth/github/callback?code=valid-code&state=bad")

      assert get_session(conn, :user_id) == nil
      assert redirected_to(conn) == ~p"/auth/login"
    end)
  end

  test "gitlab callback rejects mismatched state", %{conn: conn} do
    capture_log(fn ->
      conn =
        conn
        |> init_test_session(%{gitlab_oauth_state: "state-token"})
        |> get(~p"/auth/gitlab/callback?code=valid-code&state=bad")

      assert get_session(conn, :user_id) == nil
      assert redirected_to(conn) == ~p"/auth/login"
    end)
  end

  test "github callback handles oauth error responses", %{conn: conn} do
    capture_log(fn ->
      conn = get(conn, ~p"/auth/github/callback?error=access_denied")

      assert get_session(conn, :user_id) == nil
      assert redirected_to(conn) == ~p"/auth/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "GitHub login failed. Reason: oauth error: access_denied"
    end)
  end

  test "gitlab callback handles oauth error responses", %{conn: conn} do
    capture_log(fn ->
      conn = get(conn, ~p"/auth/gitlab/callback?error=access_denied")

      assert get_session(conn, :user_id) == nil
      assert redirected_to(conn) == ~p"/auth/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "GitLab login failed. Reason: oauth error: access_denied"
    end)
  end
end
