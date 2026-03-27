defmodule Micelio.AgentInfra.ProvisioningPlanTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra

  test "build_plan/1 returns a plan with normalized volume access" do
    attrs = %{
      provider: "firecracker",
      image: "micelio/agent-runner:latest",
      cpu_cores: 4,
      memory_mb: 4096,
      disk_gb: 50,
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace",
          read_only: true
        },
        %{
          name: "cache",
          source: "/var/lib/micelio/cache",
          target: "/workspace/cache",
          type: "bind",
          access: "read-write"
        }
      ]
    }

    assert {:ok, plan} = AgentInfra.build_plan(attrs)
    assert Enum.map(plan.volumes, & &1.access) == ["ro", "rw"]
    assert Enum.map(plan.volumes, & &1.type) == ["volume", "bind"]
  end

  test "build_plan/1 requires core provisioning fields" do
    assert {:error, changeset} = AgentInfra.build_plan(%{})

    assert "can't be blank" in errors_on(changeset).provider
    assert "can't be blank" in errors_on(changeset).image
    assert "can't be blank" in errors_on(changeset).cpu_cores
    assert "can't be blank" in errors_on(changeset).memory_mb
    assert "can't be blank" in errors_on(changeset).disk_gb
  end

  test "build_plan/1 validates mount paths for bind mounts and targets" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 30,
      volumes: [
        %{
          name: "invalid-bind",
          source: "relative/path",
          target: "workspace",
          type: "bind"
        }
      ]
    }

    assert {:error, changeset} = AgentInfra.build_plan(attrs)

    [volume_errors] = errors_on(changeset).volumes
    assert "must be an absolute path for bind mounts" in volume_errors.source
    assert "must be an absolute path" in volume_errors.target
  end

  test "build_plan/1 applies a default sandbox profile" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 30
    }

    assert {:ok, plan} = AgentInfra.build_plan(attrs)

    assert plan.sandbox == %Micelio.AgentInfra.SandboxProfile{
             isolation: "microvm",
             network_policy: "egress-only",
             filesystem_policy: "workspace-rw",
             run_as_user: "agent",
             seccomp_profile: "default",
             capabilities: [],
             allowlist_hosts: [],
             max_processes: 256,
             max_open_files: 1024
           }
  end

  test "build_plan/1 rejects rw volumes outside workspace with workspace-rw policy" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 30,
      volumes: [
        %{
          name: "cache",
          source: "/var/lib/micelio/cache",
          target: "/cache",
          type: "bind",
          access: "rw"
        }
      ]
    }

    assert {:error, changeset} = AgentInfra.build_plan(attrs)
    errors = errors_on(changeset)

    assert "read-write mounts must target /workspace when filesystem policy is workspace-rw" in errors.volumes
  end

  test "build_plan/1 rejects rw volumes with immutable filesystem policy" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 30,
      sandbox: %{
        filesystem_policy: "immutable"
      },
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace",
          access: "rw"
        }
      ]
    }

    assert {:error, changeset} = AgentInfra.build_plan(attrs)
    assert "must be read-only when filesystem policy is immutable" in errors_on(changeset).volumes
  end
end
