defmodule Micelio.GRPC.VirtualContentServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.GRPC.Hif.V1.ContentService.Server, as: ContentServer
  alias Micelio.Mic.{Binary, Project, Tree}
  alias Micelio.Repositories
  alias Micelio.Storage

  test "get_tree and get_path resolve content at a revision hash" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("virtual-content-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "virtual-content-org-#{unique}",
        name: "Virtual Content Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "virtual-content-repo-#{unique}",
        name: "Virtual Content Repo #{unique}",
        organization_id: organization.id
      })

    content = "hello from virtual content\n"
    blob_hash = :crypto.hash(:sha256, content)
    {:ok, _} = Storage.put(Project.blob_key(repository.id, blob_hash), content)

    tree = %{"README.md" => blob_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository.id, tree_hash), encoded_tree)

    head = Binary.new_head(1, tree_hash)
    {:ok, _} = Storage.put(Project.head_key(repository.id), Binary.encode_head(head))

    tree_response =
      ContentServer.get_tree(
        %V1.GetTreeRequest{
          user_id: user.id,
          repository: %V1.RepositoryRef{
            organization_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          revision_hash: tree_hash
        },
        nil
      )

    assert %V1.TreeResponse{} = tree_response
    assert tree_response.tree_hash == tree_hash
    assert Enum.any?(tree_response.entries, &(&1.path == "README.md"))

    path_response =
      ContentServer.get_path(
        %V1.GetPathRequest{
          user_id: user.id,
          repository: %V1.RepositoryRef{
            organization_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          revision_hash: tree_hash,
          path: "README.md"
        },
        nil
      )

    assert %V1.PathResponse{} = path_response
    assert path_response.content == content
    assert path_response.content_hash == blob_hash
    assert path_response.size == byte_size(content)
  end
end
