defmodule Micelio.Sessions.EventSchema do
  @moduledoc """
  JSON schema and normalization helpers for agent session events.
  """

  @event_types ["status", "progress", "output", "error", "artifact"]
  @source_kinds ["agent", "tool", "system", "user"]
  @status_states ["queued", "running", "waiting", "completed", "failed", "canceled"]
  @artifact_kinds ["file", "image", "link", "dataset", "log"]
  @output_streams ["stdout", "stderr", "log"]
  @output_formats ["text", "markdown", "ansi"]

  @type event_type :: :status | :progress | :output | :error | :artifact
  @type source_kind :: :agent | :tool | :system | :user

  @doc "Returns the allowed session event types."
  def event_types, do: @event_types

  @doc "Returns the allowed session event source kinds."
  def source_kinds, do: @source_kinds

  @doc "Returns the allowed status event state values."
  def status_states, do: @status_states

  @doc "Returns the allowed artifact kinds."
  def artifact_kinds, do: @artifact_kinds

  @doc """
  Returns the JSON schema describing a session event.
  """
  def schema do
    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => "https://micelio.dev/schemas/session-event.json",
      "title" => "SessionEvent",
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["type", "timestamp", "source", "payload"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "type" => %{"type" => "string", "enum" => @event_types},
        "timestamp" => %{"type" => "string", "format" => "date-time"},
        "source" => source_schema(),
        "payload" => %{"type" => "object"}
      },
      "oneOf" => [
        event_variant_schema("status", status_payload_schema()),
        event_variant_schema("progress", progress_payload_schema()),
        event_variant_schema("output", output_payload_schema()),
        event_variant_schema("error", error_payload_schema()),
        event_variant_schema("artifact", artifact_payload_schema())
      ]
    }
  end

  @doc """
  Normalizes a session event payload into the canonical schema shape.
  """
  def normalize_event(%{} = event) do
    with {:ok, type} <- normalize_type(get_field(event, :type)),
         {:ok, timestamp} <- normalize_timestamp(get_field(event, :timestamp)),
         {:ok, source} <- normalize_source(get_field(event, :source)),
         {:ok, payload} <- normalize_payload(type, get_field(event, :payload)) do
      {:ok,
       %{
         id: normalize_optional_string(get_field(event, :id)),
         type: type,
         timestamp: timestamp,
         source: source,
         payload: payload
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  def normalize_event(_event), do: {:error, :invalid_event}

  @doc """
  Normalizes a list of session events.
  """
  def normalize_events(nil), do: {:ok, []}

  def normalize_events(events) when is_list(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {event, index}, {:ok, acc} ->
      case normalize_event(event) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, %{index: index, reason: reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  def normalize_events(_events), do: {:error, :invalid_events}

  defp source_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["kind"],
      "properties" => %{
        "kind" => %{"type" => "string", "enum" => @source_kinds},
        "id" => %{"type" => "string"},
        "label" => %{"type" => "string"},
        "metadata" => %{"type" => "object", "additionalProperties" => true}
      }
    }
  end

  defp event_variant_schema(type, payload_schema) do
    %{
      "type" => "object",
      "required" => ["type", "payload"],
      "properties" => %{
        "type" => %{"const" => type},
        "payload" => payload_schema
      }
    }
  end

  defp status_payload_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["state"],
      "properties" => %{
        "state" => %{"type" => "string", "enum" => @status_states},
        "message" => %{"type" => "string"},
        "detail" => %{"type" => "string"},
        "step" => %{"type" => "string"},
        "percent" => %{"type" => "number", "minimum" => 0, "maximum" => 100}
      }
    }
  end

  defp progress_payload_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["current", "total"],
      "properties" => %{
        "current" => %{"type" => "number", "minimum" => 0},
        "total" => %{"type" => "number", "minimum" => 0},
        "unit" => %{"type" => "string"},
        "message" => %{"type" => "string"},
        "percent" => %{"type" => "number", "minimum" => 0, "maximum" => 100}
      }
    }
  end

  defp output_payload_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["text"],
      "properties" => %{
        "text" => %{"type" => "string", "minLength" => 1},
        "stream" => %{"type" => "string", "enum" => @output_streams},
        "format" => %{"type" => "string", "enum" => @output_formats}
      }
    }
  end

  defp error_payload_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["message"],
      "properties" => %{
        "message" => %{"type" => "string", "minLength" => 1},
        "code" => %{"type" => "string"},
        "retryable" => %{"type" => "boolean"},
        "stacktrace" => %{"type" => "string"},
        "metadata" => %{"type" => "object", "additionalProperties" => true}
      }
    }
  end

  defp artifact_payload_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["kind", "name", "uri"],
      "properties" => %{
        "kind" => %{"type" => "string", "enum" => @artifact_kinds},
        "name" => %{"type" => "string"},
        "uri" => %{"type" => "string"},
        "content_type" => %{"type" => "string"},
        "size_bytes" => %{"type" => "integer", "minimum" => 0},
        "metadata" => %{"type" => "object", "additionalProperties" => true}
      }
    }
  end

  defp normalize_type(nil), do: {:error, :invalid_event_type}

  defp normalize_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> normalize_type()
  end

  defp normalize_type(type) when is_binary(type) do
    trimmed = String.trim(type)

    if trimmed in @event_types do
      {:ok, trimmed}
    else
      {:error, :invalid_event_type}
    end
  end

  defp normalize_type(_type), do: {:error, :invalid_event_type}

  defp normalize_timestamp(%DateTime{} = timestamp) do
    {:ok, DateTime.to_iso8601(timestamp)}
  end

  defp normalize_timestamp(%NaiveDateTime{} = timestamp) do
    timestamp
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
    |> then(&{:ok, &1})
  end

  defp normalize_timestamp(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix()
    |> case do
      {:ok, datetime} -> {:ok, DateTime.to_iso8601(datetime)}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp normalize_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_iso8601(datetime)}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp normalize_timestamp(_timestamp), do: {:error, :invalid_timestamp}

  defp normalize_source(%{} = source) do
    case normalize_source_kind(get_field(source, :kind)) do
      {:ok, kind} ->
        {:ok,
         %{
           kind: kind,
           id: normalize_optional_string(get_field(source, :id)),
           label: normalize_optional_string(get_field(source, :label)),
           metadata: normalize_metadata(get_field(source, :metadata))
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_source(_source), do: {:error, :invalid_source}

  defp normalize_source_kind(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> normalize_source_kind()
  end

  defp normalize_source_kind(kind) when is_binary(kind) do
    trimmed = String.trim(kind)

    if trimmed in @source_kinds do
      {:ok, trimmed}
    else
      {:error, :invalid_source_kind}
    end
  end

  defp normalize_source_kind(_kind), do: {:error, :invalid_source_kind}

  defp normalize_payload("status", %{} = payload) do
    with {:ok, state} <- normalize_status_state(get_field(payload, :state)),
         {:ok, percent} <- normalize_percent(get_field(payload, :percent)) do
      {:ok,
       %{
         state: state,
         message: normalize_optional_string(get_field(payload, :message)),
         detail: normalize_optional_string(get_field(payload, :detail)),
         step: normalize_optional_string(get_field(payload, :step)),
         percent: percent
       }}
    else
      {:error, _reason} -> {:error, :invalid_status_payload}
    end
  end

  defp normalize_payload("progress", %{} = payload) do
    with {:ok, current} <- normalize_non_negative_number(get_field(payload, :current)),
         {:ok, total} <- normalize_non_negative_number(get_field(payload, :total)),
         {:ok, percent} <- normalize_percent(get_field(payload, :percent)) do
      {:ok,
       %{
         current: current,
         total: total,
         unit: normalize_optional_string(get_field(payload, :unit)),
         message: normalize_optional_string(get_field(payload, :message)),
         percent: percent
       }}
    else
      {:error, _reason} -> {:error, :invalid_progress_payload}
    end
  end

  defp normalize_payload("output", %{} = payload) do
    with {:ok, text} <- normalize_required_string(get_field(payload, :text)),
         {:ok, stream} <-
           normalize_optional_enum(get_field(payload, :stream), @output_streams, "stdout"),
         {:ok, format} <-
           normalize_optional_enum(get_field(payload, :format), @output_formats, "text") do
      {:ok,
       %{
         text: text,
         stream: stream,
         format: format
       }}
    else
      {:error, _reason} -> {:error, :invalid_output_payload}
    end
  end

  defp normalize_payload("error", %{} = payload) do
    case normalize_required_string(get_field(payload, :message)) do
      {:ok, message} ->
        {:ok,
         %{
           message: message,
           code: normalize_optional_string(get_field(payload, :code)),
           retryable: normalize_boolean(get_field(payload, :retryable)),
           stacktrace: normalize_optional_string(get_field(payload, :stacktrace)),
           metadata: normalize_metadata(get_field(payload, :metadata))
         }}

      {:error, _reason} ->
        {:error, :invalid_error_payload}
    end
  end

  defp normalize_payload("artifact", %{} = payload) do
    with {:ok, kind} <- normalize_artifact_kind(get_field(payload, :kind)),
         {:ok, name} <- normalize_required_string(get_field(payload, :name)),
         {:ok, uri} <- normalize_required_string(get_field(payload, :uri)),
         {:ok, size_bytes} <- normalize_size_bytes(get_field(payload, :size_bytes)) do
      {:ok,
       %{
         kind: kind,
         name: name,
         uri: uri,
         content_type: normalize_optional_string(get_field(payload, :content_type)),
         size_bytes: size_bytes,
         metadata: normalize_metadata(get_field(payload, :metadata))
       }}
    else
      {:error, _reason} -> {:error, :invalid_artifact_payload}
    end
  end

  defp normalize_payload(_type, _payload), do: {:error, :invalid_payload}

  defp normalize_status_state(state) when is_atom(state) do
    state
    |> Atom.to_string()
    |> normalize_status_state()
  end

  defp normalize_status_state(state) when is_binary(state) do
    trimmed = String.trim(state)

    if trimmed in @status_states do
      {:ok, trimmed}
    else
      {:error, :invalid_status_state}
    end
  end

  defp normalize_status_state(_state), do: {:error, :invalid_status_state}

  defp normalize_artifact_kind(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> normalize_artifact_kind()
  end

  defp normalize_artifact_kind(kind) when is_binary(kind) do
    trimmed = String.trim(kind)

    if trimmed in @artifact_kinds do
      {:ok, trimmed}
    else
      {:error, :invalid_artifact_kind}
    end
  end

  defp normalize_artifact_kind(_kind), do: {:error, :invalid_artifact_kind}

  defp normalize_optional_enum(nil, _allowed, default), do: {:ok, default}

  defp normalize_optional_enum(value, allowed, default) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_optional_enum(allowed, default)
  end

  defp normalize_optional_enum(value, allowed, _default) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed in allowed do
      {:ok, trimmed}
    else
      {:error, :invalid_enum}
    end
  end

  defp normalize_optional_enum(_value, _allowed, _default), do: {:error, :invalid_enum}

  defp normalize_required_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:error, :invalid_string}, else: {:ok, trimmed}
  end

  defp normalize_required_string(_value), do: {:error, :invalid_string}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp normalize_percent(nil), do: {:ok, nil}

  defp normalize_percent(value) do
    with {:ok, number} <- normalize_number(value),
         true <- number >= 0 and number <= 100 do
      {:ok, number}
    else
      _ -> {:error, :invalid_percent}
    end
  end

  defp normalize_non_negative_number(value) do
    with {:ok, number} <- normalize_number(value),
         true <- number >= 0 do
      {:ok, number}
    else
      _ -> {:error, :invalid_number}
    end
  end

  defp normalize_number(value) when is_integer(value) or is_float(value), do: {:ok, value}

  defp normalize_number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> parse_float(value)
    end
  end

  defp normalize_number(_value), do: {:error, :invalid_number}

  defp parse_float(value) do
    case Float.parse(String.trim(value)) do
      {float, ""} -> {:ok, float}
      _ -> {:error, :invalid_number}
    end
  end

  defp normalize_size_bytes(nil), do: {:ok, nil}

  defp normalize_size_bytes(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_size_bytes(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> {:error, :invalid_size_bytes}
    end
  end

  defp normalize_size_bytes(_value), do: {:error, :invalid_size_bytes}

  defp normalize_boolean(value) when is_boolean(value), do: value

  defp normalize_boolean(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  defp normalize_boolean(_value), do: false

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
