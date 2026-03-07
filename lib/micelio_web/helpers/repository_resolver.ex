defmodule MicelioWeb.RepositoryResolver do
  @moduledoc """
  Resolves a repository from LiveView mount params.
  Uses internal params (%{"account" => ..., "repository" => ...}).
  """

  alias Micelio.Repositories

  def resolve(params, socket_assigns) do
    case params do
      %{"account" => org_handle, "repository" => repository_handle} ->
        Repositories.get_repository_for_user_by_handle(
          socket_assigns[:current_user],
          org_handle,
          repository_handle
        )

      _ ->
        {:error, :invalid_params}
    end
  end
end
