defmodule Micelio.Sessions.ChangeStoreTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Sessions
  alias Micelio.Sessions.ChangeStore

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("changestore@example.com")

    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "change-store-org-#{unique}",
        name: "Change Store Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "change-store-project-#{unique}",
        name: "Change Store Project",
        organization_id: organization.id
      })

    %{user: user, repository: repository}
  end

  test "store_session_changes returns session with change filter and stats", %{
    user: user,
    repository: repository
  } do
    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-change-filter",
        goal: "Test change filter",
        repository_id: repository.id,
        user_id: user.id
      })

    files = [
      %{"path" => "lib/example.ex", "content" => "ok\n", "change_type" => "added"}
    ]

    assert {:ok, updated_session, stats} = ChangeStore.store_session_changes(session, files)
    assert stats == %{total: 1, added: 1, modified: 0, deleted: 0}
    assert %{"change_filter" => filter} = updated_session.metadata
    assert is_map(filter)
    assert Map.has_key?(filter, "bits")
  end
end
