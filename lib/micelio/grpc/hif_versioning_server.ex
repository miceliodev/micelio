defmodule Micelio.GRPC.Hif.V1.VersioningService.Server do
  use GRPC.Server, service: Micelio.GRPC.Hif.V1.VersioningService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.Mic.{Binary, Landing, Project}
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Sessions.ChangeStore
  alias Micelio.Sessions.Conflict
  alias Micelio.Sessions.Session
  alias Micelio.Storage

  @zero_hash Binary.zero_hash()

  def get_repository_head(%V1.GetRepositoryHeadRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization, repository} <- load_repository(request.repository),
         true <- Accounts.user_in_organization?(user, organization.id),
         {:ok, head, etag} <- fetch_head(repository.id) do
      %V1.RepositoryHeadResponse{
        repository: repository_ref(organization, repository),
        head: revision_proto(head.tree_hash),
        head_etag: etag
      }
    else
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_head_at(%V1.GetHeadAtRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_hash(request.revision_hash, "revision_hash"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization, repository} <- load_repository(request.repository),
         true <- Accounts.user_in_organization?(user, organization.id),
         {:ok, head, etag} <- fetch_head_by_revision_hash(repository.id, request.revision_hash) do
      %V1.RepositoryHeadResponse{
        repository: repository_ref(organization, repository),
        head: revision_proto(head.tree_hash),
        head_etag: etag
      }
    else
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def open_session(%V1.SessionOpenRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_field(request.open.session_id, "open.session_id"),
         :ok <- require_field(request.open.goal, "open.goal"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization, repository} <- load_repository(request.repository),
         true <- Accounts.user_in_organization?(user, organization.id),
         nil <- Sessions.get_session_by_session_id(request.open.session_id),
         {:ok, base_revision_hash} <-
           resolve_base_revision_hash(repository.id, request.open.base_position),
         metadata =
           %{
             "organization_handle" => organization.account.handle,
             "repository_handle" => repository.handle,
             "base_revision_hash" => Base.encode64(base_revision_hash),
             "requested_workspace" => empty_to_nil(request.open.requested_workspace),
             "contributor_type" => "human"
           }
           |> drop_nil_values(),
         attrs = %{
           session_id: request.open.session_id,
           goal: request.open.goal,
           repository_id: repository.id,
           user_id: user.id,
           metadata: metadata
         },
         {:ok, session} <- Sessions.create_session(attrs) do
      session_to_proto(session, repository)
    else
      false ->
        {:error, forbidden_status("You do not have access to this organization.")}

      %Session{} ->
        {:error, conflict_status("Session already exists.")}

      nil ->
        {:error, not_found_status("Repository not found.")}

      {:error, %RPCError{} = status} ->
        {:error, status}

      {:error, changeset} ->
        {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
    end
  end

  def append_session_conversation(%V1.SessionEventAppendRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, session, repository} <- load_writable_session(request.session_id, user),
         :ok <- require_field(request.event.text, "event.text"),
         event = event_to_map(request.event),
         conversation = normalize_list(session.conversation) ++ [event],
         metadata = clear_conflict_metadata(session.metadata),
         {:ok, updated} <-
           Sessions.update_session(session, %{conversation: conversation, metadata: metadata}) do
      session_to_proto(updated, repository)
    end
  end

  def append_session_change(%V1.SessionChangeAppendRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, session, repository} <- load_writable_session(request.session_id, user),
         :ok <- ensure_session_active(session),
         {:ok, files} <- operation_to_change_payloads(request.operation, session),
         {:ok, updated_session, _stats} <- ChangeStore.store_session_changes(session, files),
         {:ok, refreshed} <- refresh_change_filter(updated_session) do
      session_to_proto(refreshed, repository)
    end
  end

  def land_session(%V1.LandSessionRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, session, repository} <- load_writable_session(request.session_id, user),
         {:ok, session_with_decisions} <- append_decisions(session, request.decision),
         {:ok, session_with_epoch} <- update_epoch_batch(session_with_decisions, request.epoch),
         :ok <- ensure_session_active(session_with_epoch) do
      if request.epoch > 0 and not request.finalize do
        session_to_proto(session_with_epoch, repository)
      else
        do_land_session(session_with_epoch, repository)
      end
    end
  end

  def abandon_session(%V1.AbandonSessionRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, session, repository} <- load_writable_session(request.session_id, user),
         {:ok, updated} <- Sessions.abandon_session(session) do
      session_to_proto(updated, repository)
    else
      {:error, %RPCError{} = status} ->
        {:error, status}

      {:error, changeset} ->
        {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
    end
  end

  def get_session(%V1.SessionRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, session, repository} <- load_readable_session(request.session_id, user) do
      session_to_proto(session, repository)
    end
  end

  def list_sessions(%V1.ListSessionsRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization, repository} <- load_repository(request.repository),
         true <- Accounts.user_in_organization?(user, organization.id) do
      sessions =
        repository
        |> Sessions.list_sessions_for_repository_with_details(status: "landed")
        |> maybe_filter_sessions_by_path(repository.id, empty_to_nil(request.path))
        |> Enum.take(normalize_limit(request.limit))

      %V1.ListSessionsResponse{
        sessions: Enum.map(sessions, &session_summary/1)
      }
    else
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, status} -> {:error, status}
    end
  end

  defp do_land_session(%Session{} = session, repository) do
    case Landing.land_session(session) do
      {:ok, landing} ->
        revision_hash = landing.tree_hash || current_head_revision_hash(repository.id)

        metadata =
          session.metadata
          |> normalize_metadata()
          |> Map.put("landing_revision_hash", Base.encode64(revision_hash))
          |> Map.delete("virtual_conflict")

        case Sessions.land_session(session, %{landed_at: landing.landed_at, metadata: metadata}) do
          {:ok, landed_session} ->
            session_to_proto(landed_session, repository)

          {:error, changeset} ->
            {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
        end

      {:error, {:conflicts, paths}} ->
        conflict = %{
          "revision_hash" =>
            current_head_revision_hash(repository.id) |> Base.encode16(case: :lower),
          "session_id" => session.session_id,
          "reason" => "Conflicts detected while landing session",
          "paths" => paths
        }

        metadata =
          session.metadata
          |> normalize_metadata()
          |> Map.put("virtual_conflict", conflict)

        case Sessions.update_session(session, %{metadata: metadata}) do
          {:ok, conflicted} ->
            session_to_proto(conflicted, repository)

          {:error, changeset} ->
            {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
        end

      {:error, reason} ->
        {:error, invalid_status("Landing failed: #{inspect(reason)}")}
    end
  end

  defp session_to_proto(%Session{} = session, repository) do
    organization = repository.organization
    metadata = normalize_metadata(session.metadata)

    with {:ok, base_position} <- build_base_position(repository.id, metadata),
         {:ok, current_position} <-
           build_current_position(repository.id, metadata, session.status) do
      %V1.SessionInfo{
        session_id: session.session_id,
        repository: repository_ref(organization, repository),
        goal: session.goal,
        status: session_status(session),
        base_position: base_position,
        current_position: current_position,
        conversation:
          Enum.map(normalize_list(session.conversation), &conversation_event_from_map/1),
        decisions: Enum.map(normalize_list(session.decisions), &decision_event_from_map/1),
        changes: Enum.map(Sessions.list_session_changes(session), &file_operation_from_change/1),
        attribution: attribution_from_session(session),
        created_at_ms: datetime_ms(session.inserted_at),
        updated_at_ms: datetime_ms(session.updated_at),
        conflict: conflict_from_metadata(metadata)
      }
    end
  end

  defp build_base_position(repository_id, metadata) do
    tree_hash =
      decode_hash(Map.get(metadata, "base_revision_hash")) ||
        current_head_revision_hash(repository_id)

    {:ok, revision_proto(tree_hash)}
  end

  defp build_current_position(repository_id, metadata, "landed") do
    tree_hash =
      decode_hash(Map.get(metadata, "landing_revision_hash")) ||
        current_head_revision_hash(repository_id)

    {:ok, revision_proto(tree_hash)}
  end

  defp build_current_position(repository_id, _metadata, _status) do
    with {:ok, head, _etag} <- fetch_head(repository_id) do
      {:ok, revision_proto(head.tree_hash)}
    end
  end

  defp repository_ref(organization, repository) do
    %V1.RepositoryRef{
      organization_handle: organization.account.handle,
      repository_handle: repository.handle
    }
  end

  defp revision_proto(tree_hash) do
    %V1.Position{
      hash: tree_hash,
      at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp conflict_from_metadata(metadata) do
    case Map.get(metadata, "virtual_conflict") do
      %{} = conflict ->
        revision_hash =
          case Map.get(conflict, "revision_hash") do
            value when is_binary(value) ->
              case Base.decode16(value, case: :mixed) do
                {:ok, decoded} when byte_size(decoded) == 32 -> decoded
                _ -> <<>>
              end

            _ ->
              <<>>
          end

        %V1.SessionConflict{
          revision_hash: revision_hash,
          session_id: Map.get(conflict, "session_id", ""),
          reason: Map.get(conflict, "reason", ""),
          paths: Map.get(conflict, "paths", [])
        }

      _ ->
        nil
    end
  end

  defp conversation_event_from_map(%{} = value) do
    %V1.SessionEvent{
      role: Map.get(value, "role", "human"),
      kind: Map.get(value, "kind", "note"),
      text: Map.get(value, "text") || Map.get(value, "content") || "",
      metadata: decode_metadata(Map.get(value, "metadata")),
      at_ms: parse_integer(Map.get(value, "at_ms"))
    }
  end

  defp conversation_event_from_map(_value) do
    %V1.SessionEvent{}
  end

  defp decision_event_from_map(%{} = value) do
    text =
      case {Map.get(value, "decision"), Map.get(value, "reasoning")} do
        {decision, reasoning}
        when is_binary(decision) and is_binary(reasoning) and reasoning != "" ->
          decision <> "\n" <> reasoning

        {decision, _} when is_binary(decision) ->
          decision

        _ ->
          Map.get(value, "text", "")
      end

    %V1.SessionEvent{
      role: Map.get(value, "role", "agent"),
      kind: Map.get(value, "kind", "decision"),
      text: text,
      metadata: decode_metadata(Map.get(value, "metadata")),
      at_ms: parse_integer(Map.get(value, "at_ms"))
    }
  end

  defp decision_event_from_map(_value) do
    %V1.SessionEvent{kind: "decision"}
  end

  defp event_to_map(%V1.SessionEvent{} = event) do
    %{
      "role" => empty_to_nil(event.role) || "human",
      "kind" => empty_to_nil(event.kind) || "note",
      "text" => event.text,
      "metadata" => if(event.metadata not in [nil, <<>>], do: Base.encode64(event.metadata)),
      "at_ms" => if(event.at_ms > 0, do: event.at_ms, else: System.system_time(:millisecond))
    }
    |> drop_nil_values()
  end

  defp file_operation_from_change(change) do
    action =
      case change.change_type do
        "added" -> :ACTION_CREATE
        "modified" -> :ACTION_UPDATE
        "deleted" -> :ACTION_DELETE
        _ -> :ACTION_UNSPECIFIED
      end

    content =
      case load_change_content(change, []) do
        {:ok, loaded} when is_binary(loaded) -> loaded
        _ -> <<>>
      end

    content_hash =
      if content == <<>> do
        ""
      else
        :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      end

    %V1.FileOperation{
      action: action,
      path: change.file_path,
      content: content,
      content_hash: content_hash
    }
  end

  defp attribution_from_session(session) do
    metadata = normalize_metadata(session.metadata)

    actor_kind =
      case Map.get(metadata, "contributor_type") do
        "ai" -> "agent"
        "mixed" -> "agent"
        _ -> "user"
      end

    %V1.AgentAttribution{
      actor_kind: actor_kind,
      actor_id: session.user_id,
      model_id: Map.get(metadata, "model_id", ""),
      tool_name: Map.get(metadata, "tool_name", ""),
      tool_version: Map.get(metadata, "tool_version", "")
    }
  end

  defp append_decisions(%Session{} = session, decisions) do
    decision_events =
      Enum.map(decisions, fn event ->
        %{
          "role" => empty_to_nil(event.role) || "agent",
          "kind" => empty_to_nil(event.kind) || "decision",
          "text" => event.text,
          "metadata" => if(event.metadata not in [nil, <<>>], do: Base.encode64(event.metadata)),
          "at_ms" => if(event.at_ms > 0, do: event.at_ms, else: System.system_time(:millisecond))
        }
        |> drop_nil_values()
      end)

    if decision_events == [] do
      {:ok, session}
    else
      updated = normalize_list(session.decisions) ++ decision_events
      Sessions.update_session(session, %{decisions: updated})
    end
  end

  defp operation_to_change_payloads(%V1.FileOperation{} = operation, session) do
    content = maybe_content(operation.content)

    case operation.action do
      :ACTION_CREATE ->
        if is_binary(content) do
          {:ok, [%{"path" => operation.path, "content" => content, "change_type" => "added"}]}
        else
          {:error, invalid_status("operation.content is required for create.")}
        end

      :ACTION_UPDATE ->
        if is_binary(content) do
          {:ok, [%{"path" => operation.path, "content" => content, "change_type" => "modified"}]}
        else
          {:error, invalid_status("operation.content is required for update.")}
        end

      :ACTION_DELETE ->
        {:ok, [%{"path" => operation.path, "change_type" => "deleted"}]}

      :ACTION_RENAME ->
        with :ok <- require_field(operation.old_path, "operation.old_path"),
             {:ok, rename_content} <- resolve_rename_content(content, session, operation.old_path) do
          {:ok,
           [
             %{"path" => operation.old_path, "change_type" => "deleted"},
             %{"path" => operation.path, "content" => rename_content, "change_type" => "added"}
           ]}
        end

      _ ->
        {:error, invalid_status("operation.action is required.")}
    end
  end

  defp resolve_rename_content(content, _session, _old_path) when is_binary(content),
    do: {:ok, content}

  defp resolve_rename_content(nil, session, old_path) do
    metadata = normalize_metadata(session.metadata)
    base_tree_hash = metadata["base_revision_hash"]

    with true <- is_binary(base_tree_hash),
         {:ok, decoded_hash} <- Base.decode64(base_tree_hash),
         {:ok, tree} <- Project.get_tree(session.repository_id, decoded_hash),
         blob_hash when is_binary(blob_hash) <- Map.get(tree, old_path),
         {:ok, content} <- Project.get_blob(session.repository_id, blob_hash) do
      {:ok, content}
    else
      _ ->
        {:error,
         invalid_status(
           "operation.content is required for rename when source content is unavailable."
         )}
    end
  end

  defp refresh_change_filter(%Session{} = session) do
    paths =
      session
      |> Sessions.list_session_changes()
      |> Enum.map(& &1.file_path)
      |> Enum.uniq()

    metadata =
      session.metadata
      |> normalize_metadata()
      |> Map.put("change_filter", Conflict.build_filter(paths))
      |> Map.delete("virtual_conflict")

    Sessions.update_session(session, %{metadata: metadata})
  end

  defp resolve_base_revision_hash(repository_id, nil) do
    with {:ok, head, _etag} <- fetch_head(repository_id) do
      {:ok, head.tree_hash}
    end
  end

  defp resolve_base_revision_hash(repository_id, %V1.Position{} = position) do
    if is_binary(position.hash) and byte_size(position.hash) == 32 do
      {:ok, position.hash}
    else
      resolve_base_revision_hash(repository_id, nil)
    end
  end

  defp ensure_session_active(%Session{status: "active"}), do: :ok

  defp ensure_session_active(%Session{status: "landed"}),
    do: {:error, conflict_status("Session already landed.")}

  defp ensure_session_active(%Session{status: "abandoned"}),
    do: {:error, conflict_status("Session is abandoned.")}

  defp ensure_session_active(_session), do: {:error, conflict_status("Session is not active.")}

  defp load_writable_session(session_id, user) do
    with %Session{} = session <- Sessions.get_session_by_session_id(session_id),
         repository = Repositories.get_repository_with_organization(session.repository_id),
         true <- Accounts.user_in_organization?(user, repository.organization.id) do
      {:ok, session, repository}
    else
      nil -> {:error, not_found_status("Session not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  defp load_readable_session(session_id, user) do
    with %Session{} = session <- Sessions.get_session_by_session_id(session_id),
         repository = Repositories.get_repository_with_organization(session.repository_id),
         true <- Accounts.user_in_organization?(user, repository.organization.id) do
      {:ok, session, repository}
    else
      nil -> {:error, not_found_status("Session not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
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

  defp fetch_head_by_revision_hash(repository_id, revision_hash)
       when is_binary(revision_hash) and byte_size(revision_hash) == 32 do
    case revision_hash do
      hash when hash == @zero_hash ->
        {:ok, Binary.new_head(0, @zero_hash), ""}

      _ ->
        case Project.get_tree(repository_id, revision_hash) do
          {:ok, _tree} ->
            {:ok, Binary.new_head(0, revision_hash),
             "revision-#{Base.encode16(revision_hash, case: :lower)}"}

          {:error, :not_found} ->
            {:error, not_found_status("Revision not found.")}

          {:error, _reason} ->
            {:error, internal_status("Failed to load revision tree.")}
        end
    end
  end

  defp fetch_head_by_revision_hash(_repository_id, _revision_hash),
    do: {:error, invalid_status("revision_hash is required.")}

  defp current_head_revision_hash(repository_id) do
    case fetch_head(repository_id) do
      {:ok, head, _etag} -> head.tree_hash
      _ -> Binary.zero_hash()
    end
  end

  defp load_change_content(%{content: content}, _opts) when is_binary(content), do: {:ok, content}

  defp load_change_content(%{storage_key: key}, opts) when is_binary(key),
    do: Storage.get(key, opts)

  defp load_change_content(_change, _opts), do: {:error, :missing_change_content}

  defp update_epoch_batch(%Session{} = session, epoch) when is_integer(epoch) and epoch > 0 do
    last_epoch = parse_integer(Map.get(session.metadata || %{}, "epoch_batch"))

    if epoch <= last_epoch do
      {:error, conflict_status("Epoch already processed.")}
    else
      metadata = Map.put(normalize_metadata(session.metadata), "epoch_batch", epoch)
      Sessions.update_session(session, %{metadata: metadata})
    end
  end

  defp update_epoch_batch(%Session{} = session, _epoch), do: {:ok, session}

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

  defp require_repository_ref(%V1.RepositoryRef{} = repository_ref) do
    with :ok <-
           require_field(repository_ref.organization_handle, "repository.organization_handle") do
      require_field(repository_ref.repository_handle, "repository.repository_handle")
    end
  end

  defp require_repository_ref(_), do: {:error, invalid_status("repository is required.")}

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

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_), do: %{}

  defp clear_conflict_metadata(metadata) do
    metadata
    |> normalize_metadata()
    |> Map.delete("virtual_conflict")
  end

  defp normalize_list(list) when is_list(list), do: list
  defp normalize_list(_), do: []

  defp drop_nil_values(%{} = map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp maybe_content(value) when is_binary(value) and byte_size(value) > 0 do
    if String.valid?(value), do: value
  end

  defp maybe_content(_value), do: nil

  defp decode_metadata(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> decoded
      :error -> <<>>
    end
  end

  defp decode_metadata(_value), do: <<>>

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp parse_integer(_), do: 0

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 and limit <= 500, do: limit
  defp normalize_limit(_limit), do: 20

  defp session_summary(%Session{} = session) do
    %V1.SessionSummary{
      id: session.session_id,
      goal: session.goal || "",
      author: session_author_handle(session),
      revision_hash: landing_revision_hash_from_session(session)
    }
  end

  defp session_author_handle(%Session{} = session) do
    case session do
      %{user: %{account: %{handle: handle}}} when is_binary(handle) and handle != "" -> handle
      _ -> ""
    end
  end

  defp maybe_filter_sessions_by_path(sessions, _repository_id, nil), do: sessions

  defp maybe_filter_sessions_by_path(sessions, _repository_id, path) do
    Enum.filter(sessions, fn session ->
      session
      |> Sessions.list_session_changes()
      |> Enum.map(& &1.file_path)
      |> path_matches_any?(path)
    end)
  end

  defp path_matches_any?(indexed_paths, query_path) do
    Enum.any?(indexed_paths, fn indexed_path ->
      indexed_path == query_path or
        String.starts_with?(indexed_path, query_path <> "/") or
        String.starts_with?(query_path, indexed_path <> "/")
    end)
  end

  defp landing_revision_hash_from_session(%Session{} = session) do
    case normalize_metadata(session.metadata) do
      %{"landing_revision_hash" => value} ->
        decode_hash(value) || Binary.zero_hash()

      _ ->
        Binary.zero_hash()
    end
  end

  defp datetime_ms(nil), do: 0

  defp datetime_ms(%DateTime{} = timestamp) do
    DateTime.to_unix(timestamp, :millisecond)
  end

  defp datetime_ms(%NaiveDateTime{} = timestamp) do
    timestamp
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  defp session_status(%Session{} = session) do
    conflict = get_in(normalize_metadata(session.metadata), ["virtual_conflict"])

    cond do
      session.status == "landed" -> "landed"
      session.status == "abandoned" -> "abandoned"
      is_map(conflict) -> "conflict"
      true -> "active"
    end
  end

  defp decode_hash(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == 32 -> decoded
      _ -> nil
    end
  end

  defp decode_hash(_), do: nil

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
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

  defp conflict_status(message) do
    %RPCError{status: Status.failed_precondition(), message: message}
  end

  defp internal_status(message) do
    %RPCError{status: Status.internal(), message: message}
  end
end
