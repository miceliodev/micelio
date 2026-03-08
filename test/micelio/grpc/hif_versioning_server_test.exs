defmodule Micelio.GRPC.VirtualVersioningServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.GRPC.Hif.V1.VersioningService.Server, as: VersioningServer
  alias Micelio.Repositories

  test "open, append conversation, append change, and get session" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("virtual-versioning-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "virtual-versioning-org-#{unique}",
        name: "Virtual Versioning Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "virtual-versioning-repo-#{unique}",
        name: "Virtual Versioning Repo #{unique}",
        organization_id: organization.id
      })

    session_id = "virtual-session-#{unique}"

    opened =
      VersioningServer.open_session(
        %V1.SessionOpenRequest{
          user_id: user.id,
          repository: %V1.RepositoryRef{
            organization_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          open: %V1.SessionOpen{
            session_id: session_id,
            goal: "Validate virtual versioning workflow",
            base_position: %V1.Position{hash: <<0::size(256)>>}
          }
        },
        nil
      )

    assert %V1.SessionInfo{} = opened
    assert opened.session_id == session_id
    assert opened.status == "active"

    appended_note =
      VersioningServer.append_session_conversation(
        %V1.SessionEventAppendRequest{
          user_id: user.id,
          session_id: session_id,
          event: %V1.SessionEvent{
            role: "agent",
            kind: "note",
            text: "Started implementing virtual RPCs",
            at_ms: System.system_time(:millisecond)
          }
        },
        nil
      )

    assert %V1.SessionInfo{} = appended_note
    assert length(appended_note.conversation) == 1
    assert hd(appended_note.conversation).text =~ "virtual RPCs"

    appended_change =
      VersioningServer.append_session_change(
        %V1.SessionChangeAppendRequest{
          user_id: user.id,
          session_id: session_id,
          operation: %V1.FileOperation{
            action: :ACTION_CREATE,
            path: "docs/virtual.txt",
            content: "virtual content\n"
          }
        },
        nil
      )

    assert %V1.SessionInfo{} = appended_change
    assert length(appended_change.changes) == 1
    assert hd(appended_change.changes).path == "docs/virtual.txt"

    loaded =
      VersioningServer.get_session(
        %V1.SessionRequest{user_id: user.id, session_id: session_id},
        nil
      )

    assert %V1.SessionInfo{} = loaded
    assert loaded.session_id == session_id
    assert length(loaded.conversation) == 1
    assert length(loaded.changes) == 1
  end
end
