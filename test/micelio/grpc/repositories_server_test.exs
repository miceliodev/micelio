defmodule Micelio.GRPC.RepositoriesServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Repositories.V1.ProjectService.Server

  alias Micelio.GRPC.Repositories.V1.{
    CreateProjectRequest,
    DeleteProjectRequest,
    GetProjectRequest,
    ListProjectsRequest,
    ListProjectsResponse,
    ProjectResponse,
    UpdateProjectRequest
  }

  alias Micelio.Repositories

  test "list_repositories returns projects for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-list@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-org",
        name: "GRPC Org"
      })

    {:ok, _} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-project",
        name: "GRPC Project",
        organization_id: organization.id
      })

    response =
      Server.list_repositories(
        %ListProjectsRequest{
          user_id: user.id,
          organization_handle: organization.account.handle
        },
        nil
      )

    assert %ListProjectsResponse{} = response
    assert length(response.repositories) == 1
  end

  test "list_repositories returns public projects for anonymous user" do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "grpc-public-org-#{unique}",
        name: "GRPC Public Org"
      })

    {:ok, _private_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-private-project-#{unique}",
        name: "GRPC Private Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, public_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-public-project-#{unique}",
        name: "GRPC Public Project",
        organization_id: organization.id,
        visibility: "public"
      })

    response =
      Server.list_repositories(
        %ListProjectsRequest{
          user_id: "",
          organization_handle: organization.account.handle
        },
        nil
      )

    assert %ListProjectsResponse{} = response
    assert Enum.map(response.repositories, & &1.id) == [public_repository.id]
  end

  test "create_repository rejects unauthorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-owner@example.com")
    {:ok, other_user} = Accounts.get_or_create_user_by_email("grpc-guest@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-owner-org",
        name: "GRPC Owner Org"
      })

    response =
      Server.create_repository(
        %CreateProjectRequest{
          user_id: other_user.id,
          organization_handle: organization.account.handle,
          handle: "blocked-project",
          name: "Blocked Project",
          description: ""
        },
        nil
      )

    assert {:error, _} = response
  end

  test "create_repository stores visibility when provided" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-visibility@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-visibility-org",
        name: "GRPC Visibility Org"
      })

    response =
      Server.create_repository(
        %CreateProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: "visible-project",
          name: "Visible Project",
          description: "",
          visibility: "public"
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.repository.visibility == "public"
  end

  test "update_repository returns updated project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-update@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-update-org",
        name: "GRPC Update Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-update-project",
        name: "GRPC Update Project",
        organization_id: organization.id
      })

    response =
      Server.update_repository(
        %UpdateProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: repository.handle,
          new_handle: "grpc-updated",
          name: "Updated",
          description: "Updated",
          visibility: "public"
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.repository.handle == "grpc-updated"
    assert response.repository.visibility == "public"
  end

  test "delete_repository removes project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-delete@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-delete-org",
        name: "GRPC Delete Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-delete-project",
        name: "GRPC Delete Project",
        organization_id: organization.id
      })

    response =
      Server.delete_repository(
        %DeleteProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: repository.handle
        },
        nil
      )

    assert %{success: true} = response
    assert Repositories.get_repository(repository.id) == nil
  end

  test "get_repository returns project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-get@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-get-org",
        name: "GRPC Get Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-get-project",
        name: "GRPC Get Project",
        organization_id: organization.id
      })

    response =
      Server.get_repository(
        %GetProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: repository.handle
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.repository.id == repository.id
  end

  test "get_repository returns public project for anonymous user" do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{handle: "grpc-anon-org-#{unique}", name: "GRPC Anon Org"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-anon-project-#{unique}",
        name: "GRPC Anon Project",
        organization_id: organization.id,
        visibility: "public"
      })

    response =
      Server.get_repository(
        %GetProjectRequest{
          user_id: "",
          organization_handle: organization.account.handle,
          handle: repository.handle
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.repository.id == repository.id
  end
end
