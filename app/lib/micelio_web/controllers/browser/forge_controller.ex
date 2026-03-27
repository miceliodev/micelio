defmodule MicelioWeb.Browser.ForgeController do
  use MicelioWeb, :controller

  alias Micelio.Repositories

  def show(conn, %{"owner" => owner, "repo" => repo} = params) do
    forge_host = Map.get(params, "forge_host") || List.first(conn.path_info)
    rest = Map.get(params, "rest", [])
    current_user = conn.assigns[:current_user]

    case resolve_repository(current_user, forge_host, owner, repo) do
      {:ok, repository} ->
        organization = repository.organization
        base = "/#{organization.account.handle}/#{repository.handle}"
        target = if rest == [], do: base, else: "#{base}/#{Enum.join(rest, "/")}"

        redirect(conn, to: target)

      {:error, :not_found} ->
        send_resp(conn, 404, "Not found")

      {:error, :integration_required} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "This repository requires installation access before sessions can start. Install the forge app first."
          )
        )
        |> redirect(to: ~p"/repositories")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Unable to load repository from forge right now."))
        |> redirect(to: ~p"/repositories")
    end
  end

  defp resolve_repository(user, forge_host, owner, repo) do
    case Repositories.get_repository_by_forge_reference(forge_host, owner, repo) do
      %{} = repository ->
        repository = Micelio.Repo.preload(repository, organization: :account)
        {:ok, repository}

      nil ->
        if user do
          Repositories.get_or_create_repository_for_forge_reference(
            user,
            forge_host,
            owner,
            repo
          )
        else
          {:error, :not_found}
        end
    end
  end
end
