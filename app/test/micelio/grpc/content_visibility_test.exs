defmodule Micelio.GRPC.ContentVisibilityTest do
  use Micelio.DataCase, async: true

  alias GRPC.Server.Stream
  alias Micelio.Accounts
  alias Micelio.GRPC.Content.V1.ContentService.Server, as: ContentServer
  alias Micelio.GRPC.Content.V1.GetHeadTreeRequest

  test "public project content is accessible without authentication" do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{handle: "public-org-#{unique}", name: "Public Org"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "public-project-#{unique}",
        name: "Public Project",
        organization_id: organization.id,
        visibility: "public"
      })

    response =
      ContentServer.get_head_tree(
        %GetHeadTreeRequest{
          user_id: "",
          account_handle: organization.account.handle,
          repository_handle: repository.handle
        },
        empty_stream()
      )

    assert %Micelio.GRPC.Content.V1.GetTreeResponse{} = response
  end

  test "private project content requires authentication" do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{handle: "private-org-#{unique}", name: "Private Org"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "private-project-#{unique}",
        name: "Private Project",
        organization_id: organization.id,
        visibility: "private"
      })

    response =
      ContentServer.get_head_tree(
        %GetHeadTreeRequest{
          user_id: "",
          account_handle: organization.account.handle,
          repository_handle: repository.handle
        },
        empty_stream()
      )

    assert {:error, %GRPC.RPCError{}} = response
  end

  defp empty_stream do
    %Stream{http_request_headers: %{}}
  end
end
