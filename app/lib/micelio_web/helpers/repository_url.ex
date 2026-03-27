defmodule MicelioWeb.RepositoryURL do
  @moduledoc """
  Computes canonical URL base paths for repositories.
  Always uses the internal Micelio namespace (`/account/repo`).
  """

  def base_path(%{organization: %{account: %{handle: account_handle}}, handle: repo_handle}) do
    "/#{account_handle}/#{repo_handle}"
  end

  def base_path(repository, organization) do
    "/#{organization.account.handle}/#{repository.handle}"
  end
end
