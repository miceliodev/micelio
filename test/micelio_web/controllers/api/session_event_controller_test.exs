defmodule MicelioWeb.Api.SessionEventControllerTest do
  use MicelioWeb.ConnCase

  alias Micelio.StorageHelper
  alias Micelio.{Accounts, Projects, Sessions}

  setup :setup_storage
  setup :assign_storage_config

  setup %{storage_config: storage_config} do
    {:ok, user} = Accounts.get_or_create_user_by_email("sse@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "sse-org",
        name: "SSE Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(
        %{
          handle: "sse-project",
          name: "SSE Project",
          visibility: "public",
          organization_id: organization.id
        },
        user: user
      )

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "sse-session-1",
        goal: "Stream SSE",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "status",
          payload: %{state: "running"}
        },
        storage_config: storage_config
      )

    %{session: session}
  end

  test "streams a snapshot of session events when follow is false", %{
    conn: conn,
    session: session
  } do
    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?follow=false")

    assert conn.status == 200
    assert ["text/event-stream; charset=utf-8"] = get_resp_header(conn, "content-type")
    assert String.contains?(conn.resp_body, "retry: 1000")
    assert String.contains?(conn.resp_body, "event: session_event")
    assert String.contains?(conn.resp_body, ~s("type":"status"))
    assert String.contains?(conn.resp_body, "id: sessions/#{session.session_id}/events/")
  end

  test "filters events by type and since cursor", %{conn: conn, session: session} do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -3, :second)
    t2 = DateTime.add(now, -2, :second)
    t3 = DateTime.add(now, -1, :second)

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "first", stream: "stdout", format: "text"}
        },
        timestamp: t1,
        storage_config: conn.assigns.storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "second", stream: "stdout", format: "text"}
        },
        timestamp: t2,
        storage_config: conn.assigns.storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "error",
          payload: %{message: "boom"}
        },
        timestamp: t3,
        storage_config: conn.assigns.storage_config
      )

    since = DateTime.to_unix(t1, :millisecond)

    conn =
      get(
        conn,
        "/api/sessions/#{session.session_id}/events/stream?follow=false&types=output&since=#{since}"
      )

    assert conn.status == 200
    assert String.contains?(conn.resp_body, ~s("type":"output"))
    assert String.contains?(conn.resp_body, ~s("text":"second"))
    refute String.contains?(conn.resp_body, ~s("text":"first"))
    refute String.contains?(conn.resp_body, ~s("type":"error"))
  end

  test "accepts ISO8601 since cursor for snapshot filtering", %{conn: conn, session: session} do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -2, :second)
    t2 = DateTime.add(now, -1, :second)

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "first", stream: "stdout", format: "text"}
        },
        timestamp: t1,
        storage_config: conn.assigns.storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "second", stream: "stdout", format: "text"}
        },
        timestamp: t2,
        storage_config: conn.assigns.storage_config
      )

    since = DateTime.to_iso8601(t1)

    conn =
      get(
        conn,
        "/api/sessions/#{session.session_id}/events/stream?follow=false&types=output&since=#{since}"
      )

    assert conn.status == 200
    assert String.contains?(conn.resp_body, ~s("text":"second"))
    refute String.contains?(conn.resp_body, ~s("text":"first"))
  end

  test "respects last-event-id for snapshot pagination", %{conn: conn, session: session} do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -2, :second)
    t2 = DateTime.add(now, -1, :second)

    {:ok, first} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "first", stream: "stdout", format: "text"}
        },
        timestamp: t1,
        storage_config: conn.assigns.storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "second", stream: "stdout", format: "text"}
        },
        timestamp: t2,
        storage_config: conn.assigns.storage_config
      )

    conn =
      conn
      |> put_req_header("last-event-id", first.storage_key)
      |> get("/api/sessions/#{session.session_id}/events/stream?follow=false")

    assert conn.status == 200
    refute String.contains?(conn.resp_body, ~s("text":"first"))
    assert String.contains?(conn.resp_body, ~s("text":"second"))
  end

  test "returns bad request for invalid event types", %{conn: conn, session: session} do
    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?types=bogus")

    assert conn.status == 400
    assert %{"error" => "Invalid event types"} = json_response(conn, 400)
  end

  test "accepts type parameter alias for filtering", %{conn: conn, session: session} do
    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "aliased", stream: "stdout", format: "text"}
        },
        storage_config: conn.assigns.storage_config
      )

    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?follow=false&type=output")

    assert conn.status == 200
    assert String.contains?(conn.resp_body, ~s("text":"aliased"))
    refute String.contains?(conn.resp_body, ~s("type":"status"))
  end

  test "returns bad request for invalid since cursor", %{conn: conn, session: session} do
    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?since=nope")

    assert conn.status == 400
    assert %{"error" => "Invalid since cursor"} = json_response(conn, 400)
  end

  test "returns bad request for negative since cursor", %{conn: conn, session: session} do
    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?since=-5")

    assert conn.status == 400
    assert %{"error" => "Invalid since cursor"} = json_response(conn, 400)
  end

  test "limits snapshot results when limit is provided", %{conn: conn, session: session} do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -2, :second)
    t2 = DateTime.add(now, -1, :second)

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "first", stream: "stdout", format: "text"}
        },
        timestamp: t1,
        storage_config: conn.assigns.storage_config
      )

    {:ok, _} =
      Sessions.capture_session_event(
        session,
        %{
          type: "output",
          payload: %{text: "second", stream: "stdout", format: "text"}
        },
        timestamp: t2,
        storage_config: conn.assigns.storage_config
      )

    conn =
      get(
        conn,
        "/api/sessions/#{session.session_id}/events/stream?follow=false&types=output&limit=1"
      )

    assert conn.status == 200
    assert String.contains?(conn.resp_body, ~s("text":"first"))
    refute String.contains?(conn.resp_body, ~s("text":"second"))
  end

  test "returns bad request for invalid limit", %{conn: conn, session: session} do
    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?limit=oops")

    assert conn.status == 400
    assert %{"error" => "Invalid limit"} = json_response(conn, 400)
  end

  test "returns forbidden for private session without access", %{conn: conn} do
    {:ok, owner} = Accounts.get_or_create_user_by_email("private-owner@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "private-org",
        name: "Private Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(
        %{
          handle: "private-project",
          name: "Private Project",
          visibility: "private",
          organization_id: organization.id
        },
        user: owner
      )

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "private-session-1",
        goal: "Private stream",
        repository_id: repository.id,
        user_id: owner.id
      })

    conn = get(conn, "/api/sessions/#{session.session_id}/events/stream?follow=false")

    assert conn.status == 403
    assert %{"error" => "Access denied"} = json_response(conn, 403)
  end

  test "returns not found when session identifier is unknown", %{conn: conn} do
    conn = get(conn, "/api/sessions/missing-session/events/stream?follow=false")

    assert conn.status == 404
    assert %{"error" => "Session not found"} = json_response(conn, 404)
  end

  defp setup_storage(context) do
    StorageHelper.setup_isolated_storage(context)
  end

  defp assign_storage_config(%{conn: conn, storage_config: storage_config}) do
    {:ok, conn: assign(conn, :storage_config, storage_config)}
  end
end
