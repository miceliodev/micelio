defmodule Micelio.GRPC.AuthRequiredTest do
  use Micelio.DataCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias GRPC.Server.Stream
  alias Micelio.Accounts
  alias Micelio.GRPC.Content.V1.ContentService.Server, as: ContentServer
  alias Micelio.GRPC.Content.V1.GetHeadTreeRequest
  alias Micelio.GRPC.Repositories.V1.ListProjectsRequest
  alias Micelio.GRPC.Repositories.V1.ProjectService.Server
  alias Micelio.GRPC.Sessions.V1.ListSessionsRequest
  alias Micelio.GRPC.Sessions.V1.SessionService.Server, as: SessionsServer
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Sessions

  test "gRPC requests require bearer token when configured" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-auth-required@example.com")
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-auth-org-#{unique}",
        name: "GRPC Auth Org"
      })

    {:ok, _} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-auth-project-#{unique}",
        name: "GRPC Auth Project",
        organization_id: organization.id
      })

    response =
      Server.list_repositories(
        %ListProjectsRequest{
          user_id: user.id,
          organization_handle: organization.account.handle
        },
        auth_required_stream()
      )

    assert {:error, %GRPC.RPCError{}} = response
  end

  test "content requests accept bearer token when configured" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-auth-content@example.com")
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-auth-content-org-#{unique}",
        name: "GRPC Auth Content Org"
      })

    {:ok, _project} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-auth-content-project-#{unique}",
        name: "GRPC Auth Content Project",
        organization_id: organization.id
      })

    token = create_access_token(user)

    response =
      ContentServer.get_head_tree(
        %GetHeadTreeRequest{
          user_id: user.id,
          account_handle: organization.account.handle,
          repository_handle: "grpc-auth-content-project-#{unique}"
        },
        auth_required_token_stream(token)
      )

    assert %Micelio.GRPC.Content.V1.GetTreeResponse{} = response
  end

  test "session requests accept bearer token when configured" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-auth-sessions@example.com")
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-auth-sessions-org-#{unique}",
        name: "GRPC Auth Sessions Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-auth-sessions-project-#{unique}",
        name: "GRPC Auth Sessions Project",
        organization_id: organization.id
      })

    {:ok, _session} =
      Sessions.create_session(%{
        session_id: "grpc-auth-session-#{unique}",
        goal: "Auth session list",
        repository_id: repository.id,
        user_id: user.id
      })

    token = create_access_token(user)

    response =
      SessionsServer.list_sessions(
        %ListSessionsRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          repository_handle: repository.handle,
          status: "all"
        },
        auth_required_token_stream(token)
      )

    assert %Micelio.GRPC.Sessions.V1.ListSessionsResponse{} = response
  end

  defp auth_required_stream do
    %Stream{http_request_headers: %{"x-micelio-require-auth" => "true"}}
  end

  defp auth_required_token_stream(token) do
    %Stream{
      http_request_headers: %{
        "authorization" => "Bearer #{token}",
        "x-micelio-require-auth" => "true"
      }
    }
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "Test CLI"})
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
