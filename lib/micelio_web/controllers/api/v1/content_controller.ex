defmodule MicelioWeb.Api.V1.ContentController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.Mic.Binary
  alias Micelio.Mic.DeltaCompression
  alias Micelio.Mic.Tree, as: MicTree
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias Micelio.Storage
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug, ["content:read"]

  tags(["Content"])

  operation(:tree,
    summary: "Get repository tree",
    description: "Gets the current head tree (file listing) for a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      path: [in: :query, type: :string, description: "Optional sub-path filter"]
    ],
    security: [%{"bearer" => ["content:read"]}],
    responses: %{
      200 => {"Tree entries", "application/json", Schemas.TreeResponse},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def tree(conn, %{"org" => org_handle, "repo" => repo_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, _tree_hash, tree} <- load_head_tree(repository.id) do
      path_filter = params["path"]

      entries =
        tree
        |> Map.to_list()
        |> maybe_filter_path(path_filter)
        |> Enum.sort_by(fn {path, _hash} -> path end)
        |> Enum.map(fn {path, _hash} ->
          %{name: path, type: "blob"}
        end)

      json(conn, %{data: entries})
    else
      {:error, :not_found} -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:blob,
    summary: "Get file content",
    description: "Gets the content of a file at the given path.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      path: [in: :path, type: :string, description: "File path", required: true]
    ],
    security: [%{"bearer" => ["content:read"]}],
    responses: %{
      200 => {"Blob content", "application/json", Schemas.BlobResponse},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def blob(conn, %{"org" => org_handle, "repo" => repo_handle, "path" => path_parts}) do
    file_path = Enum.join(List.wrap(path_parts), "/")

    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, _tree_hash, tree} <- load_head_tree(repository.id),
         {:ok, blob_hash} <- fetch_path_hash(tree, file_path),
         {:ok, content} <- load_blob(repository.id, blob_hash) do
      {encoded, encoding} =
        if String.valid?(content) do
          {content, "utf-8"}
        else
          {Base.encode64(content), "base64"}
        end

      json(conn, %{
        data: %{
          content: encoded,
          encoding: encoding,
          size: byte_size(content)
        }
      })
    else
      {:error, :not_found} ->
        Helpers.handle_error(conn, {:error, :not_found})

      {:error, :path_not_found} ->
        Helpers.error_response(conn, :not_found, "not_found", "File path not found")

      error ->
        Helpers.handle_error(conn, error)
    end
  end

  operation(:blame,
    summary: "Get file blame",
    description: "Gets blame (session attribution) for each line of a file.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      path: [in: :path, type: :string, description: "File path", required: true]
    ],
    security: [%{"bearer" => ["content:read"]}],
    responses: %{
      200 => {"Blame lines", "application/json", Schemas.BlameResponse},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def blame(conn, %{"org" => org_handle, "repo" => repo_handle, "path" => path_parts}) do
    file_path = Enum.join(List.wrap(path_parts), "/")

    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, _tree_hash, tree} <- load_head_tree(repository.id),
         {:ok, blob_hash} <- fetch_path_hash(tree, file_path),
         {:ok, content} <- load_blob(repository.id, blob_hash),
         {:ok, text} <- ensure_text(content) do
      changes = Sessions.list_landed_changes_for_file(repository.id, file_path)

      lines =
        text
        |> Blame.build_lines(changes)
        |> Enum.map(fn line ->
          attribution = line[:attribution]
          session = if attribution, do: Map.get(attribution, :session)
          account = if session, do: session.user && session.user.account

          %{
            line_number: line.line_number,
            text: line.text,
            session_id: if(session, do: session.session_id),
            author: if(account, do: account.handle),
            landed_at: if(session, do: Helpers.format_datetime(session.landed_at))
          }
        end)

      json(conn, %{data: lines})
    else
      {:error, :not_found} ->
        Helpers.handle_error(conn, {:error, :not_found})

      {:error, :path_not_found} ->
        Helpers.error_response(conn, :not_found, "not_found", "File path not found")

      {:error, :binary_file} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "binary_file",
          "Binary files cannot be blamed"
        )

      error ->
        Helpers.handle_error(conn, error)
    end
  end

  # Storage helpers (mirroring gRPC content server)

  @zero_hash <<0::size(256)>>

  defp load_head_tree(repository_id) do
    case Storage.get(head_key(repository_id)) do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content),
             {:ok, tree} <- load_tree(repository_id, head.tree_hash) do
          {:ok, head.tree_hash, tree}
        else
          {:error, _} -> {:error, :not_found}
        end

      {:error, :not_found} ->
        {:ok, Binary.zero_hash(), MicTree.empty()}

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  defp load_tree(_repository_id, tree_hash) when tree_hash == @zero_hash,
    do: {:ok, MicTree.empty()}

  defp load_tree(repository_id, tree_hash) do
    case Storage.get(tree_key(repository_id, tree_hash)) do
      {:ok, content} ->
        case MicTree.decode(content) do
          {:ok, tree} -> {:ok, tree}
          {:error, _} -> {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp load_blob(repository_id, blob_hash) do
    case Storage.get(blob_key(repository_id, blob_hash)) do
      {:ok, content} ->
        case DeltaCompression.decode(content, fn hash ->
               Storage.get(blob_key(repository_id, hash))
             end) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp fetch_path_hash(tree, path) do
    case Map.fetch(tree, path) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, :path_not_found}
    end
  end

  defp ensure_text(content) when is_binary(content) do
    if String.valid?(content) do
      {:ok, content}
    else
      {:error, :binary_file}
    end
  end

  defp maybe_filter_path(entries, nil), do: entries

  defp maybe_filter_path(entries, prefix) do
    Enum.filter(entries, fn {path, _hash} -> String.starts_with?(path, prefix) end)
  end

  defp head_key(repository_id), do: "projects/#{repository_id}/head"

  defp tree_key(repository_id, tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "projects/#{repository_id}/trees/#{prefix}/#{hash_hex}.bin"
  end

  defp blob_key(repository_id, blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "projects/#{repository_id}/blobs/#{prefix}/#{hash_hex}.bin"
  end
end
