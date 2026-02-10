defmodule Micelio.AgentInfra.Provider do
  @moduledoc """
  Defines the provider abstraction for cloud-agnostic VM management.

  Providers implement a small, consistent surface area so Micelio can
  provision, inspect, and terminate agent VMs across multiple platforms.
  """

  alias Micelio.AgentInfra.Protocol
  alias Micelio.AgentInfra.ProvisioningRequest

  @typedoc "Opaque reference returned by a provider when a VM is provisioned."
  @type instance_ref :: term()

  @typedoc "Status response returned by providers for a running VM."
  @type status :: Protocol.status()

  @callback id() :: atom()
  @callback name() :: String.t()
  @callback capabilities() :: map()
  @callback validate_request(ProvisioningRequest.t()) :: :ok | {:error, term()}
  @callback validate_request(ProvisioningRequest.t(), keyword()) :: :ok | {:error, term()}
  @callback provision(ProvisioningRequest.t()) :: {:ok, instance_ref()} | {:error, term()}
  @callback provision(ProvisioningRequest.t(), keyword()) ::
              {:ok, instance_ref()} | {:error, term()}
  @callback status(instance_ref()) :: {:ok, status()} | {:error, term()}
  @callback status(instance_ref(), keyword()) :: {:ok, status()} | {:error, term()}
  @callback terminate(instance_ref()) :: :ok | {:error, term()}
  @callback terminate(instance_ref(), keyword()) :: :ok | {:error, term()}

  @optional_callbacks capabilities: 0,
                      validate_request: 1,
                      validate_request: 2,
                      provision: 2,
                      status: 2,
                      terminate: 2
end
