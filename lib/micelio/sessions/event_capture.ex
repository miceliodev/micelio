defmodule Micelio.Sessions.EventCapture do
  @moduledoc """
  Captures agent session events and persists them to storage.
  """

  alias Micelio.Sessions.EventSchema
  alias Micelio.Sessions.Session
  alias Micelio.Storage

  @default_source %{kind: "agent"}
  @ansi_regex ~r/\x1B\[[0-9;]*[A-Za-z]/

  @type capture_result :: {:ok, %{event: map(), storage_key: String.t()}} | {:error, term()}

  @doc """
  Captures a session event and writes it to session storage.
  """
  @spec capture_event(Session.t() | String.t(), map(), Keyword.t()) :: capture_result
  def capture_event(session_or_id, event, opts \\ []) do
    with {:ok, session_id} <- normalize_session_id(session_or_id),
         {:ok, event_map} <- normalize_event_input(event, opts),
         {:ok, normalized} <- EventSchema.normalize_event(event_map),
         {:ok, enriched} <- ensure_event_id(normalized),
         {:ok, json} <- Jason.encode(enriched),
         {:ok, key} <- Storage.put(event_storage_key(session_id, enriched), json, opts) do
      {:ok, %{event: enriched, storage_key: key}}
    else
      {:error, _reason} = error -> error
      error -> {:error, error}
    end
  end

  @doc """
  Captures raw output as a structured output event.
  """
  @spec capture_output(Session.t() | String.t(), String.t(), Keyword.t()) :: capture_result
  def capture_output(session_or_id, text, opts \\ [])

  def capture_output(session_or_id, text, opts) when is_binary(text) do
    stream = Keyword.get(opts, :stream, "stdout")
    format = Keyword.get(opts, :format, detect_output_format(text))

    event = %{
      type: "output",
      payload: %{text: text, stream: stream, format: format}
    }

    capture_event(session_or_id, event, opts)
  end

  def capture_output(_session_or_id, _text, _opts), do: {:error, :invalid_output}

  @doc """
  Captures a structured event or wraps raw output as an output event.
  """
  @spec capture_payload(Session.t() | String.t(), map() | String.t(), Keyword.t()) ::
          capture_result
  def capture_payload(session_or_id, payload, opts \\ [])

  def capture_payload(session_or_id, %{} = payload, opts) do
    capture_event(session_or_id, payload, opts)
  end

  def capture_payload(session_or_id, payload, opts) when is_binary(payload) do
    trimmed = String.trim(payload)

    case maybe_decode_event(trimmed) do
      {:ok, event} ->
        case capture_event(session_or_id, event, opts) do
          {:ok, _} = ok -> ok
          {:error, _reason} -> capture_output(session_or_id, payload, opts)
        end

      :error ->
        capture_output(session_or_id, payload, opts)
    end
  end

  def capture_payload(_session_or_id, _payload, _opts), do: {:error, :invalid_payload}

  @doc """
  Captures stdout output as a structured output event.
  """
  @spec capture_stdout(Session.t() | String.t(), String.t(), Keyword.t()) :: capture_result
  def capture_stdout(session_or_id, text, opts \\ []) do
    capture_output(session_or_id, text, Keyword.put_new(opts, :stream, "stdout"))
  end

  @doc """
  Captures stderr output as a structured output event.
  """
  @spec capture_stderr(Session.t() | String.t(), String.t(), Keyword.t()) :: capture_result
  def capture_stderr(session_or_id, text, opts \\ []) do
    capture_output(session_or_id, text, Keyword.put_new(opts, :stream, "stderr"))
  end

  defp normalize_session_id(%Session{session_id: session_id}) when is_binary(session_id),
    do: {:ok, session_id}

  defp normalize_session_id(session_id) when is_binary(session_id) and session_id != "",
    do: {:ok, session_id}

  defp normalize_session_id(_session_id), do: {:error, :invalid_session}

  defp normalize_event_input(%{} = event, opts) do
    default_timestamp = Keyword.get(opts, :timestamp) || DateTime.utc_now()
    default_source = Keyword.get(opts, :source, @default_source)

    event =
      event
      |> put_default(:timestamp, default_timestamp)
      |> put_default(:source, default_source)

    {:ok, event}
  end

  defp normalize_event_input(_event, _opts), do: {:error, :invalid_event}

  defp put_default(map, key, value) do
    if value == nil do
      map
    else
      if Map.has_key?(map, key) || Map.has_key?(map, Atom.to_string(key)) do
        map
      else
        Map.put(map, key, value)
      end
    end
  end

  defp ensure_event_id(%{id: id} = event) when is_binary(id) and id != "", do: {:ok, event}

  defp ensure_event_id(event) do
    {:ok, Map.put(event, :id, Ecto.UUID.generate())}
  end

  defp event_storage_key(session_id, %{timestamp: timestamp, id: id}) do
    unix_ms =
      case DateTime.from_iso8601(timestamp) do
        {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :millisecond)
        _ -> DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      end

    "sessions/#{session_id}/events/#{unix_ms}-#{id}.json"
  end

  defp detect_output_format(text) when is_binary(text) do
    if Regex.match?(@ansi_regex, text) do
      "ansi"
    else
      "text"
    end
  end

  defp maybe_decode_event(""), do: :error

  defp maybe_decode_event(payload) when is_binary(payload) do
    if String.starts_with?(payload, "{") do
      case Jason.decode(payload) do
        {:ok, %{} = event} -> {:ok, event}
        _ -> :error
      end
    else
      :error
    end
  end
end
