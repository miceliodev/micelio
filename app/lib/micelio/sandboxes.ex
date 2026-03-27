defmodule Micelio.Sandboxes do
  @moduledoc """
  Context for managing sandboxed coding agent environments.
  """

  alias Micelio.Sandboxes.DaytonaProvider
  alias Micelio.Sandboxes.DockerProvider

  @providers %{
    "docker" => DockerProvider,
    "daytona" => DaytonaProvider
  }

  @doc """
  Resolves a provider module by name.
  """
  def provider_for(name) when is_binary(name) do
    case Map.fetch(@providers, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_provider}
    end
  end

  @doc """
  Returns the default provider name for the current environment.
  """
  def default_provider do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:default_provider, "daytona")
  end

  @doc """
  Creates a workspace using the specified provider.
  """
  def create_workspace(provider_name, plan, opts \\ []) do
    with {:ok, provider} <- provider_for(provider_name) do
      provider.create_workspace(plan, opts)
    end
  end

  @doc """
  Destroys a workspace using the specified provider.
  """
  def destroy_workspace(provider_name, workspace_id) do
    with {:ok, provider} <- provider_for(provider_name) do
      provider.destroy_workspace(workspace_id)
    end
  end

  @doc """
  Returns the status of a workspace.
  """
  def workspace_status(provider_name, workspace_id) do
    with {:ok, provider} <- provider_for(provider_name) do
      provider.status(workspace_id)
    end
  end
end
