defmodule Micelio.Mic.SearchIndexTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Mic.{Binary, Project, SearchIndex, Tree}
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Storage

  test "query returns only the latest indexed file snapshot" do
    %{user: user, repository: repository} = create_repository_fixture()

    first_content = "TODO: alpha line\n"
    first_hash = write_revision(repository.id, 1, %{"src/main.txt" => first_content})
    first_session = create_session_fixture(user, repository, "Index first revision")

    {:ok, first_change} =
      Sessions.create_session_change(%{
        session_id: first_session.id,
        file_path: "src/main.txt",
        change_type: "added",
        content: first_content
      })

    assert :ok =
             SearchIndex.index_session_changes(
               repository.id,
               first_hash,
               System.system_time(:millisecond),
               first_session,
               [first_change]
             )

    assert {:ok, %{total: 1, matches: [match], next_offset: nil}} =
             SearchIndex.query(repository.id, %{query: "TODO", limit: 20})

    assert match.path == "src/main.txt"
    assert match.snippet =~ "TODO: alpha line"

    second_content = "DONE: beta line\n"
    second_hash = write_revision(repository.id, 2, %{"src/main.txt" => second_content})
    second_session = create_session_fixture(user, repository, "Index second revision")

    {:ok, second_change} =
      Sessions.create_session_change(%{
        session_id: second_session.id,
        file_path: "src/main.txt",
        change_type: "modified",
        content: second_content
      })

    assert :ok =
             SearchIndex.index_session_changes(
               repository.id,
               second_hash,
               System.system_time(:millisecond),
               second_session,
               [second_change]
             )

    assert {:ok, %{total: 0, matches: [], next_offset: nil}} =
             SearchIndex.query(repository.id, %{query: "TODO", limit: 20})

    assert {:ok, %{total: 1, matches: [updated_match], next_offset: nil}} =
             SearchIndex.query(repository.id, %{query: "DONE", limit: 20, path_prefix: "src/"})

    assert updated_match.path == "src/main.txt"
    assert updated_match.snippet =~ "DONE: beta line"
  end

  test "query scans repository content when regex has no indexable tokens" do
    %{user: user, repository: repository} = create_repository_fixture()

    content = "DONE: beta line\n"
    revision_hash = write_revision(repository.id, 1, %{"src/main.txt" => content})
    session = create_session_fixture(user, repository, "Index regex fallback revision")

    {:ok, change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/main.txt",
        change_type: "added",
        content: content
      })

    assert :ok =
             SearchIndex.index_session_changes(
               repository.id,
               revision_hash,
               System.system_time(:millisecond),
               session,
               [change]
             )

    assert {:ok, %{total: 1, matches: [match], next_offset: nil}} =
             SearchIndex.query(repository.id, %{
               query: "^[A-Z]{4}: [a-z]{4} [a-z]{4}$",
               regex: true,
               limit: 20
             })

    assert match.path == "src/main.txt"
    assert match.snippet =~ "DONE: beta line"
  end

  defp create_repository_fixture do
    unique = System.unique_integer([:positive])
    {:ok, user} = Accounts.get_or_create_user_by_email("search-index-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "search-index-org-#{unique}",
        name: "Search Index Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "search-index-repo-#{unique}",
        name: "Search Index Repo #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    %{user: user, organization: organization, repository: repository}
  end

  defp create_session_fixture(user, repository, goal) do
    {:ok, session} =
      Sessions.create_session(%{
        session_id: "search-index-session-#{System.unique_integer([:positive])}",
        goal: goal,
        repository_id: repository.id,
        user_id: user.id
      })

    session
  end

  defp write_revision(repository_id, position, files) do
    tree =
      Enum.reduce(files, %{}, fn {path, content}, acc ->
        blob_hash = :crypto.hash(:sha256, content)
        {:ok, _} = Storage.put(Project.blob_key(repository_id, blob_hash), content)
        Map.put(acc, path, blob_hash)
      end)

    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository_id, tree_hash), encoded_tree)

    {:ok, _} =
      Storage.put(
        Project.head_key(repository_id),
        Binary.encode_head(Binary.new_head(position, tree_hash))
      )

    tree_hash
  end
end
