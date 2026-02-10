defmodule Micelio.Sessions.EventStreamTest do
  use Micelio.DataCase

  alias Micelio.StorageHelper
  alias Micelio.{Accounts, Projects, Sessions}

  setup :setup_storage

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("streamer@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "stream-org",
        name: "Stream Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(
        %{
          handle: "stream-project",
          name: "Stream Project",
          organization_id: organization.id
        },
        user: user
      )

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "stream-session-1",
        goal: "Stream events",
        repository_id: repository.id,
        user_id: user.id
      })

    %{session: session}
  end

  test "list_session_events filters by type and cursor", %{
    session: session,
    storage_config: storage_config
  } do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -3, :second)
    t2 = DateTime.add(now, -2, :second)
    t3 = DateTime.add(now, -1, :second)

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "status",
          payload: %{state: "running"}
        },
        timestamp: t1,
        storage_config: storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "first", stream: "stdout", format: "text"}
        },
        timestamp: t2,
        storage_config: storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "second", stream: "stdout", format: "text"}
        },
        timestamp: t3,
        storage_config: storage_config
      )

    assert {:ok, events} =
             Sessions.list_session_events(session.session_id,
               types: ["output"],
               storage_config: storage_config
             )

    assert Enum.map(events, & &1.event["payload"]["text"]) == ["first", "second"]

    after_key = hd(events).storage_key

    assert {:ok, [later]} =
             Sessions.list_session_events(session.session_id,
               after: after_key,
               storage_config: storage_config
             )

    assert later.event["payload"]["text"] == "second"

    since = DateTime.to_unix(t2, :millisecond)

    assert {:ok, [since_event]} =
             Sessions.list_session_events(session.session_id,
               since: since,
               storage_config: storage_config
             )

    assert since_event.event["payload"]["text"] == "second"
  end

  defp setup_storage(context) do
    StorageHelper.setup_isolated_storage(context)
  end
end
