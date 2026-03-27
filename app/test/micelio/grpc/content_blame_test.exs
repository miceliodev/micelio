defmodule Micelio.GRPC.ContentBlameTest do
  use Micelio.DataCase, async: true

  alias GRPC.Server.Stream
  alias Micelio.Accounts
  alias Micelio.GRPC.Content.V1.ContentService.Server, as: ContentServer
  alias Micelio.GRPC.Content.V1.GetBlameRequest
  alias Micelio.Mic.{Binary, Repository, Tree}
  alias Micelio.Sessions
  alias Micelio.Storage

  test "get_blame returns session attribution" do
    {:ok, user_one} = Accounts.get_or_create_user_by_email("blame-one@example.com")
    {:ok, user_two} = Accounts.get_or_create_user_by_email("blame-two@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user_one, %{
        handle: "blame-org",
        name: "Blame Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "blame-project",
        name: "Blame Project",
        organization_id: organization.id,
        visibility: "public"
      })

    base_content = ~s{IO.puts("ok")}
    updated_content = ~s{IO.puts("ok")\nIO.puts("next")}

    updated_hash = :crypto.hash(:sha256, updated_content)
    {:ok, _} = Storage.put(Repository.blob_key(repository.id, updated_hash), updated_content)

    tree = %{"lib/app.ex" => updated_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(repository.id, tree_hash), encoded_tree)

    head = Binary.new_head(6, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(repository.id), Binary.encode_head(head))

    {:ok, session_one} =
      Sessions.create_session(%{
        session_id: "session-one",
        goal: "Initial import",
        repository_id: repository.id,
        user_id: user_one.id
      })

    {:ok, _} =
      Sessions.create_session_change(%{
        session_id: session_one.id,
        file_path: "lib/app.ex",
        change_type: "added",
        content: base_content
      })

    {:ok, session_one} = Sessions.land_session(session_one)

    {:ok, _} =
      Sessions.update_session(session_one, %{
        landed_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, session_two} =
      Sessions.create_session(%{
        session_id: "session-two",
        goal: "Add follow-up output",
        repository_id: repository.id,
        user_id: user_two.id
      })

    {:ok, _} =
      Sessions.create_session_change(%{
        session_id: session_two.id,
        file_path: "lib/app.ex",
        change_type: "modified",
        content: updated_content
      })

    {:ok, session_two} = Sessions.land_session(session_two)

    response =
      ContentServer.get_blame(
        %GetBlameRequest{
          user_id: "",
          account_handle: organization.account.handle,
          repository_handle: repository.handle,
          path: "lib/app.ex"
        },
        empty_stream()
      )

    assert %Micelio.GRPC.Content.V1.GetBlameResponse{} = response
    assert length(response.lines) == 2

    [first, second] = response.lines

    assert first.line_number == 1
    assert first.text == base_content
    assert first.session_id == session_one.session_id
    assert first.author_handle == user_one.account.handle
    assert first.landed_at != ""

    assert second.line_number == 2
    assert second.text == "IO.puts(\"next\")"
    assert second.session_id == session_two.session_id
    assert second.author_handle == user_two.account.handle
    assert second.landed_at != ""
  end

  defp empty_stream do
    %Stream{http_request_headers: %{}}
  end
end
