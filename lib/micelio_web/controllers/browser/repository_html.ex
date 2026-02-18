defmodule MicelioWeb.Browser.RepositoryHTML do
  use MicelioWeb, :html

  embed_templates "repository_html/*"

  def breadcrumb_switcher_accounts(user_accounts, current_account) do
    user_accounts
    |> Enum.filter(& &1.organization_id)
    |> case do
      [] -> [current_account]
      accounts -> ensure_current_account(accounts, current_account)
    end
    |> Enum.uniq_by(& &1.id)
  end

  def account_breadcrumb_owner_label(repository, account) do
    owner = normalize_forge_value(repository.forge_owner)

    if owner do
      owner
    else
      account.handle
    end
  end

  def github_repository?(repository) do
    provider = normalize_forge_value(repository.forge_provider)
    host = normalize_forge_value(repository.forge_host)

    provider == "github" or host == "github.com"
  end

  def github_account?(account) do
    account_forge_provider(account) == "github"
  end

  def account_switcher_label(account) do
    case account_forge_owner(account) do
      nil -> account.handle
      owner -> owner
    end
  end

  defp account_forge_provider(account) do
    case normalize_forge_value(account.handle) do
      "github-" <> _rest -> "github"
      "gitlab-" <> _rest -> "gitlab"
      _ -> nil
    end
  end

  defp account_forge_owner(account) do
    case normalize_forge_value(account.handle) do
      "github-" <> owner -> normalize_forge_value(owner)
      "gitlab-" <> owner -> normalize_forge_value(owner)
      _ -> nil
    end
  end

  defp ensure_current_account(accounts, current_account) do
    if Enum.any?(accounts, &(&1.id == current_account.id)) do
      accounts
    else
      [current_account | accounts]
    end
  end

  defp normalize_forge_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_forge_value(_), do: nil
end
