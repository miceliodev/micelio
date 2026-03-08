defmodule Micelio.GRPC.Hif.V1.ContentService.Server do
  use GRPC.Server, service: Micelio.GRPC.Hif.V1.ContentService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.Mic.{Binary, Project}
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias Micelio.Storage

  def get_tree(%V1.GetTreeRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         {:ok, organization, repository} <- load_repository(request.repository),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream),
         {:ok, tree_hash} <- resolve_tree_hash(repository.id, request.position, request.tree_hash),
         {:ok, tree} <- Project.get_tree(repository.id, tree_hash) do
      %V1.TreeResponse{
        repository: repository_ref(organization, repository),
        tree_hash: tree_hash,
        entries: tree_entries(tree)
      }
    end
  end

  def get_path(%V1.GetPathRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_field(request.path, "path"),
         {:ok, organization, repository} <- load_repository(request.repository),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream),
         {:ok, tree_hash} <- resolve_tree_hash(repository.id, request.position, request.tree_hash),
         {:ok, tree} <- Project.get_tree(repository.id, tree_hash),
         blob_hash when is_binary(blob_hash) <- Map.get(tree, request.path),
         {:ok, content} <- Project.get_blob(repository.id, blob_hash) do
      %V1.PathResponse{
        content: content,
        content_hash: blob_hash,
        mode: 0o100644,
        size: byte_size(content)
      }
    else
      nil -> {:error, not_found_status("Path not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_blob(%V1.GetBlobRequest{} = request, stream) do
    with :ok <- require_hash(request.content_hash, "content_hash"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, content} <- find_blob_for_user(user, request.content_hash) do
      %V1.BlobResponse{content: content}
    end
  end

  def diff(%V1.DiffRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_position(request.from_position, "from_position"),
         {:ok, organization, repository} <- load_repository(request.repository),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream),
         {:ok, from_tree} <- load_tree_at_position(repository.id, request.from_position),
         to_position = resolve_to_position(repository.id, request.to_position),
         {:ok, to_tree} <- load_tree_at_position(repository.id, to_position) do
      path_prefix = empty_to_nil(request.path_prefix)

      hunks =
        diff_paths(from_tree, to_tree, path_prefix)
        |> Enum.flat_map(fn {path, old_hash, new_hash} ->
          old_text = load_blob_text(repository.id, old_hash)
          new_text = load_blob_text(repository.id, new_hash)
          build_diff_hunks(path, old_text, new_text)
        end)

      %V1.DiffResponse{hunks: hunks}
    end
  end

  def blame(%V1.BlameRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_field(request.path, "path"),
         {:ok, organization, repository} <- load_repository(request.repository),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream),
         {:ok, tree} <- load_tree_at_position(repository.id, request.position),
         blob_hash when is_binary(blob_hash) <- Map.get(tree, request.path),
         {:ok, content} <- Project.get_blob(repository.id, blob_hash),
         {:ok, text} <- ensure_text(content) do
      changes = Sessions.list_landed_changes_for_file(repository.id, request.path)

      lines =
        text
        |> Blame.build_lines(changes)
        |> Enum.map(fn line ->
          attribution = Map.get(line, :attribution)
          session = attribution && Map.get(attribution, :session)

          %V1.BlameLine{
            path: request.path,
            line: line.line_number,
            text: line.text,
            session_id: if(session, do: session.session_id, else: ""),
            actor_handle: actor_handle(session),
            position: landing_position(session),
            at_ms: landed_at_ms(session)
          }
        end)

      %V1.BlameResponse{lines: lines}
    else
      nil -> {:error, not_found_status("Path not found.")}
      {:error, status} -> {:error, status}
    end
  end

  defp repository_ref(organization, repository) do
    %V1.RepositoryRef{
      organization_handle: organization.account.handle,
      repository_handle: repository.handle
    }
  end

  defp load_repository(%V1.RepositoryRef{} = repository_ref) do
    with {:ok, organization} <-
           Accounts.get_organization_by_handle(repository_ref.organization_handle),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(
             organization.id,
             repository_ref.repository_handle
           ) do
      {:ok, organization, Repositories.get_repository_with_organization(repository.id)}
    else
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  defp resolve_tree_hash(repository_id, position, tree_hash) do
    cond do
      is_binary(tree_hash) and byte_size(tree_hash) == 32 ->
        {:ok, tree_hash}

      is_integer(position) and position > 0 ->
        load_tree_hash_at_position(repository_id, position)

      true ->
        with {:ok, head, _etag} <- fetch_head(repository_id) do
          {:ok, head.tree_hash}
        end
    end
  end

  defp load_tree_at_position(_repository_id, 0), do: {:ok, %{}}

  defp load_tree_at_position(repository_id, position)
       when is_integer(position) and position > 0 do
    with {:ok, tree_hash} <- load_tree_hash_at_position(repository_id, position) do
      Project.get_tree(repository_id, tree_hash)
    end
  end

  defp load_tree_at_position(repository_id, _position) do
    with {:ok, head, _etag} <- fetch_head(repository_id) do
      Project.get_tree(repository_id, head.tree_hash)
    end
  end

  defp load_tree_hash_at_position(_repository_id, 0), do: {:ok, Binary.zero_hash()}

  defp load_tree_hash_at_position(repository_id, position) do
    with {:ok, head, _etag} <- fetch_head(repository_id) do
      if head.position == position do
        {:ok, head.tree_hash}
      else
        landing_key = "repositories/#{repository_id}/landing/#{pad_position(position)}.bin"

        case Storage.get(landing_key) do
          {:ok, encoded} ->
            case Binary.decode_landing(encoded) do
              {:ok, landing} -> {:ok, landing.tree_hash}
              {:error, _} -> {:error, internal_status("Failed to decode landing record.")}
            end

          {:error, :not_found} ->
            {:error, not_found_status("Position not found.")}

          {:error, _reason} ->
            {:error, internal_status("Failed to load landing record.")}
        end
      end
    end
  end

  defp fetch_head(repository_id) do
    case Storage.get_with_metadata(Project.head_key(repository_id)) do
      {:ok, %{content: content, etag: etag}} ->
        case Binary.decode_head(content) do
          {:ok, head} -> {:ok, head, etag || ""}
          {:error, _} -> {:error, internal_status("Failed to decode head.")}
        end

      {:error, :not_found} ->
        {:ok, Binary.new_head(0, Binary.zero_hash()), ""}

      {:error, _reason} ->
        {:error, internal_status("Failed to load repository head.")}
    end
  end

  defp tree_entries(tree) do
    tree
    |> Enum.sort_by(fn {path, _hash} -> path end)
    |> Enum.map(fn {path, hash} ->
      %V1.TreeEntry{
        path: path,
        hash: Base.encode16(hash, case: :lower)
      }
    end)
  end

  defp resolve_to_position(_repository_id, position) when is_integer(position) and position > 0,
    do: position

  defp resolve_to_position(repository_id, _position) do
    case fetch_head(repository_id) do
      {:ok, head, _etag} -> head.position
      _ -> 0
    end
  end

  defp diff_paths(from_tree, to_tree, path_prefix) do
    from_tree
    |> Map.keys()
    |> Kernel.++(Map.keys(to_tree))
    |> Enum.uniq()
    |> Enum.filter(fn path ->
      case path_prefix do
        nil -> true
        prefix -> String.starts_with?(path, prefix)
      end
    end)
    |> Enum.filter(fn path -> Map.get(from_tree, path) != Map.get(to_tree, path) end)
    |> Enum.map(fn path -> {path, Map.get(from_tree, path), Map.get(to_tree, path)} end)
  end

  defp load_blob_text(_repository_id, nil), do: nil

  defp load_blob_text(repository_id, blob_hash) do
    case Project.get_blob(repository_id, blob_hash) do
      {:ok, content} ->
        if String.valid?(content), do: content, else: Base.encode64(content)

      _ ->
        nil
    end
  end

  defp build_diff_hunks(path, old_text, new_text) do
    old_lines = split_lines(old_text)
    new_lines = split_lines(new_text)
    max_lines = max(length(old_lines), length(new_lines))

    if max_lines == 0 do
      []
    else
      Enum.reduce(1..max_lines, [], fn line, acc ->
        old_line = Enum.at(old_lines, line - 1)
        new_line = Enum.at(new_lines, line - 1)

        if old_line == new_line do
          acc
        else
          [
            %V1.DiffHunk{
              path: path,
              line: line,
              old_line: old_line || "",
              new_line: new_line || ""
            }
            | acc
          ]
        end
      end)
      |> Enum.reverse()
    end
  end

  defp split_lines(nil), do: []
  defp split_lines(text), do: String.split(text, "\n", trim: false)

  defp ensure_text(content) when is_binary(content) do
    if String.valid?(content) do
      {:ok, content}
    else
      {:error, invalid_status("Blob is not valid UTF-8 text.")}
    end
  end

  defp actor_handle(nil), do: ""

  defp actor_handle(session) do
    get_in(session, [:user, :account, :handle]) || ""
  end

  defp landing_position(nil), do: 0

  defp landing_position(session) do
    metadata = Map.get(session, :metadata) || %{}

    case Map.get(metadata, "landing_position") do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _ -> 0
    end
  end

  defp landed_at_ms(nil), do: 0
  defp landed_at_ms(%{landed_at: nil}), do: 0

  defp landed_at_ms(%{landed_at: landed_at}) do
    DateTime.to_unix(landed_at, :millisecond)
  end

  defp find_blob_for_user(user, content_hash) do
    repositories =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.flat_map(&Repositories.list_repositories_for_organization(&1.id))

    Enum.find_value(repositories, {:error, not_found_status("Blob not found.")}, fn repository ->
      case Project.get_blob(repository.id, content_hash) do
        {:ok, content} -> {:ok, content}
        _ -> nil
      end
    end)
  end

  defp authorize_repository_read(organization, repository, user_id, stream) do
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
        false -> {:error, forbidden_status("You do not have access to this organization.")}
        {:error, status} -> {:error, status}
      end
    end
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

  defp require_repository_ref(%V1.RepositoryRef{} = repository_ref) do
    with :ok <-
           require_field(repository_ref.organization_handle, "repository.organization_handle") do
      require_field(repository_ref.repository_handle, "repository.repository_handle")
    end
  end

  defp require_repository_ref(_), do: {:error, invalid_status("repository is required.")}

  defp require_position(value, _field_name) when is_integer(value) and value > 0, do: :ok

  defp require_position(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp require_hash(value, field_name) when is_binary(value) do
    if byte_size(value) == 32 do
      :ok
    else
      {:error, invalid_status("#{field_name} must be 32 bytes.")}
    end
  end

  defp require_hash(_value, field_name),
    do: {:error, invalid_status("#{field_name} must be 32 bytes.")}

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_value), do: 0

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp invalid_status(message) do
    %RPCError{status: Status.invalid_argument(), message: message}
  end

  defp unauthenticated_status(message) do
    %RPCError{status: Status.unauthenticated(), message: message}
  end

  defp forbidden_status(message) do
    %RPCError{status: Status.permission_denied(), message: message}
  end

  defp not_found_status(message) do
    %RPCError{status: Status.not_found(), message: message}
  end

  defp internal_status(message) do
    %RPCError{status: Status.internal(), message: message}
  end
end
