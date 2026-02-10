defmodule Micelio.Errors.Capture do
  @moduledoc """
  Capture helpers for persisting errors with fingerprinting and deduplication.
  """

  import Ecto.Query, warn: false

  alias Micelio.Errors.Config
  alias Micelio.Errors.Error
  alias Micelio.Errors.Notifier
  alias Micelio.Errors.RateLimiter
  alias Micelio.Repo

  @stack_frames 5

  def capture_exception(exception, opts \\ []) do
    if Config.capture_enabled?(opts) do
      error_kind = Keyword.get(opts, :error_kind, :error)
      stacktrace = Keyword.get(opts, :stacktrace, [])
      normalized_exception = normalize_exception(error_kind, exception, stacktrace)
      message = Exception.message(normalized_exception)
      exception_module = exception_module(normalized_exception)

      capture(
        %{
          kind: Keyword.get(opts, :kind, :exception),
          message: message,
          stacktrace: format_stacktrace(stacktrace),
          severity: Keyword.get(opts, :severity, :error),
          source: Keyword.get(opts, :source),
          metadata: normalize_map(Keyword.get(opts, :metadata, %{})),
          context: normalize_map(Keyword.get(opts, :context, %{})),
          user_id: Keyword.get(opts, :user_id),
          repository_id: Keyword.get(opts, :repository_id)
        },
        stacktrace,
        Keyword.put_new(opts, :exception_module, exception_module)
      )
    else
      :ok
    end
  end

  def capture_message(message, severity, opts \\ []) when is_binary(message) do
    if Config.capture_enabled?(opts) do
      capture(
        %{
          kind: Keyword.get(opts, :kind, :exception),
          message: message,
          stacktrace: nil,
          severity: severity,
          source: Keyword.get(opts, :source),
          metadata: normalize_map(Keyword.get(opts, :metadata, %{})),
          context: normalize_map(Keyword.get(opts, :context, %{})),
          user_id: Keyword.get(opts, :user_id),
          repository_id: Keyword.get(opts, :repository_id)
        },
        [],
        opts
      )
    else
      :ok
    end
  end

  defp capture(attrs, stacktrace, opts) do
    opts = Keyword.put_new(opts, :async, Config.capture_async?(opts))
    now = Keyword.get(opts, :occurred_at, utc_now())
    exception_module = Keyword.get(opts, :exception_module)

    fingerprint =
      Keyword.get(
        opts,
        :fingerprint,
        build_fingerprint(attrs.kind, attrs.message, stacktrace, exception_module)
      )

    if RateLimiter.allow?(attrs.kind, opts) do
      if Keyword.get(opts, :async, true) do
        Task.Supervisor.start_child(Micelio.Errors.Supervisor, fn ->
          persist_capture(attrs, fingerprint, now, opts)
        end)

        :ok
      else
        persist_capture(attrs, fingerprint, now, opts)
      end
    else
      :ok
    end
  end

  defp persist_capture(attrs, fingerprint, now, opts) do
    if sampled_out?(fingerprint, opts) do
      :ok
    else
      dedupe_window_seconds =
        Keyword.get(opts, :dedupe_window_seconds, Config.dedupe_window_seconds(opts))

      cutoff =
        if is_integer(dedupe_window_seconds) and dedupe_window_seconds > 0 do
          DateTime.add(now, -dedupe_window_seconds, :second)
        end

      Repo.transaction(fn ->
        existing =
          if cutoff do
            Error
            |> where([error], error.fingerprint == ^fingerprint and error.last_seen_at >= ^cutoff)
            |> order_by([error], desc: error.last_seen_at)
            |> limit(1)
            |> Repo.one()
          end

        result =
          case existing do
            %Error{} = error ->
              error
              |> Error.changeset(%{
                occurrence_count: error.occurrence_count + 1,
                last_seen_at: now,
                occurred_at: now,
                message: attrs.message,
                stacktrace: attrs.stacktrace,
                severity: attrs.severity,
                metadata: attrs.metadata,
                context: attrs.context,
                user_id: attrs.user_id,
                repository_id: attrs.repository_id
              })
              |> Repo.update()

            nil ->
              %Error{}
              |> Error.changeset(%{
                fingerprint: fingerprint,
                kind: attrs.kind,
                message: attrs.message,
                stacktrace: attrs.stacktrace,
                severity: attrs.severity,
                metadata: attrs.metadata,
                context: attrs.context,
                occurred_at: now,
                occurrence_count: 1,
                first_seen_at: now,
                last_seen_at: now,
                user_id: attrs.user_id,
                repository_id: attrs.repository_id
              })
              |> Repo.insert()
          end

        emit_telemetry(attrs, fingerprint, result, existing != nil)
        {result, existing != nil}
      end)
      |> case do
        {:ok, {{:ok, %Error{} = error}, deduped?}} ->
          Notifier.maybe_notify(error, deduped?: deduped?, now: now)
          {:ok, error}

        {:ok, {{:error, reason}, _deduped?}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp emit_telemetry(attrs, fingerprint, result, deduped?) do
    measurements = %{count: 1}

    metadata = %{
      fingerprint: fingerprint,
      kind: attrs.kind,
      severity: attrs.severity,
      deduped: deduped?,
      source: attrs[:source]
    }

    :telemetry.execute([:micelio, :errors, :capture], measurements, metadata)
    result
  end

  defp normalize_exception(kind, reason, stacktrace) do
    Exception.normalize(kind, reason, stacktrace)
  rescue
    _ -> %RuntimeError{message: inspect(reason)}
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    Exception.format_stacktrace(stacktrace)
  end

  defp format_stacktrace(stacktrace) when is_binary(stacktrace), do: stacktrace
  defp format_stacktrace(_stacktrace), do: nil

  defp build_fingerprint(kind, message, stacktrace, exception_module) do
    normalized = normalize_message(message)
    stack = stacktrace_summary(stacktrace)
    module_name = format_exception_module(exception_module)
    payload = "#{kind}:#{module_name}:#{normalized}:#{stack}"

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
  end

  defp stacktrace_summary(stacktrace) when is_list(stacktrace) do
    stacktrace
    |> Enum.take(@stack_frames)
    |> Exception.format_stacktrace()
  end

  defp stacktrace_summary(stacktrace) when is_binary(stacktrace), do: stacktrace
  defp stacktrace_summary(_stacktrace), do: ""

  defp normalize_message(message) do
    message
    |> String.replace(
      ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
      ":uuid"
    )
    |> String.replace(~r/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?\b/, ":timestamp")
    |> String.replace(~r/\b\d+\b/, ":number")
  end

  defp exception_module(%{__struct__: module}), do: module
  defp exception_module(_exception), do: nil

  defp format_exception_module(nil), do: "unknown"
  defp format_exception_module(module) when is_atom(module), do: Atom.to_string(module)
  defp format_exception_module(module), do: to_string(module)

  defp normalize_map(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, nested}, acc ->
      normalized_key = normalize_key(key)

      case normalize_value(nested) do
        :skip -> acc
        normalized -> Map.put(acc, normalized_key, normalized)
      end
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)

  defp normalize_value(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) do
    value
  end

  defp normalize_value(value) when is_atom(value) do
    Atom.to_string(value)
  end

  defp normalize_value(value) when is_list(value) do
    value
    |> Enum.map(&normalize_value/1)
    |> Enum.reject(&(&1 == :skip))
  end

  defp normalize_value(%_{} = struct) do
    %{__struct__: inspect(struct.__struct__)}
  end

  defp normalize_value(value) when is_map(value) do
    normalize_map(value)
  end

  defp normalize_value(value), do: inspect(value)

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp sampled_out?(fingerprint, opts) do
    sample_after =
      Keyword.get(opts, :sampling_after_occurrences, Config.sampling_after_occurrences(opts))

    sample_rate = Keyword.get(opts, :sampling_rate, Config.sampling_rate(opts))

    if is_integer(sample_after) and sample_after > 0 and is_number(sample_rate) and
         sample_rate < 1 do
      total =
        Error
        |> where([error], error.fingerprint == ^fingerprint)
        |> select([error], sum(error.occurrence_count))
        |> Repo.one()

      count = total || 0

      if count >= sample_after do
        :rand.uniform() > sample_rate
      else
        false
      end
    else
      false
    end
  end
end
