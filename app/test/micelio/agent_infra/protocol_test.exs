defmodule Micelio.AgentInfra.ProtocolTest do
  use ExUnit.Case, async: true

  alias Micelio.AgentInfra.Protocol

  test "states returns the canonical lifecycle list" do
    assert Protocol.states() == [:starting, :running, :stopped, :terminated, :error]
  end

  test "normalize_status accepts atom state payloads" do
    payload = %{state: :running, hostname: "vm.local", ip_address: "10.0.0.1"}

    assert {:ok,
            %{
              state: :running,
              hostname: "vm.local",
              ip_address: "10.0.0.1",
              metadata: %{}
            }} = Protocol.normalize_status(payload)
  end

  test "normalize_status coerces string states and metadata" do
    payload = %{
      "state" => "starting",
      "hostname" => nil,
      "ip_address" => "192.168.1.10",
      "metadata" => %{"region" => "us-east-1"}
    }

    assert {:ok,
            %{
              state: :starting,
              hostname: nil,
              ip_address: "192.168.1.10",
              metadata: %{"region" => "us-east-1"}
            }} = Protocol.normalize_status(payload)
  end

  test "normalize_status normalizes tuple ip addresses and list hostnames" do
    payload = %{state: :running, hostname: ~c"vm.local", ip_address: {10, 0, 0, 5}}

    assert {:ok,
            %{
              state: :running,
              hostname: "vm.local",
              ip_address: "10.0.0.5",
              metadata: %{}
            }} = Protocol.normalize_status(payload)
  end

  test "normalize_status rejects unknown states" do
    assert {:error, :invalid_state} = Protocol.normalize_status(%{state: "paused"})
  end

  test "normalize_status rejects non-map payloads" do
    assert {:error, :invalid_status} = Protocol.normalize_status("invalid")
  end

  test "normalize_instance coerces provider and embeds normalized status" do
    payload = %{
      ref: "vm-123",
      status: %{state: :running, hostname: "host", ip_address: "10.0.0.2"},
      provider: :fly,
      metadata: %{"zone" => "iad"}
    }

    assert {:ok,
            %{
              ref: "vm-123",
              provider: "fly",
              metadata: %{"zone" => "iad"},
              status: %{
                state: :running,
                hostname: "host",
                ip_address: "10.0.0.2",
                metadata: %{}
              }
            }} = Protocol.normalize_instance(payload)
  end

  test "normalize_instance rejects missing references" do
    payload = %{status: %{state: :running}}

    assert {:error, :invalid_instance_ref} = Protocol.normalize_instance(payload)
  end

  test "normalize_instance rejects invalid status payloads" do
    payload = %{ref: "vm-123", status: "invalid"}

    assert {:error, :invalid_status} = Protocol.normalize_instance(payload)
  end

  test "normalize_instance rejects non-map payloads" do
    assert {:error, :invalid_instance} = Protocol.normalize_instance("invalid")
  end

  test "normalize_instances returns normalized instance lists" do
    payloads = [
      %{
        ref: "vm-123",
        status: %{state: :running, hostname: "host", ip_address: "10.0.0.2"},
        provider: :fly,
        metadata: %{"zone" => "iad"}
      },
      %{
        "ref" => "vm-456",
        "status" => %{"state" => "stopped", "hostname" => nil, "ip_address" => nil},
        "provider" => "aws",
        "metadata" => %{"region" => "us-east-1"}
      }
    ]

    assert {:ok, instances} = Protocol.normalize_instances(payloads)
    assert Enum.count(instances) == 2

    assert [
             %{
               ref: "vm-123",
               provider: "fly",
               status: %{state: :running},
               metadata: %{"zone" => "iad"}
             },
             %{
               ref: "vm-456",
               provider: "aws",
               status: %{state: :stopped},
               metadata: %{"region" => "us-east-1"}
             }
           ] = instances
  end

  test "normalize_instances reports the first invalid entry" do
    payloads = [
      %{ref: "vm-123", status: %{state: :running}},
      %{ref: nil, status: %{state: :running}}
    ]

    assert {:error, %{index: 1, reason: :invalid_instance_ref}} =
             Protocol.normalize_instances(payloads)
  end

  test "normalize_instances reports non-map entries" do
    payloads = [%{ref: "vm-123", status: %{state: :running}}, "invalid"]

    assert {:error, %{index: 1, reason: :invalid_instance}} =
             Protocol.normalize_instances(payloads)
  end

  test "normalize_instances handles nil and invalid inputs" do
    assert {:ok, []} = Protocol.normalize_instances(nil)
    assert {:error, :invalid_instances} = Protocol.normalize_instances(:invalid)
  end

  test "normalize_capabilities returns defaults when nil" do
    assert {:ok,
            %{
              cpu_cores: %{min: nil, max: nil},
              memory_mb: %{min: nil, max: nil},
              disk_gb: %{min: nil, max: nil},
              networks: [],
              volume_types: [],
              metadata: %{}
            }} = Protocol.normalize_capabilities(nil)
  end

  test "normalize_capabilities coerces ranges and lists" do
    payload = %{
      "cpu_cores" => %{"min" => "2", "max" => 8},
      "memory_mb" => %{"min" => 2048, "max" => "16384"},
      "disk_gb" => %{"min" => "10", "max" => "200"},
      "networks" => ["default", :private],
      "volume_types" => "ssd",
      "metadata" => %{"region" => "us-east-1"}
    }

    assert {:ok,
            %{
              cpu_cores: %{min: 2, max: 8},
              memory_mb: %{min: 2048, max: 16384},
              disk_gb: %{min: 10, max: 200},
              networks: ["default", "private"],
              volume_types: ["ssd"],
              metadata: %{"region" => "us-east-1"}
            }} = Protocol.normalize_capabilities(payload)
  end

  test "normalize_capabilities rejects non-map inputs" do
    assert {:error, :invalid_capabilities} = Protocol.normalize_capabilities(:invalid)
  end

  test "normalize_error coerces code, message, and retryable" do
    payload = %{
      code: :capacity_exhausted,
      message: "No capacity available",
      retryable: "true",
      metadata: %{"region" => "us-east-1"}
    }

    assert {:ok,
            %{
              code: "capacity_exhausted",
              message: "No capacity available",
              retryable: true,
              metadata: %{"region" => "us-east-1"}
            }} = Protocol.normalize_error(payload)
  end

  test "normalize_error trims string codes and defaults retryable" do
    payload = %{"code" => "  quota_exceeded  ", "message" => :rate_limited}

    assert {:ok,
            %{
              code: "quota_exceeded",
              message: "rate_limited",
              retryable: false,
              metadata: %{}
            }} = Protocol.normalize_error(payload)
  end

  test "normalize_error rejects missing codes" do
    assert {:error, :invalid_error_code} = Protocol.normalize_error(%{message: "missing code"})
  end

  test "normalize_error rejects blank codes" do
    assert {:error, :invalid_error_code} = Protocol.normalize_error(%{code: "  "})
  end

  test "normalize_error rejects non-map inputs" do
    assert {:error, :invalid_error} = Protocol.normalize_error("invalid")
  end
end
