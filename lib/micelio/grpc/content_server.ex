defmodule Micelio.GRPC.Content.V1.ContentService.Server do
  use GRPC.Server, service: Micelio.GRPC.Content.V1.ContentService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Content.V1

  alias Micelio.GRPC.Content.V1.{
    BlameLine,
    GetBlobRequest,
    GetBlobResponse,
    GetBlameRequest,
    GetBlameResponse,
    GetHeadTreeRequest,
    GetPathRequest,
    GetPathResponse,
    GetTreeAtPositionRequest,
    GetTreeRequest,
    GetTreeResponse,
    TreeEntry
  }

  alias Micelio.Mic.Binary
  alias Micelio.Mic.DeltaCompression
  alias Micelio.Mic.Tree, as: MicTree
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias Micelio.Storage

  @zero_hash <<0::size(256)>>

  def get_head_tree(%GetHeadTreeRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, tree_hash, tree} <- load_head_tree(repository.id) do
      %GetTreeResponse{tree: %V1.Tree{entries: tree_entries(tree)}, tree_hash: tree_hash}
    end
  end

  def get_tree(%GetTreeRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         :ok <- require_hash(request.tree_hash, "tree_hash"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, tree} <- load_tree(repository.id, request.tree_hash) do
      %GetTreeResponse{tree: %V1.Tree{entries: tree_entries(tree)}, tree_hash: request.tree_hash}
    end
  end

  def get_tree_at_position(%GetTreeAtPositionRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, tree_hash, tree} <- load_tree_at_position(repository.id, request.position) do
      %GetTreeResponse{tree: %V1.Tree{entries: tree_entries(tree)}, tree_hash: tree_hash}
    end
  end

  defp load_tree_at_position(_repository_id, 0) do
    # Position 0 means empty tree (before any landings)
    {:ok, Binary.zero_hash(), MicTree.empty()}
  end

  defp load_tree_at_position(repository_id, position) do
    landing_key = "repositories/#{repository_id}/landing/#{pad_position(position)}.bin"

    case Storage.get(landing_key) do
      {:ok, content} ->
        with {:ok, landing} <- Binary.decode_landing(content),
             {:ok, tree} <- load_tree(repository_id, landing.tree_hash) do
          {:ok, landing.tree_hash, tree}
        else
          {:error, _} -> {:error, internal_status("Failed to decode landing.")}
        end

      {:error, :not_found} ->
        {:error, not_found_status("Position not found.")}

      {:error, _reason} ->
        {:error, internal_status("Failed to load landing.")}
    end
  end

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  def get_blob(%GetBlobRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         :ok <- require_hash(request.blob_hash, "blob_hash"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, content} <- load_blob(repository.id, request.blob_hash) do
      %GetBlobResponse{content: content}
    end
  end

  def get_path(%GetPathRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         :ok <- require_field(request.path, "path"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, _tree_hash, tree} <- load_head_tree(repository.id),
         {:ok, blob_hash} <- fetch_path_hash(tree, request.path),
         {:ok, content} <- load_blob(repository.id, blob_hash) do
      %GetPathResponse{content: content, blob_hash: blob_hash}
    end
  end

  def get_blame(%GetBlameRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         :ok <- require_field(request.path, "path"),
         {:ok, organization, repository} <-
           load_repository(request.account_handle, request.repository_handle),
         :ok <- authorize_project_read(organization, repository, request.user_id, stream),
         {:ok, _tree_hash, tree} <- load_head_tree(repository.id),
         {:ok, blob_hash} <- fetch_path_hash(tree, request.path),
         {:ok, content} <- load_blob(repository.id, blob_hash),
         {:ok, text} <- ensure_text(content) do
      changes = Sessions.list_landed_changes_for_file(repository.id, request.path)

      lines =
        text
        |> Blame.build_lines(changes)
        |> Enum.map(&format_blame_line/1)

      %GetBlameResponse{lines: lines}
    end
  end

  defp fetch_path_hash(tree, path) do
    case Map.fetch(tree, path) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, not_found_status("Path not found.")}
    end
  end

  defp load_head_tree(repository_id) do
    case Storage.get(head_key(repository_id)) do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content),
             {:ok, tree} <- load_tree(repository_id, head.tree_hash) do
          {:ok, head.tree_hash, tree}
        else
          {:error, _} -> {:error, internal_status("Failed to decode head.")}
        end

      {:error, :not_found} ->
        {:ok, Binary.zero_hash(), MicTree.empty()}

      {:error, _reason} ->
        {:error, internal_status("Failed to load head.")}
    end
  end

  defp load_tree(_repository_id, tree_hash) when tree_hash == @zero_hash,
    do: {:ok, MicTree.empty()}

  defp load_tree(repository_id, tree_hash) do
    case Storage.get(tree_key(repository_id, tree_hash)) do
      {:ok, content} ->
        case MicTree.decode(content) do
          {:ok, tree} -> {:ok, tree}
          {:error, _} -> {:error, internal_status("Failed to decode tree.")}
        end

      {:error, :not_found} ->
        {:error, not_found_status("Tree not found.")}

      {:error, _reason} ->
        {:error, internal_status("Failed to load tree.")}
    end
  end

  defp load_blob(repository_id, blob_hash) do
    case Storage.get(blob_key(repository_id, blob_hash)) do
      {:ok, content} ->
        case DeltaCompression.decode(content, fn hash ->
               Storage.get(blob_key(repository_id, hash))
             end) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, internal_status("Failed to decode blob.")}
        end

      {:error, :not_found} ->
        {:error, not_found_status("Blob not found.")}

      {:error, _reason} ->
        {:error, internal_status("Failed to load blob.")}
    end
  end

  defp tree_entries(tree) do
    tree
    |> Map.to_list()
    |> Enum.sort_by(fn {path, _hash} -> path end)
    |> Enum.map(fn {path, hash} -> %TreeEntry{path: path, hash: hash} end)
  end

  defp head_key(repository_id), do: "repositories/#{repository_id}/head"

  defp tree_key(repository_id, tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/trees/#{prefix}/#{hash_hex}.bin"
  end

  defp blob_key(repository_id, blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/blobs/#{prefix}/#{hash_hex}.bin"
  end

  defp fetch_user(user_id, stream) do
    if require_auth_token?(stream) do
      fetch_user_from_token(user_id, stream)
    else
      case empty_to_nil(user_id) do
        nil -> fetch_user_from_token(user_id, stream)
        value -> fetch_user_by_id(value)
      end
    end
  end

  defp fetch_user_by_id(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, unauthenticated_status("User not found.")}
      user -> {:ok, user}
    end
  end

  defp fetch_user_from_token(user_id, stream) do
    with {:ok, token} <- fetch_bearer_token(stream),
         %Boruta.Oauth.Token{} = access_token <- AccessTokens.get_by(value: token),
         user when not is_nil(user) <- Accounts.get_user(access_token.sub) do
      case empty_to_nil(user_id) do
        nil -> {:ok, user}
        value when value == user.id -> {:ok, user}
        _ -> {:error, unauthenticated_status("User does not match access token.")}
      end
    else
      _ -> {:error, unauthenticated_status("User is required.")}
    end
  end

  defp fetch_bearer_token(stream) do
    case Map.get(stream.http_request_headers, "authorization") do
      "Bearer " <> token -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp load_repository(account_handle, repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(account_handle),
         %Repositories.Repository{} = repository <-
           Repositories.get_repository_by_handle(organization.id, repository_handle) do
      {:ok, organization, repository}
    else
      nil -> {:error, not_found_status("Project not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  defp authorize_project_read(organization, repository, user_id, stream) do
    if repository.visibility == "public" do
      if require_auth_token?(stream) do
        case fetch_user(user_id, stream) do
          {:ok, _user} -> :ok
          {:error, status} -> {:error, status}
        end
      else
        :ok
      end
    else
      with {:ok, user} <- fetch_user(user_id, stream),
           true <- Accounts.user_in_organization?(user, organization.id) do
        :ok
      else
        false -> {:error, forbidden_status("You do not have access to this account.")}
        {:error, status} -> {:error, status}
      end
    end
  end

  defp require_auth_token? do
    config = Application.get_env(:micelio, Micelio.GRPC, [])
    Keyword.get(config, :require_auth_token, false)
  end

  defp require_auth_token?(stream) when is_map(stream) do
    headers = Map.get(stream, :http_request_headers) || %{}

    case Map.get(headers, "x-micelio-require-auth") do
      "true" -> true
      "false" -> false
      _ -> require_auth_token?()
    end
  end

  defp require_auth_token?(_stream), do: require_auth_token?()

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp require_hash(value, field_name) when is_binary(value) do
    if byte_size(value) == 32 do
      :ok
    else
      {:error, invalid_status("#{field_name} must be a 32-byte hash.")}
    end
  end

  defp require_hash(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp ensure_text(content) when is_binary(content) do
    limit = 200_000
    content = if byte_size(content) > limit, do: binary_part(content, 0, limit), else: content

    if String.valid?(content) do
      {:ok, content}
    else
      {:error, invalid_status("Binary file cannot be blamed.")}
    end
  end

  defp format_blame_line(%{attribution: attribution} = line) do
    session = if attribution, do: Map.get(attribution, :session)
    account = if session, do: session.user && session.user.account

    %BlameLine{
      line_number: line.line_number,
      text: line.text,
      session_id: if(session, do: session.session_id, else: ""),
      author_handle: if(account, do: account.handle, else: ""),
      landed_at: format_timestamp(session && session.landed_at)
    }
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)
  defp internal_status(message), do: rpc_error(Status.internal(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
