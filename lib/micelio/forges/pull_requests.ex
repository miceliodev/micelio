defmodule Micelio.Forges.PullRequests do
  @moduledoc false

  alias Micelio.Accounts
  alias Micelio.Accounts.User
  alias Micelio.Forges.GitHubPullRequests
  alias Micelio.Forges.GitLabPullRequests
  alias Micelio.Repositories.Repository

  @providers %{
    "github" => GitHubPullRequests,
    "gitlab" => GitLabPullRequests
  }

  def ensure_draft_pr(%Repository{} = repository, %User{} = user, opts \\ []) do
    with {:ok, provider_module} <- provider_module(repository.forge_provider),
         {:ok, access_token} <- oauth_access_token(user, repository.forge_provider) do
      provider_module.ensure_draft_pr(repository, access_token, opts)
    end
  end

  defp provider_module(provider) when is_binary(provider) do
    case Map.fetch(@providers, provider) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_forge_provider}
    end
  end

  defp provider_module(_provider), do: {:error, :unsupported_forge_provider}

  defp oauth_access_token(%User{} = user, "github") do
    identity = Accounts.get_oauth_identity_for_user(user, :github)
    extract_token(identity)
  end

  defp oauth_access_token(%User{} = user, "gitlab") do
    identity = Accounts.get_oauth_identity_for_user(user, :gitlab)
    extract_token(identity)
  end

  defp oauth_access_token(_user, _provider), do: {:error, :integration_required}

  defp extract_token(%{access_token_encrypted: token}) when is_binary(token) and token != "" do
    {:ok, token}
  end

  defp extract_token(_), do: {:error, :integration_required}
end
