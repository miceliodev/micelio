defmodule Micelio.AgentInfra.ProviderRegistryTest do
  use ExUnit.Case, async: true

  alias Micelio.AgentInfra.ProviderRegistry

  defmodule TestProvider do
    @behaviour Micelio.AgentInfra.Provider

    @impl true
    def id, do: :test_provider

    @impl true
    def name, do: "Test Provider"

    @impl true
    def provision(_request), do: {:ok, :ref}

    @impl true
    def status(_ref), do: {:ok, %{state: :running, hostname: nil, ip_address: nil, metadata: %{}}}

    @impl true
    def terminate(_ref), do: :ok
  end

  defmodule InvalidProvider do
    def id, do: :invalid
  end

  test "resolves providers from a map" do
    providers = %{"test_provider" => TestProvider}

    assert {:ok, TestProvider} = ProviderRegistry.resolve("test_provider", providers)
  end

  test "resolves providers from a list and accepts atoms" do
    providers = [{"test_provider", TestProvider}]

    assert {:ok, TestProvider} = ProviderRegistry.resolve(:test_provider, providers)
  end

  test "returns error for unknown provider" do
    assert {:error, :unknown_provider} = ProviderRegistry.resolve("missing", %{})
  end

  test "returns error for invalid provider modules" do
    providers = %{"invalid" => InvalidProvider}

    assert {:error, :invalid_provider} = ProviderRegistry.resolve("invalid", providers)
  end
end
