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

        if forge_imported?(repository) do
          conn
          |> send_resp(404, "Not found")
          |> halt()
        else
          assign(conn, :selected_repository, repository)
        end

      _ ->
        assign(conn, :selected_repository, nil)
    end
  end

  defp forge_imported?(%{forge_host: host, forge_owner: owner, forge_repo: repo})
       when is_binary(host) and host != "" and is_binary(owner) and owner != "" and
              is_binary(repo) and repo != "" do
    true
  end

  defp forge_imported?(_), do: false
end
