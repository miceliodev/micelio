defmodule Micelio.GRPC.VirtualVersioningServerTest do
  use Micelio.DataCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias GRPC.Server.Stream
  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.GRPC.Hif.V1.VersioningService.Server, as: VersioningServer
  alias Micelio.Mic.{Binary, Project, Tree}
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Repositories
  alias Micelio.Storage

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

    token = create_access_token(user)
    stream = token_stream(token)

    session_id = "virtual-session-#{unique}"

    opened =
      VersioningServer.open_session(
        %V1.SessionOpenRequest{
          repository: %V1.RepositoryRef{
            account_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          open: %V1.SessionOpen{
            session_id: session_id,
            goal: "Validate virtual versioning workflow",
            base_position: %V1.Position{hash: <<0::size(256)>>}
          }
        },
        stream
      )

    assert %V1.SessionInfo{} = opened
    assert opened.session_id == session_id
    assert opened.status == "active"
    assert %V1.Attribution{} = opened.attribution
    assert %V1.IdentityRef{} = opened.attribution.attributed_to
    assert opened.attribution.attributed_to.handle == user.account.handle
    assert opened.attribution.attributed_to.kind == "user"
    assert %V1.IdentityRef{} = opened.attribution.performed_by
    assert opened.attribution.performed_by.id == opened.attribution.attributed_to.id

    appended_note =
      VersioningServer.append_session_conversation(
        %V1.SessionEventAppendRequest{
          session_id: session_id,
          event: %V1.SessionEvent{
            role: "agent",
            kind: "note",
            text: "Started implementing virtual RPCs",
            at_ms: System.system_time(:millisecond)
          }
        },
        stream
      )

    assert %V1.SessionInfo{} = appended_note
    assert length(appended_note.conversation) == 1
    assert hd(appended_note.conversation).text =~ "virtual RPCs"

    appended_change =
      VersioningServer.append_session_change(
        %V1.SessionChangeAppendRequest{
          session_id: session_id,
          operation: %V1.FileOperation{
            action: :ACTION_CREATE,
            path: "docs/virtual.txt",
            content: "virtual content\n"
          }
        },
        stream
      )

    assert %V1.SessionInfo{} = appended_change
    assert length(appended_change.changes) == 1
    assert hd(appended_change.changes).path == "docs/virtual.txt"

    loaded =
      VersioningServer.get_session(
        %V1.SessionRequest{session_id: session_id},
        stream
      )

    assert %V1.SessionInfo{} = loaded
    assert loaded.session_id == session_id
    assert length(loaded.conversation) == 1
    assert length(loaded.changes) == 1
  end

  test "get_repository_head allows anonymous reads for public repositories" do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "public-versioning-org-#{unique}",
        name: "Public Versioning Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "public-versioning-repo-#{unique}",
        name: "Public Versioning Repo #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    content = "lazy mount\n"
    blob_hash = :crypto.hash(:sha256, content)
    {:ok, _} = Storage.put(Project.blob_key(repository.id, blob_hash), content)

    tree = %{"README.md" => blob_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository.id, tree_hash), encoded_tree)

    {:ok, _} =
      Storage.put(
        Project.head_key(repository.id),
        Binary.encode_head(Binary.new_head(1, tree_hash))
      )

    response =
      VersioningServer.get_repository_head(
        %V1.GetRepositoryHeadRequest{
          repository: %V1.RepositoryRef{
            account_handle: organization.account.handle,
            repository_handle: repository.handle
          }
        },
        %Stream{http_request_headers: %{}}
      )

    assert %V1.RepositoryHeadResponse{} = response
    assert response.head.hash == tree_hash
    assert response.repository.account_handle == organization.account.handle
    assert response.repository.repository_handle == repository.handle
  end

  defp token_stream(token) do
    %Stream{
      http_request_headers: %{
        "authorization" => "Bearer #{token}"
      }
    }
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "Test CLI"})
    client = Clients.get_client(device_client.client_id)

    params = %{
      client: client,
      scope: "",
      sub: to_string(user.id),
      resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
    }

    {:ok, token} = AccessTokens.create(params, refresh_token: true)
    Map.get(token, :value) || Map.get(token, :access_token)
  end
end
