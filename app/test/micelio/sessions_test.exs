defmodule Micelio.SessionsTest do
  use Micelio.DataCase

  import ExUnit.CaptureLog

  alias Micelio.Sessions.{OGSummary, Session}
  alias Micelio.{Sessions, Accounts}

  describe "sessions" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{
          handle: "test-org",
          name: "Test Organization"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "test-project",
          name: "Test Project",
          organization_id: organization.id
        })

      %{user: user, organization: organization, repository: repository}
    end

    test "list_sessions_for_repository/1 returns all sessions for a repository", %{
      user: user,
      repository: repository
    } do
      {:ok, session1} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Test goal 1",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, session2} =
        Sessions.create_session(%{
          session_id: "session-2",
          goal: "Test goal 2",
          repository_id: repository.id,
          user_id: user.id
        })

      sessions = Sessions.list_sessions_for_repository(repository)
      assert length(sessions) == 2
      assert Enum.any?(sessions, fn s -> s.id == session1.id end)
      assert Enum.any?(sessions, fn s -> s.id == session2.id end)
    end

    test "list_sessions_for_repository/2 filters by status", %{user: user, repository: repository} do
      {:ok, active_session} =
        Sessions.create_session(%{
          session_id: "active-session",
          goal: "Active",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, landed_session} =
        Sessions.create_session(%{
          session_id: "landed-session",
          goal: "Landed",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} = Sessions.land_session(landed_session)

      active_sessions = Sessions.list_sessions_for_repository(repository, status: "active")
      assert length(active_sessions) == 1
      assert hd(active_sessions).id == active_session.id

      landed_sessions = Sessions.list_sessions_for_repository(repository, status: "landed")
      assert length(landed_sessions) == 1
      assert hd(landed_sessions).status == "landed"
    end

    test "count_sessions_for_repository/1 returns total count", %{
      user: user,
      repository: repository
    } do
      Sessions.create_session(%{
        session_id: "session-1",
        goal: "Test 1",
        repository_id: repository.id,
        user_id: user.id
      })

      Sessions.create_session(%{
        session_id: "session-2",
        goal: "Test 2",
        repository_id: repository.id,
        user_id: user.id
      })

      assert Sessions.count_sessions_for_repository(repository) == 2
    end

    test "count_sessions_for_repository/2 counts by status", %{user: user, repository: repository} do
      {:ok, _} =
        Sessions.create_session(%{
          session_id: "active-1",
          goal: "Active 1",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, landed} =
        Sessions.create_session(%{
          session_id: "landed-1",
          goal: "Landed 1",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _} = Sessions.land_session(landed)

      assert Sessions.count_sessions_for_repository(repository, status: "active") == 1
      assert Sessions.count_sessions_for_repository(repository, status: "landed") == 1
    end

    test "list_sessions_for_repository/2 supports sorting", %{user: user, repository: repository} do
      {:ok, older} =
        Sessions.create_session(%{
          session_id: "older",
          goal: "Older session",
          repository_id: repository.id,
          user_id: user.id,
          started_at:
            DateTime.utc_now()
            |> DateTime.add(-3600, :second)
            |> DateTime.truncate(:second)
        })

      {:ok, newer} =
        Sessions.create_session(%{
          session_id: "newer",
          goal: "Newer session",
          repository_id: repository.id,
          user_id: user.id,
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _} = Sessions.land_session(older)

      sessions_newest = Sessions.list_sessions_for_repository(repository, sort: :newest)
      assert hd(sessions_newest).id == newer.id

      sessions_oldest = Sessions.list_sessions_for_repository(repository, sort: :oldest)
      assert hd(sessions_oldest).id == older.id

      sessions_by_status = Sessions.list_sessions_for_repository(repository, sort: :status)
      assert hd(sessions_by_status).status == "active"
      assert Enum.at(sessions_by_status, 1).status == "landed"
    end

    test "get_session/1 returns the session with given id", %{user: user, repository: repository} do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "test-session",
          goal: "Test goal",
          repository_id: repository.id,
          user_id: user.id
        })

      assert Sessions.get_session(session.id).id == session.id
    end

    test "get_session_by_session_id/1 returns the session with given session_id", %{
      user: user,
      repository: repository
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "unique-session-id",
          goal: "Test goal",
          repository_id: repository.id,
          user_id: user.id
        })

      found = Sessions.get_session_by_session_id("unique-session-id")
      assert found.id == session.id
    end

    test "get_session_with_associations/1 preloads user and project", %{
      user: user,
      repository: repository
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "test-session",
          goal: "Test goal",
          repository_id: repository.id,
          user_id: user.id
        })

      loaded = Sessions.get_session_with_associations(session.id)
      assert loaded.user.id == user.id
      assert loaded.repository.id == repository.id
    end

    test "og_summary_for_sessions/2 accepts session snapshots", %{
      user: user,
      repository: repository
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "summary-session",
          goal: "Summarize changes",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/summary.ex",
          change_type: "added",
          content: "defmodule Summary do\nend\n"
        })

      session_with_changes = Sessions.get_session_with_changes(session.id)
      summary = "Added summary module for agent changes."
      digest = OGSummary.digest(session_with_changes.changes)

      {:ok, _} =
        Sessions.update_session(session_with_changes, %{
          metadata: %{"og_summary" => summary, "og_summary_hash" => digest}
        })

      session_with_changes = Sessions.get_session_with_changes(session.id)
      snapshot = %{session: session_with_changes}

      assert {:ok, ^summary} = Sessions.og_summary_for_sessions([snapshot])
      assert {:ok, ^summary} = Sessions.og_summary_for_sessions([session_with_changes])
    end

    test "create_session/1 with valid data creates a session", %{
      user: user,
      repository: repository
    } do
      attrs = %{
        session_id: "new-session",
        goal: "Build feature",
        repository_id: repository.id,
        user_id: user.id
      }

      assert {:ok, %Session{} = session} = Sessions.create_session(attrs)
      assert session.session_id == "new-session"
      assert session.goal == "Build feature"
      assert session.status == "active"
      assert session.started_at != nil
    end

    test "create_session/1 with conversation and decisions", %{user: user, repository: repository} do
      attrs = %{
        session_id: "session-with-data",
        goal: "Test",
        repository_id: repository.id,
        user_id: user.id,
        conversation: [
          %{"role" => "user", "content" => "Hello"},
          %{"role" => "assistant", "content" => "Hi there"}
        ],
        decisions: [
          %{"decision" => "Use Elixir", "reasoning" => "Best for real-time"}
        ]
      }

      assert {:ok, session} = Sessions.create_session(attrs)
      assert length(session.conversation) == 2
      assert length(session.decisions) == 1
    end

    test "create_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Sessions.create_session(%{})
    end

    test "create_session/1 enforces unique session_id", %{user: user, repository: repository} do
      attrs = %{
        session_id: "duplicate-id",
        goal: "Test",
        repository_id: repository.id,
        user_id: user.id
      }

      {:ok, _} = Sessions.create_session(attrs)
      assert {:error, %Ecto.Changeset{}} = Sessions.create_session(attrs)
    end

    test "land_session/1 marks session as landed", %{user: user, repository: repository} do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-land",
          goal: "Test",
          repository_id: repository.id,
          user_id: user.id
        })

      assert session.status == "active"
      assert session.landed_at == nil

      {:ok, landed} = Sessions.land_session(session)
      assert landed.status == "landed"
      assert landed.landed_at != nil
    end

    test "abandon_session/1 marks session as abandoned", %{user: user, repository: repository} do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-abandon",
          goal: "Test",
          repository_id: repository.id,
          user_id: user.id
        })

      assert session.status == "active"

      {:ok, abandoned} = Sessions.abandon_session(session)
      assert abandoned.status == "abandoned"
      assert abandoned.landed_at != nil
    end

    test "update_session/2 with valid data updates the session", %{
      user: user,
      repository: repository
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-update",
          goal: "Original goal",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, updated} = Sessions.update_session(session, %{goal: "Updated goal"})
      assert updated.goal == "Updated goal"
    end

    test "delete_session/1 deletes the session", %{user: user, repository: repository} do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-delete",
          goal: "Test",
          repository_id: repository.id,
          user_id: user.id
        })

      assert {:ok, %Session{}} = Sessions.delete_session(session)
      assert Sessions.get_session(session.id) == nil
    end
  end

  describe "session schema validations" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("test-validation@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{
          handle: "test-org-validation",
          name: "Test Organization"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "test-project-validation",
          name: "Test Project",
          organization_id: organization.id
        })

      %{user: user, repository: repository}
    end

    test "validates status is one of active, landed, abandoned", %{
      user: user,
      repository: repository
    } do
      attrs = %{
        session_id: "test",
        goal: "Test",
        repository_id: repository.id,
        user_id: user.id,
        status: "invalid"
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "is invalid" in errors_on(changeset).status
    end

    test "requires session_id", %{user: user, repository: repository} do
      attrs = %{
        goal: "Test",
        repository_id: repository.id,
        user_id: user.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).session_id
    end

    test "requires goal", %{user: user, repository: repository} do
      attrs = %{
        session_id: "test",
        repository_id: repository.id,
        user_id: user.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).goal
    end

    test "requires repository_id", %{user: user} do
      attrs = %{
        session_id: "test",
        goal: "Test",
        user_id: user.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).repository_id
    end

    test "requires user_id", %{repository: repository} do
      attrs = %{
        session_id: "test",
        goal: "Test",
        repository_id: repository.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).user_id
    end
  end

  describe "session changes" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("test-changes@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{
          handle: "test-org-changes",
          name: "Test Organization"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "test-project-changes",
          name: "Test Project",
          organization_id: organization.id
        })

      {:ok, session} =
        Sessions.create_session(%{
          session_id: "test-session-changes",
          goal: "Test changes",
          repository_id: repository.id,
          user_id: user.id
        })

      %{user: user, repository: repository, session: session}
    end

    test "create_session_change/1 creates a file addition", %{session: session} do
      attrs = %{
        session_id: session.id,
        file_path: "src/main.ex",
        change_type: "added",
        content: "defmodule Main do\nend"
      }

      assert {:ok, change} = Sessions.create_session_change(attrs)
      assert change.file_path == "src/main.ex"
      assert change.change_type == "added"
      assert change.content == "defmodule Main do\nend"
    end

    test "create_session_change/1 creates a file modification", %{session: session} do
      attrs = %{
        session_id: session.id,
        file_path: "src/app.ex",
        change_type: "modified",
        content: "# Updated content"
      }

      assert {:ok, change} = Sessions.create_session_change(attrs)
      assert change.change_type == "modified"
    end

    test "create_session_change/1 creates a file deletion", %{session: session} do
      attrs = %{
        session_id: session.id,
        file_path: "src/old.ex",
        change_type: "deleted"
      }

      assert {:ok, change} = Sessions.create_session_change(attrs)
      assert change.change_type == "deleted"
      assert change.content == nil
    end

    test "create_session_change/1 with storage_key instead of content", %{session: session} do
      attrs = %{
        session_id: session.id,
        file_path: "src/large.ex",
        change_type: "added",
        storage_key: "sessions/test/changes/src/large.ex"
      }

      assert {:ok, change} = Sessions.create_session_change(attrs)
      assert change.storage_key == "sessions/test/changes/src/large.ex"
      assert change.content == nil
    end

    test "create_session_change/1 requires content or storage_key for non-deleted files", %{
      session: session
    } do
      attrs = %{
        session_id: session.id,
        file_path: "src/test.ex",
        change_type: "added"
      }

      {result, _log} = with_log(fn -> Sessions.create_session_change(attrs) end)
      assert {:error, changeset} = result

      assert "must provide either content or storage_key for non-deleted files" in errors_on(
               changeset
             ).content
    end

    test "create_session_change/1 validates change_type", %{session: session} do
      attrs = %{
        session_id: session.id,
        file_path: "src/test.ex",
        change_type: "invalid",
        content: "test"
      }

      assert {:error, changeset} = Sessions.create_session_change(attrs)
      assert "is invalid" in errors_on(changeset).change_type
    end

    test "create_session_changes/1 creates multiple changes in transaction", %{session: session} do
      changes = [
        %{
          session_id: session.id,
          file_path: "src/file1.ex",
          change_type: "added",
          content: "content1"
        },
        %{
          session_id: session.id,
          file_path: "src/file2.ex",
          change_type: "modified",
          content: "content2"
        },
        %{
          session_id: session.id,
          file_path: "src/file3.ex",
          change_type: "deleted"
        }
      ]

      assert {:ok, created} = Sessions.create_session_changes(changes)
      assert length(created) == 3
    end

    test "create_session_changes/1 rolls back on error", %{session: session} do
      changes = [
        %{
          session_id: session.id,
          file_path: "src/file1.ex",
          change_type: "added",
          content: "content1"
        },
        %{
          session_id: session.id,
          file_path: "src/file2.ex",
          # This will cause an error
          change_type: "invalid",
          content: "content2"
        }
      ]

      {result, _log} = with_log(fn -> Sessions.create_session_changes(changes) end)
      assert {:error, _} = result

      # Verify no changes were created
      assert Sessions.list_session_changes(session) == []
    end

    test "list_session_changes/1 returns all changes for a session", %{session: session} do
      {:ok, _} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "src/a.ex",
          change_type: "added",
          content: "test"
        })

      {:ok, _} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "src/b.ex",
          change_type: "modified",
          content: "test"
        })

      changes = Sessions.list_session_changes(session)
      assert length(changes) == 2
      # Verify ordered by file_path
      assert Enum.at(changes, 0).file_path == "src/a.ex"
      assert Enum.at(changes, 1).file_path == "src/b.ex"
    end

    test "count_session_changes/1 returns total count", %{session: session} do
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/a.ex",
        change_type: "added",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/b.ex",
        change_type: "modified",
        content: "test"
      })

      assert Sessions.count_session_changes(session) == 2
    end

    test "count_session_changes/2 counts by change type", %{session: session} do
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/a.ex",
        change_type: "added",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/b.ex",
        change_type: "added",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/c.ex",
        change_type: "modified",
        content: "test"
      })

      assert Sessions.count_session_changes(session, change_type: "added") == 2
      assert Sessions.count_session_changes(session, change_type: "modified") == 1
      assert Sessions.count_session_changes(session, change_type: "deleted") == 0
    end

    test "get_session_change_stats/1 returns statistics", %{session: session} do
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/a.ex",
        change_type: "added",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/b.ex",
        change_type: "added",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/c.ex",
        change_type: "modified",
        content: "test"
      })

      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "src/d.ex",
        change_type: "deleted"
      })

      stats = Sessions.get_session_change_stats(session)
      assert stats.total == 4
      assert stats.added == 2
      assert stats.modified == 1
      assert stats.deleted == 1
    end

    test "get_session_with_changes/1 preloads changes", %{session: session} do
      {:ok, _} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "src/test.ex",
          change_type: "added",
          content: "test"
        })

      loaded = Sessions.get_session_with_changes(session.id)
      assert loaded != nil
      assert length(loaded.changes) == 1
      assert hd(loaded.changes).file_path == "src/test.ex"
    end

    test "changes are deleted when session is deleted", %{session: session} do
      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "src/test.ex",
          change_type: "added",
          content: "test"
        })

      Sessions.delete_session(session)

      # Changes should be deleted due to on_delete: :delete_all
      assert Sessions.list_session_changes(session) == []
    end
  end
end
