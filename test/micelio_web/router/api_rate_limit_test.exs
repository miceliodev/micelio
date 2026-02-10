defmodule MicelioWeb.Router.ApiRateLimitTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients

  test "api routes apply rate limit headers for unauthenticated requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/oauth/register", %{})

    assert get_resp_header(conn, "x-ratelimit-limit") != []
    assert get_resp_header(conn, "x-ratelimit-remaining") != []
  end

  test "api routes apply rate limit headers for authenticated requests", %{conn: conn} do
    {:ok, user} = Micelio.Accounts.get_or_create_user_by_email(unique_email())
    access_token = create_access_token(user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> post(~p"/oauth/register", %{})

    assert get_resp_header(conn, "x-ratelimit-limit") != []
    assert get_resp_header(conn, "x-ratelimit-remaining") != []
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "mic"})
    client = Clients.get_client(device_client.client_id)

    params = %{
      client: client,
      scope: "",
      sub: to_string(user.id),
      resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
    }

    {:ok, token} = AccessTokens.create(params, refresh_token: true)
    Map.get(token, :value) || Map.get(token, :access_token)
  end

  defp unique_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end
end
