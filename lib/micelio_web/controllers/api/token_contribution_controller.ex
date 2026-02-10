defmodule MicelioWeb.Api.TokenContributionController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.Authorization
  alias Micelio.Repositories

  def create(conn, %{
        "organization_handle" => organization_handle,
        "repository_handle" => repository_handle,
        "token_contribution" => token_contribution_params
      }) do
    with {:ok, user} <- fetch_user(conn),
         {:ok, repository} <- fetch_project(organization_handle, repository_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, contribution, pool} <-
           AITokens.contribute_tokens(repository, user, token_contribution_params) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          contribution: token_contribution_payload(contribution),
          token_pool: token_pool_payload(pool)
        }
      })
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to contribute tokens"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "token_contribution payload is required"})
  end

  defp fetch_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp fetch_project(organization_handle, repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(organization.id, repository_handle) do
      {:ok, repository}
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp token_contribution_payload(contribution) do
    %{
      id: contribution.id,
      repository_id: contribution.repository_id,
      user_id: contribution.user_id,
      amount: contribution.amount,
      inserted_at: format_datetime(contribution.inserted_at)
    }
  end

  defp token_pool_payload(pool) do
    %{
      id: pool.id,
      repository_id: pool.repository_id,
      balance: pool.balance,
      reserved: pool.reserved,
      inserted_at: format_datetime(pool.inserted_at),
      updated_at: format_datetime(pool.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
