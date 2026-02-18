defmodule MicelioWeb.Plugs.ForgeResourcePlug do
  @moduledoc """
  Resolves forge URL parameters (owner, repo) into the internal account and repository,
  setting the same assigns that ResourcePlug would for standard routes.
  """
  import Plug.Conn

  alias Micelio.Repositories

  def init(opts), do: opts

  def call(%{params: %{"owner" => owner, "repo" => repo}} = conn, _opts) do
    forge_host = determine_forge_host(conn)
    current_user = conn.assigns[:current_user]

    case resolve_repository(current_user, forge_host, owner, repo) do
      {:ok, repository} ->
        account = repository.organization.account

        conn
        |> assign(:selected_account, account)
        |> assign(:selected_repository, repository)
        |> put_params(%{"account" => account.handle, "repository" => repository.handle})

      {:error, _reason} ->
        conn
        |> put_status(404)
        |> Phoenix.Controller.put_view(MicelioWeb.Browser.ErrorHTML)
        |> Phoenix.Controller.render("404.html")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp resolve_repository(user, forge_host, owner, repo) do
    case Repositories.get_repository_by_forge_reference(forge_host, owner, repo) do
      %{} = repository ->
        repository = Micelio.Repo.preload(repository, organization: :account)
        {:ok, repository}

      nil ->
        if user do
          Repositories.get_or_create_repository_for_forge_reference(user, forge_host, owner, repo)
        else
          {:error, :not_found}
        end
    end
  end

  defp determine_forge_host(conn) do
    case conn.path_info do
      ["github.com" | _] -> "github.com"
      ["gitlab.com" | _] -> "gitlab.com"
      _ -> "github.com"
    end
  end

  defp put_params(conn, new_params) do
    %{conn | params: Map.merge(conn.params, new_params)}
  end
end
