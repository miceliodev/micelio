defmodule Micelio.Errors.AgentReporter do
  @moduledoc false

  alias Micelio.Errors.Capture
  alias Micelio.Sessions
  alias Micelio.Sessions.Session

  @handler_id "micelio-errors-agent"
  @events [[:micelio, :agent, :crash]]
  @action_limit 10

  def attach do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def detach do
    :telemetry.detach(@handler_id)
  end

  def handle_event([:micelio, :agent, :crash], _measurements, metadata, _config) do
    reason = Map.get(metadata, :reason) || Map.get(metadata, :error) || "agent crash"
    stacktrace = Map.get(metadata, :stacktrace, [])

    capture_crash(reason,
      session: Map.get(metadata, :session),
      session_id: Map.get(metadata, :session_id),
      action_limit: Map.get(metadata, :action_limit),
      metadata: Map.get(metadata, :metadata, %{}),
      context: Map.get(metadata, :context, %{}),
      user_id: Map.get(metadata, :user_id),
      repository_id: Map.get(metadata, :repository_id),
      severity: Map.get(metadata, :severity),
      error_kind: Map.get(metadata, :kind),
      correlation_id: Map.get(metadata, :correlation_id),
      stacktrace: stacktrace,
      occurred_at: Map.get(metadata, :occurred_at),
      async: Map.get(metadata, :async)
    )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  def capture_crash(reason, opts \\ []) do
    session = resolve_session(opts)
    action_limit = Keyword.get(opts, :action_limit, @action_limit)
    {user_id, repository_id} = session_context(session, opts)
    metadata = build_metadata(session, action_limit, opts)
    context = Keyword.get(opts, :context, %{})
    severity = Keyword.get(opts, :severity, :error)
    stacktrace = Keyword.get(opts, :stacktrace, [])
    error_kind = Keyword.get(opts, :error_kind, :error)

    capture_opts =
      opts
      |> Keyword.drop([
        :session,
        :session_id,
        :session_ref,
        :action_limit,
        :metadata,
        :context,
        :error_kind
      ])
      |> Keyword.put(:kind, :agent_crash)
      |> Keyword.put(:metadata, metadata)
      |> Keyword.put(:context, context)
      |> Keyword.put(:user_id, user_id)
      |> Keyword.put(:repository_id, repository_id)
      |> Keyword.put(:source, :agent)

    cond do
      is_exception(reason) ->
        Capture.capture_exception(
          reason,
          Keyword.merge(capture_opts, stacktrace: stacktrace, error_kind: error_kind)
        )

      is_binary(reason) ->
        Capture.capture_message(reason, severity, capture_opts)

      true ->
        Capture.capture_message("Agent crash: #{inspect(reason)}", severity, capture_opts)
    end
  end

  defp resolve_session(opts) do
    case Keyword.get(opts, :session) do
      %Session{} = session ->
        session

      _ ->
        case Keyword.get(opts, :session_id) || Keyword.get(opts, :session_ref) do
          nil -> nil
          id -> Sessions.get_session(id) || Sessions.get_session_by_session_id(id)
        end
    end
  end

  defp session_context(%Session{} = session, opts) do
    {
      Keyword.get(opts, :user_id, session.user_id),
      Keyword.get(opts, :repository_id, session.repository_id)
    }
  end

  defp session_context(_session, opts) do
    {Keyword.get(opts, :user_id), Keyword.get(opts, :repository_id)}
  end

  defp build_metadata(%Session{} = session, action_limit, opts) do
    agent_id = Keyword.get(opts, :user_id, session.user_id)
    repository_id = Keyword.get(opts, :repository_id, session.repository_id)
    base = %{}
    base = maybe_put(base, "agent_id", agent_id)
    base = maybe_put(base, "agent_session_id", session.id)
    base = maybe_put(base, "agent_session_ref", session.session_id)
    base = maybe_put(base, "repository_id", repository_id)

    base =
      maybe_put(
        base,
        "correlation_id",
        Keyword.get(opts, :correlation_id) || session.session_id
      )

    actions = last_actions(session, action_limit)
    base = maybe_put(base, "last_actions", actions)

    Map.merge(base, Keyword.get(opts, :metadata, %{}))
  end

  defp build_metadata(_session, _action_limit, opts) do
    base = %{}
    base = maybe_put(base, "agent_id", Keyword.get(opts, :user_id))
    base = maybe_put(base, "repository_id", Keyword.get(opts, :repository_id))
    base = maybe_put(base, "correlation_id", Keyword.get(opts, :correlation_id))

    Map.merge(base, Keyword.get(opts, :metadata, %{}))
  end

  defp last_actions(%Session{} = session, limit) when is_integer(limit) and limit > 0 do
    conversation = session.conversation || []
    decisions = session.decisions || []

    actions =
      Enum.map(conversation, fn message ->
        %{"source" => "conversation", "payload" => message}
      end) ++
        Enum.map(decisions, fn decision ->
          %{"source" => "decision", "payload" => decision}
        end)

    Enum.take(actions, -limit)
  end

  defp last_actions(_session, _limit), do: []

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
