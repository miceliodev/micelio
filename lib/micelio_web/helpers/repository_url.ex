defmodule MicelioWeb.RepositoryURL do
  @moduledoc """
  Computes canonical URL base paths for repositories.
  Forge-imported repos use `/github.com/owner/repo`, internal repos use `/account/repo`.
  """

  def base_path(%{forge_host: host, forge_owner: owner, forge_repo: repo})
      when is_binary(host) and host != "" and is_binary(owner) and owner != "" and is_binary(repo) and
             repo != "" do
    "/#{host}/#{owner}/#{repo}"
  end

  def base_path(%{organization: %{account: %{handle: account_handle}}, handle: repo_handle}) do
    "/#{account_handle}/#{repo_handle}"
  end

  def base_path(repository, organization) do
    if is_binary(repository.forge_host) and repository.forge_host != "" and
         is_binary(repository.forge_owner) and repository.forge_owner != "" and
         is_binary(repository.forge_repo) and repository.forge_repo != "" do
      "/#{repository.forge_host}/#{repository.forge_owner}/#{repository.forge_repo}"
    else
      "/#{organization.account.handle}/#{repository.handle}"
    end
  end
end
