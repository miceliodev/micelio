defmodule Micelio.NotificationsTest do
  use Micelio.DataCase, async: true

  import Swoosh.TestAssertions

  alias Micelio.Accounts
  alias Micelio.Notifications
  alias Micelio.Repositories
  alias Micelio.Sessions

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  test "dispatch_session_landed/3 sends session landed emails to organization members" do
    handle = unique_handle("notify")
    {:ok, owner} = Accounts.get_or_create_user_by_email("owner-#{handle}@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("member-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{handle: "org-#{handle}", name: "Acme"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "member"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        name: "Acme Docs",
        handle: "docs-#{handle}",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-#{handle}",
        goal: "Ship docs",
        repository_id: repository.id,
        user_id: owner.id
      })

    {:ok, landed_session} = Sessions.land_session(session, %{})

    :ok = Notifications.dispatch_session_landed(repository, landed_session, async: false)

    assert_emails_sent([
      %{to: "member-#{handle}@example.com", subject: ~r/\[org-#{handle}\/docs-#{handle}\]/},
      %{to: "owner-#{handle}@example.com", subject: ~r/\[org-#{handle}\/docs-#{handle}\]/}
    ])
  end
end
