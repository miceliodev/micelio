defmodule Micelio.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false

  alias Micelio.Accounts.User
  alias Micelio.Repo
  alias Micelio.Repositories.Repository
  alias Micelio.Sessions.EventCapture
  alias Micelio.Sessions.OGSummary
  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  @doc """
  Returns the list of sessions for a repository.
  """
  def list_sessions_for_repository(%Repository{} = project, opts \\ []) do
    project
    |> build_repository_sessions_query(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a repository with user and change details preloaded.
  """
  def list_sessions_for_repository_with_details(%Repository{} = project, opts \\ []) do
    project
    |> build_repository_sessions_query(opts)
    |> preload([:changes, user: :account])
    |> Repo.all()
  end

  @doc """
  Counts sessions for a repository, optionally filtered by status.
  """
  def count_sessions_for_repository(%Repository{} = repository, opts \\ []) do
    status_filter = Keyword.get(opts, :status)

    query =
      Session
      |> where([s], s.repository_id == ^repository.id)

    query =
      if status_filter do
        where(query, [s], s.status == ^status_filter)
      else
        query
      end

    Repo.aggregate(query, :count)
  end

  @doc """
  Returns the list of sessions for a user.
  """
  def list_sessions_for_user(%User{} = user) do
    Session
    |> where([s], s.user_id == ^user.id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single session.
  """
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a session by session_id.
  """
  def get_session_by_session_id(session_id) do
    Repo.get_by(Session, session_id: session_id)
  end

  @doc """
  Gets a session by database ID or session_id.
  """
  def get_session_by_identifier(identifier) when is_binary(identifier) do
    case Repo.get(Session, identifier) do
      %Session{} = session -> session
      _ -> get_session_by_session_id(identifier)
    end
  end

  @doc """
  Gets a single session with preloaded associations.
  """
  def get_session_with_associations(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload([:user, :repository])
  end

  @doc """
  Gets a session by database ID or session_id with preloaded associations.
  """
  def get_session_with_associations_by_identifier(identifier) when is_binary(identifier) do
    # First try to find by session_id (which can be any string)
    result =
      Session
      |> where([s], s.session_id == ^identifier)
      |> Repo.one()

    # If not found by session_id and the identifier looks like a UUID, try by id
    result =
      if is_nil(result) and valid_uuid?(identifier) do
        Repo.get(Session, identifier)
      else
        result
      end

    case result do
      nil -> nil
      session -> Repo.preload(session, [:user, :repository])
    end
  end

  defp valid_uuid?(string) do
    case Ecto.UUID.cast(string) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Creates a session.
  """
  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lands a session (marks it as completed).
  """
  def land_session(%Session{} = session, attrs \\ %{}) do
    session
    |> Session.land_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Abandons a session (marks it as abandoned).
  """
  def abandon_session(%Session{} = session) do
    session
    |> Session.abandon_changeset()
    |> Repo.update()
  end

  @doc """
  Updates a session.
  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an LLM summary for agent Open Graph images and caches it on the session.
  """
  def get_or_generate_og_summary(%Session{} = session, changes \\ nil, opts \\ []) do
    changes = changes || list_session_changes(session)

    if changes == [] do
      {:ok, nil}
    else
      digest = OGSummary.digest(changes)
      metadata = session.metadata || %{}
      cached_summary = Map.get(metadata, "og_summary")
      cached_digest = Map.get(metadata, "og_summary_hash")

      if cached_digest == digest and is_binary(cached_summary) and cached_summary != "" do
        {:ok, cached_summary}
      else
        case OGSummary.generate(session, changes, opts) do
          {:ok, summary} when is_binary(summary) and summary != "" ->
            updated_metadata =
              metadata
              |> Map.put("og_summary", summary)
              |> Map.put("og_summary_hash", digest)

            case update_session(session, %{metadata: updated_metadata}) do
              {:ok, _} -> {:ok, summary}
              {:error, _} -> {:ok, summary}
            end

          _ ->
            {:ok, nil}
        end
      end
    end
  end

  @doc """
  Picks a session with changes and returns its OG summary.
  """
  def og_summary_for_sessions(sessions, opts \\ [])

  def og_summary_for_sessions(sessions, opts) when is_list(sessions) do
    sessions
    |> Enum.map(&extract_session/1)
    |> Enum.find(fn
      %Session{changes: [_ | _]} -> true
      _ -> false
    end)
    |> case do
      nil -> {:ok, nil}
      %Session{} = session -> get_or_generate_og_summary(session, session.changes, opts)
      _ -> {:ok, nil}
    end
  end

  defp extract_session(%Session{} = session), do: session
  defp extract_session(%{session: %Session{} = session}), do: session
  defp extract_session(session), do: session

  @doc """
  Deletes a session.
  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  ## Session Events

  @doc """
  Captures a structured session event and persists it to storage.
  """
  def capture_session_event(session_or_id, event, opts \\ []) do
    EventCapture.capture_event(session_or_id, event, opts)
  end

  @doc """
  Captures raw output as a structured session output event.
  """
  def capture_session_output(session_or_id, text, opts \\ []) do
    EventCapture.capture_output(session_or_id, text, opts)
  end

  @doc """
  Captures a structured event or wraps raw output as an output event.
  """
  def capture_session_payload(session_or_id, payload, opts \\ []) do
    EventCapture.capture_payload(session_or_id, payload, opts)
  end

  @doc """
  Captures stdout output as a structured session output event.
  """
  def capture_session_stdout(session_or_id, text, opts \\ []) do
    EventCapture.capture_stdout(session_or_id, text, opts)
  end

  @doc """
  Captures stderr output as a structured session output event.
  """
  def capture_session_stderr(session_or_id, text, opts \\ []) do
    EventCapture.capture_stderr(session_or_id, text, opts)
  end

  @doc """
  Lists session events from storage with optional filters.

  Options:
  - :types - list or comma-separated string of event types
  - :since - unix timestamp in milliseconds or DateTime
  - :after - storage key cursor
  - :limit - max number of events to return
  """
  def list_session_events(session_or_id, opts \\ []) do
    with {:ok, session_id} <- normalize_session_id(session_or_id),
         {:ok, keys} <- Storage.list(session_event_prefix(session_id), opts) do
      keys
      |> Enum.sort()
      |> filter_event_keys(opts, session_id)
      |> load_session_events(opts)
    end
  end

  defp normalize_session_id(%Session{session_id: session_id}) when is_binary(session_id),
    do: {:ok, session_id}

  defp normalize_session_id(session_id) when is_binary(session_id) and session_id != "",
    do: {:ok, session_id}

  defp normalize_session_id(_session_id), do: {:error, :invalid_session}

  defp session_event_prefix(session_id), do: "sessions/#{session_id}/events"

  defp filter_event_keys(keys, opts, session_id) do
    keys
    |> filter_after_key(Keyword.get(opts, :after), session_id)
    |> filter_since_key(Keyword.get(opts, :since))
    |> apply_limit(Keyword.get(opts, :limit))
  end

  defp filter_after_key(keys, nil, _session_id), do: keys

  defp filter_after_key(keys, after_key, session_id) when is_binary(after_key) do
    normalized =
      if String.starts_with?(after_key, "sessions/") do
        after_key
      else
        Path.join([session_event_prefix(session_id), after_key])
      end

    Enum.drop_while(keys, fn key -> key <= normalized end)
  end

  defp filter_after_key(keys, _after_key, _session_id), do: keys

  defp filter_since_key(keys, nil), do: keys

  defp filter_since_key(keys, %DateTime{} = since) do
    filter_since_key(keys, DateTime.to_unix(since, :millisecond))
  end

  defp filter_since_key(keys, since_ms) when is_integer(since_ms) and since_ms >= 0 do
    Enum.filter(keys, fn key ->
      case event_key_timestamp(key) do
        {:ok, timestamp} -> timestamp > since_ms
        _ -> true
      end
    end)
  end

  defp filter_since_key(keys, _since_ms), do: keys

  defp apply_limit(keys, limit) when is_integer(limit) and limit > 0 do
    Enum.take(keys, limit)
  end

  defp apply_limit(keys, _limit), do: keys

  defp event_key_timestamp(key) when is_binary(key) do
    with [_, filename] <- String.split(key, "/events/", parts: 2),
         [timestamp | _] <- String.split(filename, "-", parts: 2),
         {value, ""} <- Integer.parse(timestamp) do
      {:ok, value}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp load_session_events(keys, opts) do
    types = normalize_event_types(Keyword.get(opts, :types))

    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, acc} ->
      case Storage.get(key, opts) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"type" => type} = event} ->
              if type_allowed?(type, types) do
                {:cont, {:ok, [%{storage_key: key, event: event, json: json} | acc]}}
              else
                {:cont, {:ok, acc}}
              end

            _ ->
              {:cont, {:ok, acc}}
          end

        {:error, :not_found} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp normalize_event_types(nil), do: nil

  defp normalize_event_types(types) when is_list(types) do
    types
    |> Enum.map(&normalize_type_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_event_types(types) when is_binary(types) do
    types
    |> String.split(",", trim: true)
    |> Enum.map(&normalize_type_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_event_types(_types), do: nil

  defp normalize_type_value(type) when is_atom(type),
    do: normalize_type_value(Atom.to_string(type))

  defp normalize_type_value(type) when is_binary(type), do: String.trim(type)
  defp normalize_type_value(_type), do: nil

  defp type_allowed?(_type, nil), do: true
  defp type_allowed?(_type, []), do: false
  defp type_allowed?(type, allowed), do: type in allowed

  ## Session Changes

  @doc """
  Gets a session with preloaded changes.
  """
  def get_session_with_changes(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload([{:user, :account}, :repository, :changes, :prompt_request])
  end

  @doc """
  Creates a session change.
  """
  def create_session_change(attrs \\ %{}) do
    %SessionChange{}
    |> SessionChange.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple session changes in a transaction.
  """
  def create_session_changes(changes_list) when is_list(changes_list) do
    require Logger

    Repo.transaction(fn ->
      Enum.map(changes_list, fn attrs ->
        case create_session_change(attrs) do
          {:ok, change} ->
            change

          {:error, changeset} ->
            Logger.error(
              "Failed to create session change for path #{inspect(attrs[:file_path] || attrs["file_path"])}: #{inspect(changeset.errors)}"
            )

            Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Lists all changes for a session.
  """
  def list_session_changes(%Session{} = session) do
    SessionChange
    |> where([c], c.session_id == ^session.id)
    |> order_by([c], asc: c.file_path)
    |> Repo.all()
  end

  @doc """
  Lists landed session changes for a file, ordered by landing time.
  """
  def list_landed_changes_for_file(repository_id, file_path)
      when is_binary(repository_id) and is_binary(file_path) do
    SessionChange
    |> join(:inner, [c], s in assoc(c, :session))
    |> where([c, s], s.repository_id == ^repository_id and s.status == "landed")
    |> where([c, _s], c.file_path == ^file_path)
    |> order_by([c, s], asc: s.landed_at, asc: c.inserted_at)
    |> preload([_c, s], session: [user: :account])
    |> Repo.all()
    |> Enum.map(fn change ->
      %{
        change_type: change.change_type,
        content: load_change_content(change),
        session: change.session
      }
    end)
  end

  @doc """
  Counts changes for a session, optionally by change type.
  """
  def count_session_changes(%Session{} = session, opts \\ []) do
    change_type = Keyword.get(opts, :change_type)

    query =
      SessionChange
      |> where([c], c.session_id == ^session.id)

    query =
      if change_type do
        where(query, [c], c.change_type == ^change_type)
      else
        query
      end

    Repo.aggregate(query, :count)
  end

  defp build_repository_sessions_query(%Repository{} = repository, opts) do
    status_filter = Keyword.get(opts, :status)
    sort = Keyword.get(opts, :sort, :newest)

    query =
      Session
      |> where([s], s.repository_id == ^repository.id)

    query =
      if status_filter && status_filter != "all" do
        where(query, [s], s.status == ^status_filter)
      else
        query
      end

    case sort do
      :oldest -> order_by(query, asc: :started_at)
      :status -> order_by(query, asc: :status, desc: :started_at)
      _ -> order_by(query, desc: :started_at)
    end
  end

  defp load_change_content(%SessionChange{change_type: "deleted"}), do: nil

  defp load_change_content(%SessionChange{content: content}) when is_binary(content), do: content

  defp load_change_content(%SessionChange{storage_key: key}) when is_binary(key) do
    case Storage.get(key) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp load_change_content(_change), do: nil

  @doc """
  Gets statistics about session changes.
  """
  def get_session_change_stats(%Session{} = session) do
    %{
      total: count_session_changes(session),
      added: count_session_changes(session, change_type: "added"),
      modified: count_session_changes(session, change_type: "modified"),
      deleted: count_session_changes(session, change_type: "deleted")
    }
  end

  ## Activity/Contribution Data

  @doc """
  Returns activity counts grouped by date for a user.
  Counts landed sessions per day over the specified number of weeks.
  Returns a map of Date => count.
  """
  @spec activity_counts_for_user(User.t(), non_neg_integer()) :: %{Date.t() => non_neg_integer()}
  def activity_counts_for_user(%User{} = user, weeks \\ 52) do
    today = Date.utc_today()
    start_date = Date.add(today, -(weeks * 7))

    Session
    |> where([s], s.user_id == ^user.id)
    |> where([s], s.status == "landed")
    |> where([s], not is_nil(s.landed_at))
    |> where([s], s.landed_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"))
    |> select([s], s.landed_at)
    |> Repo.all()
    |> Enum.group_by(&DateTime.to_date/1)
    |> Map.new(fn {date, sessions} -> {date, length(sessions)} end)
  end

  @doc """
  Returns activity counts grouped by date for a user on public repositories.
  Counts landed sessions per day over the specified number of weeks.
  Returns a map of Date => count.
  """
  @spec activity_counts_for_user_public(User.t(), non_neg_integer()) ::
          %{Date.t() => non_neg_integer()}
  def activity_counts_for_user_public(%User{} = user, weeks \\ 52) do
    today = Date.utc_today()
    start_date = Date.add(today, -(weeks * 7))

    Session
    |> join(:inner, [s], p in assoc(s, :repository))
    |> where([s, _p], s.user_id == ^user.id)
    |> where([s, _p], s.status == "landed")
    |> where([s, _p], not is_nil(s.landed_at))
    |> where([s, _p], s.landed_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"))
    |> where([_s, p], p.visibility == "public")
    |> select([s, _p], s.landed_at)
    |> Repo.all()
    |> Enum.group_by(&DateTime.to_date/1)
    |> Map.new(fn {date, sessions} -> {date, length(sessions)} end)
  end
end
