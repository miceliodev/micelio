defmodule MicelioWeb.Api.Helpers do
  @moduledoc """
  Shared helper functions for API controllers.
  """

  alias Micelio.Accounts
  alias Micelio.Repositories

  @doc """
  Extracts the current user from conn assigns.
  Returns `{:ok, user}` or `{:error, :unauthorized}`.
  """
  def fetch_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  @doc """
  Fetches an organization and repository by their handles.
  Returns `{:ok, organization, repository}` or `{:error, :not_found}`.
  """
  def fetch_repository(organization_handle, repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(organization.id, repository_handle) do
      {:ok, organization, repository}
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Fetches an organization by handle.
  Returns `{:ok, organization}` or `{:error, :not_found}`.
  """
  def fetch_organization(handle) do
    Accounts.get_organization_by_handle(handle)
  end

  @doc """
  Sends a JSON error response with the given status and error details.
  """
  def error_response(conn, status, error, description \\ nil) do
    body = %{error: error}
    body = if description, do: Map.put(body, :error_description, description), else: body

    conn
    |> Plug.Conn.put_status(status)
    |> Phoenix.Controller.json(body)
  end

  @doc """
  Handles common error tuples from controller `with` chains.
  """
  def handle_error(conn, {:error, :unauthorized}) do
    error_response(conn, :unauthorized, "unauthorized", "Authentication required")
  end

  def handle_error(conn, {:error, :not_found}) do
    error_response(conn, :not_found, "not_found", "Resource not found")
  end

  def handle_error(conn, {:error, :forbidden}) do
    error_response(conn, :forbidden, "forbidden", "Not authorized")
  end

  def handle_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = changeset_errors(changeset)

    conn
    |> Plug.Conn.put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(%{error: "validation_error", errors: errors})
  end

  @doc """
  Formats an Ecto changeset's errors into a map.
  """
  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  Formats a DateTime as ISO 8601 string.
  """
  def format_datetime(nil), do: nil
  def format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def format_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
end
