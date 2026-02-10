defmodule Micelio.IntegrationTest do
  @moduledoc """
  End-to-end integration test that exercises the complete workflow:
  1. User authenticates
  2. Creates a repository
  3. Starts a session
  4. Adds notes to session
  5. Lands the session
  6. Browses sessions
  7. Views session details
  """

  use Micelio.DataCase, async: false

  alias Micelio.{Accounts, Projects, Sessions}

  test "complete workflow from user creation to session browsing" do
    # Step 1: Create user (simulating authentication)
    {:ok, user} = Accounts.get_or_create_user_by_email("integration@example.com")
    assert user.email == "integration@example.com"

    # Step 2: Create organization for user
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "integration-org",
        name: "Integration Organization"
      })

    assert organization.account.handle == "integration-org"

    # Step 3: Create a repository via "API"
    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "integration-project",
        name: "Integration Project",
        description: "A project for testing",
        organization_id: organization.id
      })

    assert repository.handle == "integration-project"

    # Step 4: Start a session via "API"
    {:ok, session} =
      Sessions.create_session(%{
        session_id: "integration-session-001",
        goal: "Test integration workflow",
        repository_id: repository.id,
        user_id: user.id,
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        conversation: [
          %{"role" => "user", "content" => "I want to test the integration"},
          %{"role" => "assistant", "content" => "Let me help you with that"}
        ],
        decisions: [],
        metadata: %{
          test: "integration"
        }
      })

    assert session.status == "active"
    assert session.goal == "Test integration workflow"
    assert length(session.conversation) == 2

    # Step 5: Add notes to session (update)
    {:ok, updated_session} =
      Sessions.update_session(session, %{
        conversation:
          session.conversation ++
            [
              %{"role" => "user", "content" => "Thanks for your help!"}
            ],
        decisions: [
          %{"decision" => "Integration successful", "reasoning" => "All steps completed"}
        ]
      })

    assert length(updated_session.conversation) == 3
    assert length(updated_session.decisions) == 1

    # Step 6: Land the session
    {:ok, landed_session} = Sessions.land_session(updated_session)
    assert landed_session.status == "landed"
    assert landed_session.landed_at != nil

    # Step 7: Browse sessions (list all for project)
    all_sessions = Sessions.list_sessions_for_repository(repository)
    assert length(all_sessions) == 1
    assert hd(all_sessions).id == landed_session.id

    # Step 8: Filter sessions by status
    landed_sessions = Sessions.list_sessions_for_repository(repository, status: "landed")
    assert length(landed_sessions) == 1

    active_sessions = Sessions.list_sessions_for_repository(repository, status: "active")
    assert Enum.empty?(active_sessions)

    # Step 9: View session details with associations
    detailed_session = Sessions.get_session_with_associations(landed_session.id)
    assert detailed_session.user.id == user.id
    assert detailed_session.repository.id == repository.id
    assert detailed_session.goal == "Test integration workflow"
    assert length(detailed_session.conversation) == 3
    assert length(detailed_session.decisions) == 1

    # Step 10: Count sessions
    total_count = Sessions.count_sessions_for_repository(repository)
    assert total_count == 1

    landed_count = Sessions.count_sessions_for_repository(repository, status: "landed")
    assert landed_count == 1

    # Success! All steps completed
    :ok
  end

  test "session lifecycle: create -> abandon -> delete" do
    # Setup
    {:ok, user} = Accounts.get_or_create_user_by_email("lifecycle@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "lifecycle-org",
        name: "Lifecycle Organization"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "lifecycle-project",
        name: "Lifecycle Project",
        organization_id: organization.id
      })

    # Create session
    {:ok, session} =
      Sessions.create_session(%{
        session_id: "lifecycle-session",
        goal: "Test lifecycle",
        repository_id: repository.id,
        user_id: user.id
      })

    assert session.status == "active"

    # Abandon session
    {:ok, abandoned} = Sessions.abandon_session(session)
    assert abandoned.status == "abandoned"
    assert abandoned.landed_at != nil

    # Delete session
    {:ok, _deleted} = Sessions.delete_session(abandoned)
    assert Sessions.get_session(session.id) == nil

    # Verify it's gone
    sessions = Sessions.list_sessions_for_repository(repository)
    assert Enum.empty?(sessions)
  end

  test "multiple sessions with different statuses" do
    # Setup
    {:ok, user} = Accounts.get_or_create_user_by_email("multi@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "multi-org",
        name: "Multi Organization"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "multi-project",
        name: "Multi Project",
        organization_id: organization.id
      })

    # Create 3 active sessions
    Enum.each(1..3, fn i ->
      Sessions.create_session(%{
        session_id: "active-#{i}",
        goal: "Active session #{i}",
        repository_id: repository.id,
        user_id: user.id
      })
    end)

    # Create 2 landed sessions
    Enum.each(1..2, fn i ->
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "landed-#{i}",
          goal: "Landed session #{i}",
          repository_id: repository.id,
          user_id: user.id
        })

      Sessions.land_session(session)
    end)

    # Create 1 abandoned session
    {:ok, abandoned} =
      Sessions.create_session(%{
        session_id: "abandoned-1",
        goal: "Abandoned session",
        repository_id: repository.id,
        user_id: user.id
      })

    Sessions.abandon_session(abandoned)

    # Verify counts
    assert Sessions.count_sessions_for_repository(repository) == 6
    assert Sessions.count_sessions_for_repository(repository, status: "active") == 3
    assert Sessions.count_sessions_for_repository(repository, status: "landed") == 2
    assert Sessions.count_sessions_for_repository(repository, status: "abandoned") == 1

    # Verify filtering
    active_sessions = Sessions.list_sessions_for_repository(repository, status: "active")
    assert length(active_sessions) == 3
    assert Enum.all?(active_sessions, fn s -> s.status == "active" end)

    landed_sessions = Sessions.list_sessions_for_repository(repository, status: "landed")
    assert length(landed_sessions) == 2
    assert Enum.all?(landed_sessions, fn s -> s.status == "landed" end)

    abandoned_sessions = Sessions.list_sessions_for_repository(repository, status: "abandoned")
    assert length(abandoned_sessions) == 1
    assert hd(abandoned_sessions).status == "abandoned"
  end
end
