defmodule Micelio.GRPC.Sessions.V1.SessionService.Server do
  use GRPC.Server, service: Micelio.GRPC.Sessions.V1.SessionService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Sessions.V1

  alias Micelio.GRPC.Sessions.V1.{
    CaptureSessionEventRequest,
    CaptureSessionEventResponse,
    GetSessionRequest,
    LandSessionRequest,
    ListSessionsRequest,
    SessionResponse,
    StartSessionRequest
  }

  alias Micelio.Mic.Binary
  alias Micelio.Mic.Landing
  alias Micelio.Notifications
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories
  alias Micelio.Security.SecretScanner
  alias Micelio.Sessions
  alias Micelio.Sessions.ChangeStore
  alias Micelio.Sessions.Session
  alias Micelio.Storage
  alias Micelio.Webhooks

  def start_session(%StartSessionRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         :ok <- require_field(request.session_id, "session_id"),
         :ok <- require_field(request.goal, "goal"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(organization.id, request.repository_handle),
         nil <- Sessions.get_session_by_session_id(request.session_id),
         {:ok, head} <- fetch_head(repository.id) do
      attrs = %{
        session_id: request.session_id,
        goal: request.goal,
        repository_id: repository.id,
        user_id: user.id,
        conversation: map_conversation(request.conversation),
        decisions: map_decisions(request.decisions),
        metadata:
          %{
            "organization_handle" => request.organization_handle,
            "repository_handle" => request.repository_handle,
            "base_position" => head.position,
            "base_tree_hash" => Base.encode64(head.tree_hash)
          }
          |> maybe_put_attribution("contributor_type", request.contributor_type)
          |> maybe_put_attribution("model_id", request.model_id)
          |> maybe_put_attribution("tool_name", request.tool_name)
          |> maybe_put_attribution("tool_version", request.tool_version)
      }

      case Sessions.create_session(attrs) do
        {:ok, session} ->
          %SessionResponse{session: session_to_proto(session, organization, repository)}

        {:error, changeset} ->
          {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
      end
    else
      %Session{} -> {:error, conflict_status("Session already exists.")}
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def land_session(%LandSessionRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         %Session{} = session <- Sessions.get_session_by_session_id(request.session_id),
         repository = Repositories.get_repository_with_organization(session.repository_id),
         true <- Accounts.user_in_organization?(user, repository.organization.id),
         true <- session.status == "active" do
      {:ok, updated_session} =
        Sessions.update_session(session, %{
          conversation: map_conversation(request.conversation, session.conversation),
          decisions: map_decisions(request.decisions, session.decisions)
        })

      session_for_landing =
        if Enum.empty?(request.files) do
          updated_session
        else
          case ChangeStore.store_session_changes(
                 updated_session,
                 file_change_payloads(request.files)
               ) do
            {:ok, session_with_filter, _stats} ->
              session_with_filter

            {:error, reason} ->
              {:error, invalid_status("Failed to store session changes: #{inspect(reason)}")}
          end
        end

      batch_epoch = request.epoch
      batch_finalize = request.finalize

      case session_for_landing do
        {:error, _} = error ->
          error

        %Session{} = updated_session ->
          case update_epoch_batch(updated_session, batch_epoch) do
            {:error, status} ->
              {:error, status}

            {:ok, session_with_epoch} ->
              if batch_epoch > 0 and not batch_finalize do
                %SessionResponse{
                  session:
                    session_to_proto(session_with_epoch, repository.organization, repository)
                }
              else
                case SecretScanner.scan_session_changes(session_with_epoch) do
                  :ok ->
                    case Landing.land_session(session_with_epoch) do
                      {:ok, landing} ->
                        {:ok, landed_session} =
                          Sessions.land_session(session_with_epoch, %{
                            landed_at: landing.landed_at,
                            metadata:
                              session_with_epoch.metadata
                              |> normalize_metadata()
                              |> Map.put("landing_position", landing.position)
                          })

                        Webhooks.dispatch_session_landed(
                          repository,
                          landed_session,
                          landing.position
                        )

                        Notifications.dispatch_session_landed(repository, landed_session)

                        %SessionResponse{
                          session:
                            session_to_proto(landed_session, repository.organization, repository)
                        }

                      {:error, {:conflicts, paths}} ->
                        {:error, conflict_status("Conflicts detected: #{Enum.join(paths, ", ")}")}

                      {:error, reason} ->
                        {:error, invalid_status("Landing failed: #{inspect(reason)}")}
                    end

                  {:error, info} ->
                    {:error, invalid_status(SecretScanner.format_scan_error(info))}
                end
              end
          end
      end
    else
      nil -> {:error, not_found_status("Session not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, status} -> {:error, status}
      _ -> {:error, conflict_status("Session is not active.")}
    end
  end

  def get_session(%GetSessionRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         %Session{} = session <- Sessions.get_session_by_session_id(request.session_id),
         repository = Repositories.get_repository_with_organization(session.repository_id),
         true <- Accounts.user_in_organization?(user, repository.organization.id) do
      %SessionResponse{session: session_to_proto(session, repository.organization, repository)}
    else
      nil -> {:error, not_found_status("Session not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, status} -> {:error, status}
    end
  end

  def list_sessions(%ListSessionsRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.repository_handle, "repository_handle"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(organization.id, request.repository_handle) do
      sessions =
        Sessions.list_sessions_for_repository(repository,
          status: normalize_status_filter(request.status)
        )

      # Apply path filter if specified
      filtered_sessions =
        case empty_to_nil(request.path) do
          nil ->
            sessions

          path ->
            filter_sessions_by_path(sessions, repository.id, path)
        end

      %V1.ListSessionsResponse{
        sessions: Enum.map(filtered_sessions, &session_to_proto(&1, organization, repository))
      }
    else
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def capture_session_event(%CaptureSessionEventRequest{} = request, stream) do
    with :ok <- require_field(request.session_id, "session_id"),
         :ok <- require_field(request.payload, "payload"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         %Session{} = session <- Sessions.get_session_by_session_id(request.session_id),
         repository = Repositories.get_repository_with_organization(session.repository_id),
         true <- Accounts.user_in_organization?(user, repository.organization.id) do
      opts = build_event_opts(request)

      case Sessions.capture_session_payload(session, request.payload, opts) do
        {:ok, %{event: event, storage_key: key}} ->
          case Jason.encode(event) do
            {:ok, json} ->
              %CaptureSessionEventResponse{storage_key: key, event_json: json}

            {:error, _} ->
              {:error, internal_status("Failed to encode event response.")}
          end

        {:error, reason} ->
          {:error, invalid_status("Failed to capture event: #{format_event_error(reason)}")}
      end
    else
      nil -> {:error, not_found_status("Session not found.")}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, status} -> {:error, status}
    end
  end

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_), do: %{}

  defp filter_sessions_by_path(sessions, repository_id, path) do
    alias Micelio.Mic.ConflictIndex

    # Get landing positions for sessions that touched this path
    matching_positions =
      sessions
      |> Enum.map(fn session ->
        case session.metadata do
          %{"landing_position" => pos} when is_integer(pos) -> pos
          %{"landing_position" => pos} when is_binary(pos) -> parse_integer(pos)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn position ->
        case ConflictIndex.load_path_index(repository_id, position) do
          {:ok, nil} -> false
          {:ok, paths} -> path in paths or path_matches_prefix?(path, paths)
          {:error, _} -> false
        end
      end)
      |> MapSet.new()

    Enum.filter(sessions, fn session ->
      case session.metadata do
        %{"landing_position" => pos} when is_integer(pos) ->
          MapSet.member?(matching_positions, pos)

        %{"landing_position" => pos} when is_binary(pos) ->
          MapSet.member?(matching_positions, parse_integer(pos))

        _ ->
          false
      end
    end)
  end

  defp path_matches_prefix?(query_path, indexed_paths) do
    # Also match if query path is a prefix (directory) or if indexed path is a prefix
    Enum.any?(indexed_paths, fn indexed_path ->
      String.starts_with?(indexed_path, query_path <> "/") or
        String.starts_with?(query_path, indexed_path <> "/")
    end)
  end

  defp session_to_proto(session, organization, repository) do
    landing_position =
      case session.metadata do
        %{"landing_position" => value} when is_integer(value) -> value
        %{"landing_position" => value} -> parse_integer(value)
        _ -> 0
      end

    %V1.Session{
      id: session.id,
      session_id: session.session_id,
      goal: session.goal,
      organization_handle: organization.account.handle,
      repository_handle: repository.handle,
      status: session.status,
      conversation_count: length(session.conversation || []),
      decisions_count: length(session.decisions || []),
      started_at: format_timestamp(session.started_at),
      landed_at: format_timestamp(session.landed_at),
      landing_position: landing_position,
      contributor_type: Session.contributor_type(session),
      model_id: Session.model_id(session) || "",
      tool_name: Session.tool_name(session) || "",
      tool_version: Session.tool_version(session) || ""
    }
  end

  defp map_conversation(conversation, fallback \\ []) do
    items =
      Enum.map(conversation, fn message ->
        %{"role" => empty_to_nil(message.role), "content" => empty_to_nil(message.content)}
      end)

    if items == [], do: fallback, else: items
  end

  defp map_decisions(decisions, fallback \\ []) do
    items =
      Enum.map(decisions, fn decision ->
        %{
          "decision" => empty_to_nil(decision.decision),
          "reasoning" => empty_to_nil(decision.reasoning)
        }
      end)

    if items == [], do: fallback, else: items
  end

  defp file_change_payloads(files) do
    require Logger

    Enum.map(files, fn file ->
      content = file.content
      change_type = empty_to_nil(file.change_type) || "modified"

      # Log files with nil content for debugging
      if is_nil(content) and change_type != "deleted" do
        Logger.warning(
          "Received file with nil content: path=#{inspect(file.path)}, change_type=#{inspect(change_type)}"
        )
      end

      %{
        "path" => file.path,
        "content" => content,
        "change_type" => change_type
      }
    end)
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp parse_integer(_), do: 0

  defp update_epoch_batch(%Session{} = session, epoch) when is_integer(epoch) and epoch > 0 do
    last_epoch = parse_integer(Map.get(session.metadata || %{}, "epoch_batch"))

    if epoch <= last_epoch do
      {:error, conflict_status("Epoch already processed.")}
    else
      metadata = Map.put(session.metadata || %{}, "epoch_batch", epoch)

      case Sessions.update_session(session, %{metadata: metadata}) do
        {:ok, updated_session} ->
          {:ok, updated_session}

        {:error, changeset} ->
          {:error, invalid_status("Invalid session: #{format_errors(changeset)}")}
      end
    end
  end

  defp update_epoch_batch(%Session{} = session, _epoch), do: {:ok, session}

  defp fetch_head(repository_id) do
    case Storage.get(head_key(repository_id)) do
      {:ok, content} ->
        case Binary.decode_head(content) do
          {:ok, head} -> {:ok, head}
          {:error, _} -> {:error, internal_status("Failed to decode head.")}
        end

      {:error, :not_found} ->
        {:ok, %{position: 0, tree_hash: Binary.zero_hash()}}

      {:error, _reason} ->
        {:error, internal_status("Failed to load head.")}
    end
  end

  defp head_key(repository_id), do: "projects/#{repository_id}/head"

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

  defp normalize_status_filter(value) do
    case empty_to_nil(value) do
      "all" -> nil
      other -> other
    end
  end

  defp build_event_opts(%CaptureSessionEventRequest{} = request) do
    stream = normalize_event_option(request.stream)
    format = normalize_event_option(request.format)

    []
    |> maybe_put_opt(:stream, stream)
    |> maybe_put_opt(:format, format)
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_attribution(map, _key, value) when value in [nil, ""], do: map

  defp maybe_put_attribution(map, key, value), do: Map.put(map, key, String.trim(value))

  defp normalize_event_option(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> empty_to_nil()
  end

  defp normalize_event_option(_value), do: nil

  defp format_event_error(%{index: index, reason: reason}),
    do: "invalid event at #{index}: #{format_event_error(reason)}"

  defp format_event_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp format_event_error(reason), do: inspect(reason)

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field} #{Enum.join(errors, ", ")}"
    end)
  end

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)
  defp conflict_status(message), do: rpc_error(Status.aborted(), message)
  defp internal_status(message), do: rpc_error(Status.internal(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
