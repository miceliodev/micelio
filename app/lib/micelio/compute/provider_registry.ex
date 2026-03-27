defmodule Micelio.AgentInfra.ProviderRegistry do
  @moduledoc """
  Resolves provider identifiers to provider modules.

  Provider modules must implement `Micelio.AgentInfra.Provider`.
  """

  @type provider_id :: String.t() | atom()
  @type providers :: %{required(String.t()) => module()} | [{String.t(), module()}]

  @required_callbacks [id: 0, name: 0, provision: 1, status: 1, terminate: 1]

  @doc """
  Returns providers configured via application environment.
  """
  def providers do
    Application.get_env(:micelio, :agent_infra_providers, %{})
  end

  @doc """
  Resolves a provider id to its module.
  """
  @spec resolve(provider_id(), providers()) :: {:ok, module()} | {:error, atom()}
  def resolve(provider_id, providers \\ providers()) do
    provider_key = normalize_provider_id(provider_id)

    providers
    |> normalize_providers()
    |> Map.fetch(provider_key)
    |> case do
      {:ok, module} -> ensure_provider_module(module)
      :error -> {:error, :unknown_provider}
    end
  end

  defp normalize_provider_id(provider_id) when is_atom(provider_id) do
    Atom.to_string(provider_id)
  end

  defp normalize_provider_id(provider_id) when is_binary(provider_id), do: provider_id

  defp normalize_providers(providers) when is_map(providers), do: providers

  defp normalize_providers(providers) when is_list(providers) do
    Map.new(providers)
  end

  defp ensure_provider_module(module) do
    with true <- Code.ensure_loaded?(module),
         true <- implements_provider?(module) do
      {:ok, module}
    else
      false -> {:error, :invalid_provider}
    end
  end

  defp implements_provider?(module) do
    function_exported?(module, :__info__, 1) and
      Enum.all?(@required_callbacks, fn {callback, arity} ->
        function_exported?(module, callback, arity)
      end)
  end
end
