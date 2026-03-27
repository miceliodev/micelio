defmodule Micelio.GRPC.VirtualContentServerTest do
  use Micelio.DataCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias GRPC.Server.Stream
  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.GRPC.Hif.V1.ContentService.Server, as: ContentServer
  alias Micelio.Mic.{Binary, Project, Tree}
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Storage

  test "get_tree and get_path resolve content at a revision hash" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("virtual-content-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "virtual-content-org-#{unique}",
        name: "Virtual Content Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "virtual-content-repo-#{unique}",
        name: "Virtual Content Repo #{unique}",
        organization_id: organization.id
      })

    content = "hello from virtual content\n"
    blob_hash = :crypto.hash(:sha256, content)
    {:ok, _} = Storage.put(Project.blob_key(repository.id, blob_hash), content)

    tree = %{"README.md" => blob_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository.id, tree_hash), encoded_tree)

    head = Binary.new_head(1, tree_hash)
    {:ok, _} = Storage.put(Project.head_key(repository.id), Binary.encode_head(head))

    token = create_access_token(user)
    stream = token_stream(token)

    tree_response =
      ContentServer.get_tree(
        %V1.GetTreeRequest{
          repository: %V1.RepositoryRef{
            account_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          revision_hash: tree_hash
        },
        stream
      )

    assert %V1.TreeResponse{} = tree_response
    assert tree_response.tree_hash == tree_hash
    assert Enum.any?(tree_response.entries, &(&1.path == "README.md"))

    path_response =
      ContentServer.get_path(
        %V1.GetPathRequest{
          repository: %V1.RepositoryRef{
            account_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          revision_hash: tree_hash,
          path: "README.md"
        },
        stream
      )

    assert %V1.PathResponse{} = path_response
    assert path_response.content == content
    assert path_response.content_hash == blob_hash
    assert path_response.size == byte_size(content)
  end

  test "blame returns landed session attribution with landed_at timestamp" do
    unique = System.unique_integer([:positive])

    {:ok, user} = Accounts.get_or_create_user_by_email("virtual-blame-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "virtual-blame-org-#{unique}",
        name: "Virtual Blame Org #{unique}"
      })

    {:ok, repository} =
      Repositories.create_repository(%{
        handle: "virtual-blame-repo-#{unique}",
        name: "Virtual Blame Repo #{unique}",
        organization_id: organization.id
      })

    content = "hello from virtual blame"
    blob_hash = :crypto.hash(:sha256, content)
    {:ok, _} = Storage.put(Project.blob_key(repository.id, blob_hash), content)

    tree = %{"README.md" => blob_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Project.tree_key(repository.id, tree_hash), encoded_tree)

    head = Binary.new_head(1, tree_hash)
    {:ok, _} = Storage.put(Project.head_key(repository.id), Binary.encode_head(head))

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "virtual-blame-session-#{unique}",
        goal: "Seed blame attribution",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "README.md",
        change_type: "modified",
        content: content
      })

    {:ok, session} =
      Sessions.land_session(session, %{
        metadata: %{"landing_revision_hash" => Base.encode64(tree_hash)}
      })

    token = create_access_token(user)
    stream = token_stream(token)

    blame_response =
      ContentServer.blame(
        %V1.BlameRequest{
          repository: %V1.RepositoryRef{
            account_handle: organization.account.handle,
            repository_handle: repository.handle
          },
          revision_hash: tree_hash,
          path: "README.md"
        },
        stream
      )

    assert %V1.BlameResponse{} = blame_response
    assert [%V1.BlameLine{} = line] = blame_response.lines
    assert line.path == "README.md"
    assert line.line == 1
    assert line.text == "hello from virtual blame"
    assert line.session_id == session.session_id
    assert %V1.IdentityRef{} = line.attributed_to
    assert line.attributed_to.handle == user.account.handle
    assert line.attributed_to.kind == "user"
    assert line.attributed_to.id != ""
    assert line.revision_hash == tree_hash
    assert line.landed_at > 0
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
