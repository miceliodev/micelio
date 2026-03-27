defmodule Micelio.Forges do
  @moduledoc """
  External forge metadata resolution for mirrored repositories.
  """

  alias Micelio.Forges.GitHub
  alias Micelio.Forges.GitLab

  @providers %{
    "github.com" => {"github", GitHub},
    "gitlab.com" => {"gitlab", GitLab}
  }

  @doc """
  Resolves a provider name for a forge host.
  """
  def provider_for_host(host) when is_binary(host) do
    normalized =
      host
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@providers, normalized) do
      {:ok, {provider, _module}} -> {:ok, provider}
      :error -> {:error, :provider_not_supported}
    end
  end

  @doc """
  Fetches repository metadata from a supported forge.
  """
  def fetch_repository(provider, opts) when provider in ["github", "gitlab"] and is_list(opts) do
    {host, module} =
      Enum.find_value(@providers, fn {host, {known_provider, module}} ->
        if known_provider == provider, do: {host, module}
      end)

    owner = Keyword.fetch!(opts, :owner)
    repo = Keyword.fetch!(opts, :repo)

    case module.fetch_repository(owner, repo, opts) do
      {:ok, metadata} ->
        {:ok,
         metadata
         |> Map.put_new(:forge_provider, provider)
         |> Map.put_new(:forge_host, host)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
