defmodule MicelioWeb.Api.V1.SessionControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Repositories
  alias Micelio.Sessions

  setup do
    unique = Ecto.UUID.generate() |> String.slice(0, 8)
    {:ok, user} = Accounts.get_or_create_user_by_email("session-api-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "sat-#{unique}",
        name: "Session API Org"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "sr-#{unique}",
        name: "Session Repository",
        organization_id: organization.id
      })

    token = create_access_token(user)
    org_handle = organization.account.handle

    %{
      user: user,
      token: token,
      organization: organization,
      repository: repository,
      org_handle: org_handle
    }
  end

  describe "GET /api/orgs/:org/repositories/:repo/sessions" do
    test "returns 403 without token", %{
      conn: conn,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/sessions")

      body = json_response(conn, 403)
      assert body["error"] == "insufficient_scope"
    end

    test "lists sessions for repository", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository,
      user: user
    } do
      {:ok, _session} =
        Sessions.create_session(%{
          "goal" => "Test session",
          "repository_id" => repository.id,
          "user_id" => user.id,
          "session_id" => Ecto.UUID.generate(),
          "status" => "active"
        })

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/sessions")

      body = json_response(conn, 200)
      assert is_list(body["data"])
      assert length(body["data"]) >= 1
    end
  end

  describe "POST /api/orgs/:org/repositories/:repo/sessions" do
    test "starts a new session", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          ~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/sessions",
          %{goal: "Add new feature"}
        )

      body = json_response(conn, 201)
      assert body["data"]["goal"] == "Add new feature"
      assert body["data"]["status"] == "active"
      assert body["data"]["session_id"]
    end
  end

  describe "GET /api/sessions/:session_id" do
    test "returns session by session_id", %{
      conn: conn,
      token: token,
      repository: repository,
      user: user
    } do
      session_id = Ecto.UUID.generate()

      {:ok, _session} =
        Sessions.create_session(%{
          "goal" => "Test get session",
          "repository_id" => repository.id,
          "user_id" => user.id,
          "session_id" => session_id,
          "status" => "active"
        })

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/sessions/#{session_id}")

      body = json_response(conn, 200)
      assert body["data"]["session_id"] == session_id
      assert body["data"]["goal"] == "Test get session"
    end

    test "returns 404 for unknown session", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/sessions/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/sessions/:session_id/land" do
    test "lands an active session", %{
      conn: conn,
      token: token,
      repository: repository,
      user: user
    } do
      session_id = Ecto.UUID.generate()

      {:ok, _session} =
        Sessions.create_session(%{
          "goal" => "Session to land",
          "repository_id" => repository.id,
          "user_id" => user.id,
          "session_id" => session_id,
          "status" => "active"
        })

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/sessions/#{session_id}/land")

      body = json_response(conn, 200)
      assert body["data"]["status"] == "landed"
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
