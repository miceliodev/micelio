defmodule MicelioWeb.Api.TokenPoolControllerTest do
  use MicelioWeb.ConnCase, async: false

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Repositories

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("token-pool-api@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{handle: "token-org", name: "Token Org"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "token-project",
        name: "Token Project",
        organization_id: organization.id
      })

    {:ok, pool} = AITokens.create_token_pool(repository, %{balance: 1200, reserved: 200})
    token = create_access_token(user)

    %{user: user, token: token, repository: repository, pool: pool, organization: organization}
  end

  test "shows token pool for authorized user", %{
    conn: conn,
    token: token,
    project: repository,
    pool: pool,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool")

    body = json_response(conn, 200)
    assert body["data"]["id"] == pool.id
    assert body["data"]["balance"] == 1200
    assert body["data"]["reserved"] == 200
  end

  test "updates token pool", %{
    conn: conn,
    token: token,
    project: repository,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> patch(
        ~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool",
        %{
          token_pool: %{balance: 800, reserved: 100}
        }
      )

    body = json_response(conn, 200)
    assert body["data"]["balance"] == 800
    assert body["data"]["reserved"] == 100
  end

  test "rejects invalid token pool updates", %{
    conn: conn,
    token: token,
    project: repository,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> patch(
        ~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool",
        %{
          token_pool: %{balance: 100, reserved: 200}
        }
      )

    body = json_response(conn, 422)
    assert "cannot exceed balance" in body["error"]["reserved"]
  end

  test "rejects missing token pool payload", %{
    conn: conn,
    token: token,
    project: repository,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> patch(
        ~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool",
        %{}
      )

    body = json_response(conn, 400)
    assert body["error"] == "token_pool payload is required"
  end

  test "requires authentication", %{
    conn: conn,
    repository: repository,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool")

    body = json_response(conn, 401)
    assert body["error"] == "Authentication required"
  end

  test "forbids non-admin access", %{
    conn: conn,
    repository: repository,
    organization: organization
  } do
    {:ok, other_user} = Accounts.get_or_create_user_by_email("token-pool-guest@example.com")
    other_token = create_access_token(other_user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> get(~p"/api/repositories/#{organization.account.handle}/#{repository.handle}/token-pool")

    body = json_response(conn, 403)
    assert body["error"] == "Not authorized to view token pool"
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
end
