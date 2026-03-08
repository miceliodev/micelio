defmodule Micelio.GRPC.VirtualSearchServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.GRPC.Hif.V1.SearchService.Server, as: SearchServer
  alias Micelio.Mic.{Binary, Project, SearchIndex, Tree}
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Storage

  test "query_text returns indexed matches and stale-index errors when head advances" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("virtual-search-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "virtual-search-org-#{unique}",
        name: "Virtual Search Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "virtual-search-repo-#{unique}",
        name: "Virtual Search Repo #{unique}",
        organization_id: organization.id
      })

    file_content = "TODO: index this line\n"
    blob_hash = :crypto.hash(:sha256, file_content)
    {:ok, _} = Storage.put(Project.blob_key(repository.id, blob_hash), file_content)

    tree = %{"src/main.txt" => blob_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository.id, tree_hash), encoded_tree)

    {:ok, _} =
      Storage.put(
        Project.head_key(repository.id),
        Binary.encode_head(Binary.new_head(1, tree_hash))
      )

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "virtual-search-session-#{unique}",
        goal: "Index search content",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/main.txt",
        change_type: "added",
        content: file_content
      })

    assert :ok = SearchIndex.index_session_changes(repository.id, 1, session, [change])

    request = %V1.TextQueryRequest{
      user_id: user.id,
      repository: %V1.RepositoryRef{
        organization_handle: organization.account.handle,
        repository_handle: repository.handle
      },
      query: "TODO",
      limit: 20
    }

    response = SearchServer.query_text(request, nil)
    assert %V1.TextQueryResponse{} = response
    assert response.total == 1
    assert length(response.matches) == 1
    assert hd(response.matches).path == "src/main.txt"

    # Advance HEAD without indexing the new position to trigger stale index handling.
    {:ok, _} =
      Storage.put(
        Project.head_key(repository.id),
        Binary.encode_head(Binary.new_head(2, tree_hash))
      )

    stale = SearchServer.query_text(request, nil)
    assert {:error, %GRPC.RPCError{message: message}} = stale
    assert message =~ "stale"
  end
end
