defmodule Micelio.AgentInfra.SessionManagerTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra.SessionManager

  @plan_attrs %{
    provider: "firecracker",
    image: "micelio/agent-runner:latest",
    cpu_cores: 2,
    memory_mb: 2048,
    disk_gb: 20
  }

  test "normalize_session/1 accepts string state and request attributes" do
    created_at = DateTime.utc_now() |> DateTime.truncate(:second)

    session = %{
      "id" => "sess_123",
      "state" => "running",
      "request" => %{
        "purpose" => "validation",
        "workspace_ref" => "project:123",
        "command" => ["mix", "test"],
        "plan" => @plan_attrs
      },
      "created_at" => created_at,
      "metadata" => %{"origin" => "test"}
    }

    assert {:ok, normalized} = SessionManager.normalize_session(session)
    assert normalized.state == :running
    assert normalized.access == []
    assert normalized.created_at == created_at
    assert normalized.request.purpose == "validation"
  end

  test "normalize_session/1 rejects invalid state values" do
    session = %{
      id: "sess_123",
      state: "unknown",
      request: %{
        purpose: "agent",
        workspace_ref: "project:123",
        plan: @plan_attrs
      },
      created_at: DateTime.utc_now()
    }

    assert {:error, :invalid_state} = SessionManager.normalize_session(session)
  end

  test "normalize_session/1 normalizes access points with string types" do
    created_at = DateTime.utc_now() |> DateTime.truncate(:second)

    session = %{
      "id" => "sess_456",
      "state" => "running",
      "request" => %{
        "purpose" => "agent",
        "workspace_ref" => "project:456",
        "plan" => @plan_attrs
      },
      "access" => [
        %{
          "type" => "ssh",
          "uri" => "ssh://agent@host:2222",
          "metadata" => %{"port" => 2222}
        }
      ],
      "created_at" => created_at
    }

    assert {:ok, normalized} = SessionManager.normalize_session(session)

    assert [%{type: :ssh, uri: "ssh://agent@host:2222", metadata: %{"port" => 2222}}] =
             normalized.access
  end

  test "normalize_session/1 rejects invalid access type values" do
    session = %{
      id: "sess_789",
      state: :running,
      request: %{
        purpose: "agent",
        workspace_ref: "project:789",
        plan: @plan_attrs
      },
      access: [%{type: "ftp", uri: "ftp://host"}],
      created_at: DateTime.utc_now()
    }

    assert {:error, %{index: 0, reason: :invalid_access_type}} =
             SessionManager.normalize_session(session)
  end
end
