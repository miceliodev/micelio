defmodule MicelioWeb.Api.V1.OrganizationControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients

  setup do
    unique = Ecto.UUID.generate() |> String.slice(0, 8)
    {:ok, user} = Accounts.get_or_create_user_by_email("org-api-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "oat-#{unique}",
        name: "Org API Test"
      })

    token = create_access_token(user)

    %{user: user, token: token, organization: organization}
  end

  describe "GET /api/orgs" do
    test "returns 403 without token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/orgs")

      body = json_response(conn, 403)
      assert body["error"] == "insufficient_scope"
    end

    test "lists organizations for authenticated user", %{
      conn: conn,
      token: token,
      organization: organization
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs")

      body = json_response(conn, 200)
      assert is_list(body["data"])
      assert length(body["data"]) >= 1

      org = Enum.find(body["data"], &(&1["handle"] == organization.account.handle))
      assert org
      assert org["name"] == "Org API Test"
    end
  end

  describe "GET /api/orgs/:handle" do
    test "returns 403 without token", %{conn: conn, organization: org} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/orgs/#{org.account.handle}")

      body = json_response(conn, 403)
      assert body["error"] == "insufficient_scope"
    end

    test "returns organization by handle", %{conn: conn, token: token, organization: org} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/#{org.account.handle}")

      body = json_response(conn, 200)
      assert body["data"]["handle"] == org.account.handle
      assert body["data"]["name"] == "Org API Test"
    end

    test "returns 404 for unknown handle", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/nonexistent-org")

      assert json_response(conn, 404)
    end
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
