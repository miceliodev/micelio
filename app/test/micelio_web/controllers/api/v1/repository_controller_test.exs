defmodule MicelioWeb.Api.V1.RepositoryControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Repositories

  setup do
    unique = Ecto.UUID.generate() |> String.slice(0, 8)
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-api-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "rat-#{unique}",
        name: "Repo API Org"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "tr-#{unique}",
        name: "Test Repository",
        organization_id: organization.id
      })

    token = create_access_token(user)
    org_handle = organization.account.handle

    %{
      user: user,
      token: token,
      organization: organization,
      repository: repository,
      org_handle: org_handle,
      unique: unique
    }
  end

  describe "GET /api/orgs/:org/repositories" do
    test "returns 403 without token", %{conn: conn, org_handle: org_handle} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/orgs/#{org_handle}/repositories")

      body = json_response(conn, 403)
      assert body["error"] == "insufficient_scope"
    end

    test "lists repositories for organization", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/#{org_handle}/repositories")

      body = json_response(conn, 200)
      assert is_list(body["data"])
      assert length(body["data"]) >= 1

      repo = Enum.find(body["data"], &(&1["handle"] == repository.handle))
      assert repo
      assert repo["name"] == "Test Repository"
    end
  end

  describe "GET /api/orgs/:org/repositories/:handle" do
    test "returns repository by handle", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}")

      body = json_response(conn, 200)
      assert body["data"]["handle"] == repository.handle
      assert body["data"]["name"] == "Test Repository"
    end

    test "returns 404 for unknown handle", %{conn: conn, token: token, org_handle: org_handle} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/orgs/#{org_handle}/repositories/nonexistent")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/orgs/:org/repositories" do
    test "creates a repository", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      unique: unique
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories", %{
          handle: "new-repo-#{unique}",
          name: "New Repository"
        })

      body = json_response(conn, 201)
      assert body["data"]["handle"] == "new-repo-#{unique}"
      assert body["data"]["name"] == "New Repository"
    end

    test "creates a repository with push and storage configuration", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      unique: unique
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories", %{
          handle: "remote-repo-#{unique}",
          name: "Remote Repository",
          push_protocol: "https",
          push_host: "github.com",
          push_namespace: "org",
          push_repository: "remote",
          storage_backend: "s3",
          storage_key_prefix: "repos/remote"
        })

      body = json_response(conn, 201)
      assert body["data"]["handle"] == "remote-repo-#{unique}"
      assert body["data"]["push_protocol"] == "https"
      assert body["data"]["storage_backend"] == "s3"
    end
  end

  describe "PATCH /api/orgs/:org/repositories/:handle" do
    test "updates a repository", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}", %{
          name: "Updated Name"
        })

      body = json_response(conn, 200)
      assert body["data"]["name"] == "Updated Name"
    end

    test "updates repository push and storage configuration", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}", %{
          push_protocol: "ssh",
          push_host: "example.com",
          push_namespace: "org",
          push_repository: "new-name",
          storage_backend: "local",
          storage_key_prefix: "repos/#{repository.handle}"
        })

      body = json_response(conn, 200)
      assert body["data"]["push_protocol"] == "ssh"
      assert body["data"]["storage_backend"] == "local"
    end
  end

  describe "POST /api/orgs/:org/repositories/:repository/push" do
    test "pushes changes to a repository", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/push", %{
          goal: "Add initial files",
          changes: [
            %{"path" => "README.md", "change_type" => "added", "content" => "# Hello repository"}
          ]
        })

      body = json_response(conn, 200)
      assert body["data"]["session"]["goal"] == "Add initial files"
      assert body["data"]["session"]["status"] == "landed"
      assert body["data"]["landing_position"] == 1
      assert body["data"]["stats"]["added"] == 1
      assert body["data"]["stats"]["modified"] == 0
      assert body["data"]["stats"]["deleted"] == 0
      assert body["data"]["stats"]["total"] == 1
    end

    test "returns validation errors for empty goal", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/push", %{
          goal: "   ",
          changes: [
            %{"path" => "README.md", "change_type" => "added", "content" => "# Empty goal test"}
          ]
        })

      body = json_response(conn, 422)
      assert body["error"] == "validation_error"
    end

    test "returns validation errors for missing path or content", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      base_conn = conn

      conn =
        base_conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/push", %{
          goal: "Fix file",
          changes: [
            %{"path" => "", "change_type" => "modified"}
          ]
        })

      body = json_response(conn, 422)
      assert body["error"] == "validation_error"
      assert body["error_description"] =~ "path must be"

      conn =
        base_conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/push", %{
          goal: "Fix file",
          changes: [
            %{"path" => "README.md", "change_type" => "modified"}
          ]
        })

      body = json_response(conn, 422)
      assert body["error"] == "validation_error"
      assert body["error_description"] =~ "requires content"
    end

    test "returns validation error for invalid change type", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      repository: repository
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/orgs/#{org_handle}/repositories/#{repository.handle}/push", %{
          goal: "Update file",
          changes: [
            %{"path" => "README.md", "change_type" => "rename", "content" => "x"}
          ]
        })

      body = json_response(conn, 422)
      assert body["error"] == "validation_error"
      assert body["error_description"] =~ "change_type must be"
    end
  end

  describe "DELETE /api/orgs/:org/repositories/:handle" do
    test "deletes a repository", %{
      conn: conn,
      token: token,
      org_handle: org_handle,
      organization: organization,
      unique: unique
    } do
      {:ok, to_delete} =
        Repositories.create_repository(%{
          handle: "to-delete-#{unique}",
          name: "To Delete",
          organization_id: organization.id
        })

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/orgs/#{org_handle}/repositories/#{to_delete.handle}")

      assert conn.status == 204
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
