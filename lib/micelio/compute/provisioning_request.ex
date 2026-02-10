defmodule Micelio.AgentInfra.ProvisioningRequest do
  @moduledoc """
  Normalizes provisioning plans into provider-ready requests.
  """

  alias Micelio.AgentInfra.ProvisioningPlan
  alias Micelio.AgentInfra.SandboxProfile
  alias Micelio.AgentInfra.VolumeMount

  @enforce_keys [:provider, :image, :cpu_cores, :memory_mb, :disk_gb]
  defstruct [
    :provider,
    :image,
    :cpu_cores,
    :memory_mb,
    :disk_gb,
    :network,
    :ttl_seconds,
    :sandbox,
    volumes: []
  ]

  @type volume :: %{
          name: String.t(),
          type: String.t(),
          source: String.t(),
          target: String.t(),
          read_only: boolean()
        }

  @type t :: %__MODULE__{
          provider: String.t(),
          image: String.t(),
          cpu_cores: pos_integer(),
          memory_mb: pos_integer(),
          disk_gb: pos_integer(),
          network: String.t() | nil,
          ttl_seconds: pos_integer() | nil,
          sandbox: map(),
          volumes: [volume()]
        }

  @doc """
  Builds a provisioning request from a validated plan.
  """
  @spec from_plan(ProvisioningPlan.t()) :: t()
  def from_plan(%ProvisioningPlan{} = plan) do
    sandbox = plan.sandbox || SandboxProfile.default()

    %__MODULE__{
      provider: plan.provider,
      image: plan.image,
      cpu_cores: plan.cpu_cores,
      memory_mb: plan.memory_mb,
      disk_gb: plan.disk_gb,
      network: normalize_network(plan.network, sandbox),
      ttl_seconds: plan.ttl_seconds,
      sandbox: normalize_sandbox(sandbox),
      volumes: Enum.map(plan.volumes, &normalize_volume/1)
    }
  end

  defp normalize_volume(%VolumeMount{} = mount) do
    %{
      name: mount.name,
      type: mount.type,
      source: mount.source,
      target: mount.target,
      read_only: mount.access == "ro"
    }
  end

  defp normalize_sandbox(%SandboxProfile{} = profile) do
    SandboxProfile.to_request(profile)
  end

  defp normalize_sandbox(nil) do
    SandboxProfile.to_request(SandboxProfile.default())
  end

  defp normalize_network(nil, _sandbox), do: nil

  defp normalize_network(_network, %SandboxProfile{network_policy: "none"}) do
    nil
  end

  defp normalize_network(network, _sandbox), do: network
end
