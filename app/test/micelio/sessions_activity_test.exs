defmodule Micelio.SessionsActivityTest do
  use Micelio.DataCase, async: true

  alias Micelio.{Accounts, Sessions}

  test "activity_counts_for_user_public/2 counts landed sessions on public repositories" do
    {:ok, user} = Accounts.get_or_create_user_by_email("activity-user@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "activity-org",
        name: "Activity Org"
      })

    {:ok, public_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "public-project",
        name: "Public Project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, private_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "private-project",
        name: "Private Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, public_session} =
      Sessions.create_session(%{
        session_id: "public-session",
        goal: "Public work",
        repository_id: public_repository.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(public_session)

    {:ok, private_session} =
      Sessions.create_session(%{
        session_id: "private-session",
        goal: "Private work",
        repository_id: private_repository.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(private_session)

    counts = Sessions.activity_counts_for_user_public(user, 1)

    assert Map.get(counts, Date.utc_today()) == 1
    assert Enum.sum(Map.values(counts)) == 1
  end
end
