defmodule Micelio.AgentInfra.SessionRequestTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra
  alias Micelio.AgentInfra.SessionRequest

  @plan_attrs %{
    provider: "firecracker",
    image: "micelio/agent-runner:latest",
    cpu_cores: 2,
    memory_mb: 2048,
    disk_gb: 20
  }

  test "build_session_request/1 validates session request attributes" do
    attrs = %{
      purpose: "validation",
      workspace_ref: "project:123",
      command: ["mix", "test"],
      working_dir: "/workspace",
      env: %{"MIX_ENV" => "test"},
      plan: @plan_attrs
    }

    assert {:ok, %SessionRequest{} = request} = AgentInfra.build_session_request(attrs)
    assert request.command == ["mix", "test"]
    assert request.plan.provider == "firecracker"
  end

  test "build_session_request/1 rejects non-absolute working_dir" do
    attrs = %{
      purpose: "agent",
      workspace_ref: "project:123",
      working_dir: "workspace",
      plan: @plan_attrs
    }

    assert {:error, changeset} = AgentInfra.build_session_request(attrs)
    assert "must be an absolute path" in errors_on(changeset).working_dir
  end

  test "build_session_request/1 drops empty command segments" do
    attrs = %{
      purpose: "agent",
      workspace_ref: "project:123",
      command: ["", "mix"],
      plan: @plan_attrs
    }

    assert {:ok, request} = AgentInfra.build_session_request(attrs)
    assert request.command == ["mix"]
  end
end
