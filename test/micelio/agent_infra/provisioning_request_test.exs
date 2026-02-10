defmodule Micelio.AgentInfra.ProvisioningRequestTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra
  alias Micelio.AgentInfra.ProvisioningPlan
  alias Micelio.AgentInfra.ProvisioningRequest

  test "from_plan/1 normalizes volume read_only values" do
    attrs = %{
      provider: "firecracker",
      image: "micelio/agent-runner:latest",
      cpu_cores: 4,
      memory_mb: 4096,
      disk_gb: 50,
      network: "isolated",
      ttl_seconds: 900,
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace",
          access: "ro"
        },
        %{
          name: "cache",
          source: "/var/lib/micelio/cache",
          target: "/workspace/cache",
          type: "bind",
          access: "rw"
        }
      ]
    }

    assert {:ok, plan} = AgentInfra.build_plan(attrs)
    request = ProvisioningRequest.from_plan(plan)

    assert %ProvisioningRequest{
             provider: "firecracker",
             image: "micelio/agent-runner:latest",
             cpu_cores: 4,
             memory_mb: 4096,
             disk_gb: 50,
             network: "isolated",
             ttl_seconds: 900
           } = request

    assert request.volumes == [
             %{
               name: "workspace",
               type: "volume",
               source: "agent-workspace",
               target: "/workspace",
               read_only: true
             },
             %{
               name: "cache",
               type: "bind",
               source: "/var/lib/micelio/cache",
               target: "/workspace/cache",
               read_only: false
             }
           ]

    assert request.sandbox == %{
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

  test "build_request/1 returns a request after validation" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 20,
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace"
        }
      ]
    }

    assert {:ok, %ProvisioningRequest{provider: "fly"}} = AgentInfra.build_request(attrs)
  end

  test "from_plan/1 applies a default sandbox when plan omits it" do
    plan = %ProvisioningPlan{
      provider: "firecracker",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 20,
      volumes: []
    }

    request = ProvisioningRequest.from_plan(plan)

    assert request.sandbox == %{
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

  test "from_plan/1 drops network when sandbox policy is none" do
    attrs = %{
      provider: "firecracker",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 20,
      network: "isolated",
      sandbox: %{
        network_policy: "none"
      }
    }

    assert {:ok, plan} = AgentInfra.build_plan(attrs)

    request = ProvisioningRequest.from_plan(plan)

    assert request.network == nil
    assert request.sandbox.network_policy == "none"
  end
end
