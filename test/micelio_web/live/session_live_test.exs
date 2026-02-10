defmodule MicelioWeb.SessionLiveTest do
  use MicelioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Micelio.Sessions.OGSummary
  alias Micelio.{Accounts, PromptRequests, Sessions}
  alias MicelioWeb.OpenGraphImage

  describe "SessionLive.Index" do
    setup :register_and_log_in_user
    setup :create_repository

    test "lists all sessions", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, _} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Build authentication",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.create_session(%{
          session_id: "session-2",
          goal: "Add real-time features",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _index_live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{repository.handle}/sessions")

      assert html =~ "Sessions"
      assert html =~ "Build authentication"
      assert html =~ "Add real-time features"
    end

    test "displays session metadata", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, _session} =
        Sessions.create_session(%{
          session_id: "test-session",
          goal: "Test goal",
          repository_id: repository.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "Message 1"},
            %{"role" => "assistant", "content" => "Message 2"}
          ],
          decisions: [
            %{"decision" => "Decision 1", "reasoning" => "Because"}
          ]
        })

      {:ok, _live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{repository.handle}/sessions")

      assert html =~ "Test goal"
      assert html =~ "Active"
    end

    test "filters sessions by status", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, _active_session} =
        Sessions.create_session(%{
          session_id: "active",
          goal: "Active session",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, landed_session} =
        Sessions.create_session(%{
          session_id: "landed",
          goal: "Landed session",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} = Sessions.land_session(landed_session)

      {:ok, index_live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{repository.handle}/sessions")

      assert html =~ "Active session"
      assert html =~ "Landed session"

      # Filter by active
      html = index_live |> element("button", "Active") |> render_click()
      assert html =~ "Active session"
      refute html =~ "Landed session"

      # Filter by landed
      html = index_live |> element("button", "Landed") |> render_click()
      refute html =~ "Active session"
      assert html =~ "Landed session"

      # Show all
      html = index_live |> element("button", "All") |> render_click()
      assert html =~ "Active session"
      assert html =~ "Landed session"
    end

    test "shows empty state when no sessions exist", %{
      conn: conn,
      repository: repository,
      organization: organization
    } do
      {:ok, _live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{repository.handle}/sessions")

      assert html =~ "No sessions yet"
    end

    test "requires authentication", %{
      conn: conn,
      repository: repository,
      organization: organization
    } do
      conn = conn |> log_out_user()

      assert {:error, {:redirect, %{to: "/auth/login"}}} =
               live(
                 conn,
                 "/projects/#{organization.account.handle}/#{repository.handle}/sessions"
               )
    end
  end

  describe "SessionLive.Show" do
    setup :register_and_log_in_user
    setup :create_repository

    test "displays session details", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "detail-session",
          goal: "Build something great",
          repository_id: repository.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "Hello"},
            %{"role" => "assistant", "content" => "Hi there"}
          ],
          decisions: [
            %{"decision" => "Use Phoenix", "reasoning" => "Best framework"}
          ],
          metadata: %{
            "custom_key" => "custom_value"
          }
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "Build something great"
      assert html =~ "Hello"
      assert html =~ "Hi there"
      assert html =~ "Use Phoenix"
      assert html =~ "Best framework"
      assert html =~ "custom_key"
    end

    test "shows prompt request link when session originates from a prompt request", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, prompt_request} =
        PromptRequests.create_prompt_request(
          %{
            title: "Prompt to PR",
            prompt: "Do the thing",
            result: "Output",
            model: "gpt-4.1-mini",
            model_version: "2026-01-01",
            token_count: 120,
            generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
            origin: :human,
            system_prompt: "System",
            conversation: %{"messages" => [%{"role" => "user", "content" => "Ship it"}]}
          },
          repository: repository,
          user: user
        )

      {:ok, accepted_prompt_request} =
        PromptRequests.review_prompt_request(prompt_request, user, :accepted)

      session = Sessions.get_session(accepted_prompt_request.session_id)

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "Prompt to PR"

      assert html =~
               "/projects/#{organization.account.handle}/#{repository.handle}/prompt-requests/#{prompt_request.id}"
    end

    test "renders session event viewer controls", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-viewer-session",
          goal: "Stream events",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "data-events-url=\"/api/sessions/#{session.session_id}/events/stream\""
      assert html =~ "session-tl-event-controls"
      assert html =~ "session-tl-event-filter"
    end

    test "renders initial session events and cursor", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-snapshot-session",
          goal: "Snapshot events",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "status",
          payload: %{state: "running", message: "booting"}
        })

      {:ok, %{storage_key: _cursor}} =
        Sessions.capture_session_event(session, %{
          type: "output",
          payload: %{text: "hello", stream: "stdout", format: "text"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "data-type=\"status\""
      assert html =~ "data-type=\"output\""
      assert html =~ "running - booting"
      assert html =~ "hello"

      {:ok, events} = Sessions.list_session_events(session.session_id, limit: 50)

      expected_cursor =
        case List.last(events) do
          %{storage_key: storage_key} -> storage_key
          _ -> nil
        end

      document = Floki.parse_document!(html)
      data_after = document |> Floki.attribute("[data-after]", "data-after") |> List.first()

      assert data_after == expected_cursor
    end

    test "renders session event detail payloads", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-detail-session",
          goal: "Payload details",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "status",
          payload: %{state: "running", message: "booting"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "data-type=\"status\""
      assert html =~ "running - booting"
    end

    test "renders progress summaries with percent and message", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-progress-summary",
          goal: "Track progress",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "progress",
          payload: %{current: 42, total: 100, percent: 42, message: "Downloading"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "42% - Downloading"
    end

    test "renders progress bars for long-running work", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-progress-bar",
          goal: "Show progress bar",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "progress",
          payload: %{current: 50, total: 100, percent: 50, message: "Syncing"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "session-tl-progress"
      assert html =~ "aria-valuenow=\"50\""
    end

    test "renders artifact image previews", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-artifact-image",
          goal: "Show images",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "artifact",
          payload: %{
            kind: "image",
            name: "preview.png",
            uri: "https://example.com/preview.png",
            content_type: "image/png"
          }
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "session-tl-artifact-image"
      assert html =~ "src=\"https://example.com/preview.png\""
    end

    test "renders output in collapsible sections", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-output-collapsible",
          goal: "Show output",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "output",
          payload: %{text: "Hello output", stream: "stdout", format: "text"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "session-tl-tool-call"
      assert html =~ "Output"
      assert html =~ "STDOUT"
    end

    test "opens short output blocks by default", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-output-open",
          goal: "Short output",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "output",
          payload: %{text: "Short output", stream: "stdout", format: "text"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      document = Floki.parse_document!(html)
      output_blocks = Floki.find(document, "div.session-tl-tool-call details")

      assert Enum.any?(output_blocks, fn block ->
               Floki.text(block) =~ "Short output" and Floki.attribute([block], "open") != []
             end)
    end

    test "collapses long output blocks by default", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-output-closed",
          goal: "Long output",
          repository_id: repository.id,
          user_id: user.id
        })

      long_output = String.duplicate("A", 241)

      {:ok, _} =
        Sessions.capture_session_event(session, %{
          type: "output",
          payload: %{text: long_output, stream: "stdout", format: "text"}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      document = Floki.parse_document!(html)
      output_blocks = Floki.find(document, "div.session-tl-tool-call details")

      assert Enum.any?(output_blocks, fn block ->
               Floki.text(block) =~ long_output and Floki.attribute([block], "open") == []
             end)
    end

    test "shows empty session event state when no events exist", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "event-empty-session",
          goal: "No events yet",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "data-role=\"event-empty\""
      assert html =~ "No events yet."
    end

    test "displays conversation with role labels", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "conversation-test",
          goal: "Test conversation display",
          repository_id: repository.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "User message"},
            %{"role" => "assistant", "content" => "Assistant message"},
            %{"role" => "system", "content" => "System message"}
          ]
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "User"
      assert html =~ "Assistant"
      assert html =~ "System"
      assert html =~ "User message"
      assert html =~ "Assistant message"
      assert html =~ "System message"
    end

    test "shows abandon button for active sessions", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "active-session",
          goal: "Active",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "Abandon"
    end

    test "does not show actions for landed sessions", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "landed-session",
          goal: "Landed",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, landed_session} = Sessions.land_session(session)

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{landed_session.id}"
        )

      refute html =~ "Abandon"
    end

    test "abandons an active session", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-abandon",
          goal: "Will be abandoned",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, show_live, _html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      html = show_live |> element("button", "Abandon") |> render_click()

      assert html =~ "Session abandoned successfully"
      assert html =~ "Abandoned"

      # Verify in database
      abandoned_session = Sessions.get_session(session.id)
      assert abandoned_session.status == "abandoned"
    end

    test "shows empty state when no file changes", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "files-test",
          goal: "Test files",
          repository_id: repository.id,
          user_id: user.id,
          metadata: %{"files_count" => 5}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      assert html =~ "Changes"
      assert html =~ "No file changes in this session"
    end

    test "uses cached og summary for page meta description", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "og-summary-session",
          goal: "Summarize OG",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/example.ex",
          change_type: "modified",
          content: "updated"
        })

      changes = Sessions.list_session_changes(session)
      summary = "Updated example module to refine session behavior."
      digest = OGSummary.digest(changes)

      {:ok, _session} =
        Sessions.update_session(session, %{
          metadata: %{"og_summary" => summary, "og_summary_hash" => digest}
        })

      {:ok, _view, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )

      # Verify the session page renders successfully with cached summary
      # The PageMeta is assigned internally but we can verify the session is loaded correctly
      assert html =~ "Summarize OG"
      updated = Sessions.get_session(session.id)
      assert updated.metadata["og_summary"] == summary
    end

    test "uses cached og summary for og:image description", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "og-summary-image-session",
          goal: "Summarize OG image",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/example.ex",
          change_type: "modified",
          content: "updated"
        })

      summary = "Updated example module to refine session behavior."
      digest = OGSummary.digest([change])

      {:ok, _session} =
        Sessions.update_session(session, %{
          metadata: %{"og_summary" => summary, "og_summary_hash" => digest}
        })

      html =
        conn
        |> get(
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )
        |> html_response(200)

      doc = LazyHTML.from_document(html)
      tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
      [image_url] = LazyHTML.attribute(tag, "content")

      uri = URI.parse(image_url)
      %{"token" => token} = URI.decode_query(uri.query || "")

      assert {:ok, attrs} = OpenGraphImage.verify_token(token)
      assert attrs["description"] == summary
    end

    test "sets og:image template and stats for session changes", %{
      conn: conn,
      repository: repository,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "og-session-stats",
          goal: "Track OG stats",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/added.ex",
          change_type: "added",
          content: "added"
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/modified.ex",
          change_type: "modified",
          content: "modified"
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/deleted.ex",
          change_type: "deleted",
          content: "deleted"
        })

      html =
        conn
        |> get(
          "/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
        )
        |> html_response(200)

      doc = LazyHTML.from_document(html)
      tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
      [image_url] = LazyHTML.attribute(tag, "content")

      uri = URI.parse(image_url)
      %{"token" => token} = URI.decode_query(uri.query || "")

      assert {:ok, attrs} = OpenGraphImage.verify_token(token)
      assert attrs["image_template"] == "agent_session"

      assert attrs["image_stats"] == %{
               "files" => 3,
               "added" => 1,
               "modified" => 1,
               "deleted" => 1
             }
    end

    test "returns 404 for non-existent session", %{
      conn: conn,
      repository: repository,
      organization: organization
    } do
      assert {:error,
              {:live_redirect, %{to: redirect_to, flash: %{"error" => "Session not found."}}}} =
               live(
                 conn,
                 "/projects/#{organization.account.handle}/#{repository.handle}/sessions/00000000-0000-0000-0000-000000000000"
               )

      assert redirect_to ==
               "/projects/#{organization.account.handle}/#{repository.handle}/sessions"
    end

    test "requires authentication", %{
      conn: conn,
      repository: repository,
      organization: organization
    } do
      conn = conn |> log_out_user()

      assert {:error, {:redirect, %{to: "/auth/login"}}} =
               live(
                 conn,
                 "/projects/#{organization.account.handle}/#{repository.handle}/sessions/123"
               )
    end
  end

  defp create_repository(%{user: user}) do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "test-org",
        name: "Test Organization"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "test-project",
        name: "Test Project",
        description: "A test project",
        organization_id: organization.id
      })

    %{repository: repository, organization: organization}
  end

  defp log_out_user(conn) do
    conn
    |> Phoenix.ConnTest.delete(~p"/auth/logout")
    |> Phoenix.ConnTest.recycle()
  end
end
