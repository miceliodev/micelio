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

  def account_breadcrumb_owner_label(_repository, account) do
    account.handle
  end

  def account_switcher_label(account) do
    account.handle
  end

  defp ensure_current_account(accounts, current_account) do
    if Enum.any?(accounts, &(&1.id == current_account.id)) do
      accounts
    else
      [current_account | accounts]
    end
  end
end
