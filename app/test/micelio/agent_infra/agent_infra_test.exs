defmodule Micelio.AgentInfra.ProviderTest do
  use ExUnit.Case, async: true

  alias Micelio.AgentInfra

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

  test "provider_module/2 resolves configured providers" do
    providers = %{"test_provider" => TestProvider}

    assert {:ok, TestProvider} = AgentInfra.provider_module("test_provider", providers)
  end

  test "provider_module/2 returns an error for unknown providers" do
    assert {:error, :unknown_provider} = AgentInfra.provider_module("missing", %{})
  end
end
