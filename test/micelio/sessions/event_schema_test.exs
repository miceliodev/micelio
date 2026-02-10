defmodule Micelio.Sessions.EventSchemaTest do
  use ExUnit.Case, async: true

  alias Micelio.Sessions.EventSchema

  test "schema exposes event type enum and is JSON encodable" do
    schema = EventSchema.schema()

    assert schema["properties"]["type"]["enum"] == EventSchema.event_types()
    assert is_binary(Jason.encode!(schema))
  end

  test "schema JSON file matches EventSchema.schema" do
    schema_path =
      Path.join([
        :code.priv_dir(:micelio),
        "static",
        "schemas",
        "session-event.json"
      ])

    schema_from_file = schema_path |> File.read!() |> Jason.decode!()

    assert schema_from_file == EventSchema.schema()
  end

  test "normalize_event accepts status payloads" do
    event = %{
      type: :status,
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "agent", id: "agent-1"},
      payload: %{state: "running", message: "Working", percent: 25}
    }

    assert {:ok, normalized} = EventSchema.normalize_event(event)
    assert normalized.type == "status"
    assert normalized.payload.state == "running"
    assert normalized.payload.percent == 25
    assert normalized.source.kind == "agent"
  end

  test "normalize_event accepts progress payloads with string inputs" do
    event = %{
      "type" => "progress",
      "timestamp" => ~U[2025-02-02 10:05:00Z],
      "source" => %{"kind" => "tool", "label" => "builder"},
      "payload" => %{"current" => "2", "total" => "5", "unit" => "steps"}
    }

    assert {:ok, normalized} = EventSchema.normalize_event(event)
    assert normalized.type == "progress"
    assert normalized.payload.current == 2
    assert normalized.payload.total == 5
    assert normalized.payload.unit == "steps"
    assert normalized.source.label == "builder"
  end

  test "normalize_event rejects unknown event types" do
    event = %{
      type: "nope",
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "agent"},
      payload: %{}
    }

    assert {:error, :invalid_event_type} = EventSchema.normalize_event(event)
  end

  test "normalize_event rejects output payloads without text" do
    event = %{
      type: "output",
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "agent"},
      payload: %{stream: "stdout"}
    }

    assert {:error, :invalid_output_payload} = EventSchema.normalize_event(event)
  end

  test "normalize_event applies output defaults for stream and format" do
    event = %{
      type: "output",
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "agent"},
      payload: %{text: "hi"}
    }

    assert {:ok, normalized} = EventSchema.normalize_event(event)
    assert normalized.payload.stream == "stdout"
    assert normalized.payload.format == "text"
  end

  test "normalize_event accepts artifact payloads with metadata" do
    event = %{
      type: :artifact,
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "tool", label: "archiver"},
      payload: %{
        kind: "file",
        name: "archive.tar.gz",
        uri: "s3://micelio/archive.tar.gz",
        size_bytes: 2048,
        metadata: %{"checksum" => "abc123"}
      }
    }

    assert {:ok, normalized} = EventSchema.normalize_event(event)
    assert normalized.payload.kind == "file"
    assert normalized.payload.size_bytes == 2048
    assert normalized.payload.metadata["checksum"] == "abc123"
  end

  test "normalize_event accepts unix timestamps and trims source kind" do
    event = %{
      type: "status",
      timestamp: 1_738_497_600,
      source: %{kind: " agent ", id: "agent-2"},
      payload: %{state: "completed"}
    }

    assert {:ok, normalized} = EventSchema.normalize_event(event)
    assert normalized.timestamp == "2025-02-02T12:00:00Z"
    assert normalized.source.kind == "agent"
  end

  test "normalize_events returns indexed errors" do
    events = [
      %{
        type: :status,
        timestamp: "2025-02-02T10:00:00Z",
        source: %{kind: "agent"},
        payload: %{state: "queued"}
      },
      %{
        type: "output",
        timestamp: "2025-02-02T10:01:00Z",
        source: %{kind: "agent"},
        payload: %{stream: "stdout"}
      }
    ]

    assert {:error, %{index: 1, reason: :invalid_output_payload}} =
             EventSchema.normalize_events(events)
  end

  test "normalize_event rejects invalid source kinds" do
    event = %{
      type: "status",
      timestamp: "2025-02-02T10:00:00Z",
      source: %{kind: "unknown"},
      payload: %{state: "queued"}
    }

    assert {:error, :invalid_source_kind} = EventSchema.normalize_event(event)
  end
end
