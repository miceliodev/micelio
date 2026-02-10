defmodule Micelio.Sessions.EventCaptureTest do
  use Micelio.DataCase

  alias Micelio.Sessions.EventCapture
  alias Micelio.Storage
  alias Micelio.StorageHelper
  alias Micelio.{Accounts, Projects, Sessions}

  setup :setup_storage

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("agent@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-org",
        name: "Agent Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-project",
        name: "Agent Project",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-capture-1",
        goal: "Capture events",
        repository_id: repository.id,
        user_id: user.id
      })

    %{session: session}
  end

  test "capture_event stores normalized event", %{
    session: session,
    storage_config: storage_config
  } do
    event = %{
      type: "status",
      timestamp: ~U[2024-01-01 00:00:00Z],
      source: %{kind: "agent"},
      payload: %{state: "running", message: "Booting"}
    }

    assert {:ok, %{event: stored_event, storage_key: key}} =
             EventCapture.capture_event(session, event, storage_config: storage_config)

    assert String.starts_with?(key, "sessions/#{session.session_id}/events/")
    assert stored_event.type == "status"
    assert stored_event.payload.state == "running"

    {:ok, json} = Storage.get(key, storage_config: storage_config)
    decoded = Jason.decode!(json)

    assert decoded["type"] == "status"
    assert decoded["payload"]["state"] == "running"
    assert decoded["source"]["kind"] == "agent"
    assert is_binary(decoded["id"])
  end

  test "capture_output wraps ansi output with stderr stream", %{
    session: session,
    storage_config: storage_config
  } do
    output = "\e[31mboom\e[0m"

    assert {:ok, %{event: stored_event, storage_key: key}} =
             EventCapture.capture_output(session, output,
               stream: "stderr",
               storage_config: storage_config
             )

    assert stored_event.payload.stream == "stderr"
    assert stored_event.payload.format == "ansi"

    {:ok, json} = Storage.get(key, storage_config: storage_config)
    decoded = Jason.decode!(json)

    assert decoded["payload"]["stream"] == "stderr"
    assert decoded["payload"]["format"] == "ansi"
  end

  test "capture_event returns error for invalid payload", %{
    session: session,
    storage_config: storage_config
  } do
    assert {:error, :invalid_event_type} =
             EventCapture.capture_event(session, %{}, storage_config: storage_config)
  end

  test "capture_payload stores json event payloads", %{
    session: session,
    storage_config: storage_config
  } do
    event = %{
      type: "status",
      timestamp: ~U[2024-02-01 12:00:00Z],
      source: %{kind: "agent"},
      payload: %{state: "running", message: "Preparing"}
    }

    payload = Jason.encode!(event)

    assert {:ok, %{event: stored_event, storage_key: key}} =
             EventCapture.capture_payload(session, payload, storage_config: storage_config)

    assert stored_event.type == "status"

    {:ok, json} = Storage.get(key, storage_config: storage_config)
    decoded = Jason.decode!(json)

    assert decoded["payload"]["message"] == "Preparing"
  end

  test "capture_payload wraps plain output", %{session: session, storage_config: storage_config} do
    assert {:ok, %{event: stored_event}} =
             EventCapture.capture_payload(session, "hello world",
               stream: "stdout",
               storage_config: storage_config
             )

    assert stored_event.type == "output"
    assert stored_event.payload.text == "hello world"
  end

  test "capture_payload falls back to output for invalid json events", %{
    session: session,
    storage_config: storage_config
  } do
    payload = Jason.encode!(%{type: "unknown", payload: %{text: "hi"}})

    assert {:ok, %{event: stored_event}} =
             EventCapture.capture_payload(session, payload,
               stream: "stderr",
               storage_config: storage_config
             )

    assert stored_event.type == "output"
    assert stored_event.payload.text == payload
    assert stored_event.payload.stream == "stderr"
  end

  test "sessions wrapper captures plain output payload", %{
    session: session,
    storage_config: storage_config
  } do
    assert {:ok, %{event: stored_event}} =
             Sessions.capture_session_payload(session, "wrapper output",
               stream: "stderr",
               storage_config: storage_config
             )

    assert stored_event.type == "output"
    assert stored_event.payload.stream == "stderr"
  end

  test "sessions wrapper captures event using session id", %{
    session: session,
    storage_config: storage_config
  } do
    event = %{
      type: "status",
      timestamp: ~U[2024-03-01 00:00:00Z],
      source: %{kind: "agent"},
      payload: %{state: "running", message: "Wrapper"}
    }

    assert {:ok, %{event: stored_event}} =
             Sessions.capture_session_event(session.session_id, event,
               storage_config: storage_config
             )

    assert stored_event.type == "status"
  end

  defp setup_storage(context) do
    StorageHelper.setup_isolated_storage(context)
  end
end
