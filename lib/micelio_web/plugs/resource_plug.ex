defmodule MicelioWeb.ResourcePlug do
  import Plug.Conn

  alias Micelio.Accounts
  alias Micelio.Repositories

  def init(opts) do
    opts
  end

  def call(%{params: %{"account" => account_handle}} = conn, :load_account) do
    account = Accounts.get_account_by_handle(account_handle)
    assign(conn, :selected_account, account)
  end

  def call(conn, :load_account), do: conn

  def call(conn, :load_repository) do
    case conn do
      %{params: %{"repository" => repository_handle}, assigns: %{selected_account: account}}
      when not is_nil(account) ->
        repository =
          if is_binary(account.organization_id) do
            Repositories.get_repository_by_handle(account.organization_id, repository_handle)
          end

        assign(conn, :selected_repository, repository)

      _ ->
        assign(conn, :selected_repository, nil)
    end
  end
end
