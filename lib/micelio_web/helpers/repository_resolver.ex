defmodule MicelioWeb.RepositoryResolver do
  @moduledoc """
  Resolves a repository from LiveView mount params.
  Accepts both internal params (%{"account" => ..., "repository" => ...})
  and forge params (%{"owner" => ..., "repo" => ...}).
  """

  alias Micelio.Repositories

  def resolve(params, socket_assigns) do
    current_user = socket_assigns[:current_user]

    case params do
      %{"owner" => owner, "repo" => repo} ->
        forge_host = socket_assigns[:forge_host]
        resolve_forge(current_user, forge_host, owner, repo)

      %{"account" => org_handle, "repository" => repository_handle} ->
        case Repositories.get_repository_for_user_by_handle(
               current_user,
               org_handle,
               repository_handle
             ) do
          {:ok, repository, _organization}
          when is_binary(repository.forge_host) and
                 repository.forge_host != "" ->
            {:error, :not_found}

          other ->
            other
        end

      _ ->
        {:error, :invalid_params}
    end
  end

  defp resolve_forge(user, forge_host, owner, repo) do
    case Repositories.get_repository_by_forge_reference(forge_host, owner, repo) do
      %{} = repository ->
        repository = Micelio.Repo.preload(repository, organization: :account)
        {:ok, repository, repository.organization}

      nil ->
        if user do
          case Repositories.get_or_create_repository_for_forge_reference(
                 user,
                 forge_host,
                 owner,
                 repo
               ) do
            {:ok, repository} ->
              repository = Micelio.Repo.preload(repository, organization: :account)
              {:ok, repository, repository.organization}

            error ->
              error
          end
        else
          {:error, :not_found}
        end
    end
  end
end
