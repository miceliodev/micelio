defmodule Micelio.GRPC.SessionsWorkflowTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use Micelio.DataCase, async: false

  import Mimic

  alias Micelio.Accounts

  alias Micelio.GRPC.Sessions.V1.{
    ConversationMessage,
    Decision,
    FileChange,
    GetSessionRequest,
    LandSessionRequest,
    ListSessionsRequest,
    SessionResponse,
    SessionService,
    StartSessionRequest
  }

  alias Micelio.Mic.Landing
  alias Micelio.Notifications
  alias Micelio.Sessions
  alias Micelio.Webhooks

  setup :verify_on_exit!
  setup :set_mimic_global

  test "session gRPC workflow covers start, list, get, and land" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-workflow-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-workflow-org-#{unique}",
        name: "gRPC Workflow Org #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "grpc-workflow-project-#{unique}",
        name: "gRPC Workflow Project #{unique}",
        organization_id: organization.id
      })

    session_id = "grpc-workflow-session-#{unique}"

    start_response =
      SessionService.Server.start_session(
        %StartSessionRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          repository_handle: repository.handle,
          session_id: session_id,
          goal: "Exercise the gRPC session workflow",
          conversation: [
            %ConversationMessage{role: "user", content: "Start the workflow"}
          ],
          decisions: [
            %Decision{decision: "Proceed", reasoning: "Ensure gRPC flow works"}
          ]
        },
        nil
      )

    assert %SessionResponse{} = start_response
    assert start_response.session.session_id == session_id
    assert start_response.session.status == "active"
    assert start_response.session.conversation_count == 1
    assert start_response.session.decisions_count == 1

    list_response =
      SessionService.Server.list_sessions(
        %ListSessionsRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          repository_handle: repository.handle,
          status: "active"
        },
        nil
      )

    assert [listed_session] = list_response.sessions
    assert listed_session.session_id == session_id
    assert listed_session.status == "active"

    get_response =
      SessionService.Server.get_session(
        %GetSessionRequest{
          user_id: user.id,
          session_id: session_id
        },
        nil
      )

    assert get_response.session.session_id == session_id

    landing_time = DateTime.utc_now() |> DateTime.truncate(:second)

    expect(Landing, :land_session, fn %Sessions.Session{} = landed_session ->
      assert landed_session.session_id == session_id
      {:ok, %{position: 44, landed_at: landing_time}}
    end)

    expect(Webhooks, :dispatch_session_landed, fn dispatched_repository,
                                                  dispatched_session,
                                                  position ->
      assert dispatched_repository.id == repository.id
      assert dispatched_session.session_id == session_id
      assert position == 44
      :ok
    end)

    expect(Notifications, :dispatch_session_landed, fn dispatched_repository,
                                                       dispatched_session ->
      assert dispatched_repository.id == repository.id
      assert dispatched_session.session_id == session_id
      :ok
    end)

    land_response =
      SessionService.Server.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session_id,
          conversation: [
            %ConversationMessage{role: "assistant", content: "Landing session"}
          ],
          decisions: [
            %Decision{decision: "Land", reasoning: "Finalize changes"}
          ],
          files: [
            %FileChange{path: "lib/workflow.ex", content: "ok\n", change_type: "added"}
          ]
        },
        nil
      )

    assert %SessionResponse{} = land_response
    assert land_response.session.status == "landed"
    assert land_response.session.landing_position == 44
    assert land_response.session.conversation_count == 1
    assert land_response.session.decisions_count == 1

    session = Sessions.get_session_by_session_id(session_id)
    assert session.status == "landed"

    assert [
             %{file_path: "lib/workflow.ex", change_type: "added"} = change
           ] = Sessions.list_session_changes(session)

    assert change.content == "ok\n"
  end
end
