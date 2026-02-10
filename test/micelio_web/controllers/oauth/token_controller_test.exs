defmodule MicelioWeb.Oauth.TokenControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.OAuth

  test "exchanges refresh token for a new access token", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("mobile-auth@example.com")
    {:ok, client} = OAuth.register_device_client(%{"name" => "Micelio Mobile"})
    {:ok, grant} = OAuth.create_device_grant(client, %{})
    {:ok, _approved} = OAuth.approve_device_grant(grant.user_code, user)
    {:ok, token, _session} = OAuth.exchange_device_code(client.client_id, grant.device_code)

    params = %{
      "grant_type" => "refresh_token",
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "refresh_token" => token.refresh_token
    }

    conn = post(conn, "/oauth/token", params)

    assert %{"access_token" => access_token, "token_type" => token_type} =
             json_response(conn, 200)

    assert is_binary(access_token)
    assert is_binary(token_type)
  end

  test "rejects invalid refresh token", %{conn: conn} do
    {:ok, client} = OAuth.register_device_client(%{"name" => "Micelio Mobile"})

    params = %{
      "grant_type" => "refresh_token",
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "refresh_token" => "invalid"
    }

    conn = post(conn, "/oauth/token", params)

    assert %{"error" => "invalid_grant"} = json_response(conn, 400)
  end
end
