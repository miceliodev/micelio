defmodule Micelio.ActivityTest do
  use Micelio.DataCase, async: true

  alias Micelio.{Accounts, Activity, Plans, Projects, Repo, Sessions}

  test "list_user_activity_public returns ordered public items" do
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

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "public-session",
        goal: "Public work",
        repository_id: public_repository.id,
        user_id: user.id
      })

    {:ok, landed_session} = Sessions.land_session(session)

    {:ok, private_session} =
      Sessions.create_session(%{
        session_id: "private-session",
        goal: "Private work",
        repository_id: private_repository.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(private_session)

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Transparency check",
          prompt: "Add transparency badges",
          result: "Diff output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 980,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Go"}]}
        },
        project: public_repository,
        user: user
      )

    {:ok, star} = Repositories.star_repository(user, public_repository)
    {:ok, _} = Repositories.star_repository(user, private_repository)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    project_created_at = DateTime.add(now, -3600, :second)
    session_landed_at = DateTime.add(now, -7200, :second)
    plan_at = DateTime.add(now, -5400, :second)
    star_at = DateTime.add(now, -10_800, :second)

    update_timestamp(public_repository, %{inserted_at: project_created_at})
    update_session_timestamp(landed_session, %{landed_at: session_landed_at})
    update_timestamp(plan, %{inserted_at: plan_at})
    update_timestamp(star, %{inserted_at: star_at})

    activity =
      Activity.list_user_activity_public(user, [organization.id],
        limit: 10,
        before: DateTime.add(now, 3600, :second)
      )

    assert Enum.map(activity.items, & &1.type) ==
             [
               :repository_created,
               :plan_submitted,
               :session_landed,
               :repository_starred
             ]

    assert Enum.all?(activity.items, fn item -> item.repository.visibility == "public" end)
    assert activity.has_more? == false

    limited =
      Activity.list_user_activity_public(user, [organization.id],
        limit: 1,
        before: DateTime.add(now, 3600, :second)
      )

    assert length(limited.items) == 1
    assert limited.has_more? == true
  end

  defp update_timestamp(struct, attrs) do
    struct
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  defp update_session_timestamp(session, attrs) do
    session
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end
end
