defmodule MicelioWeb.Api.V1.RepositoryController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.Repositories
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug, ["repositories:read"] when action in [:index, :show]

  plug MicelioWeb.Plugs.ApiScopePlug,
       ["repositories:write"] when action in [:create, :update, :delete]

  tags(["Repositories"])

  operation(:index,
    summary: "List repositories",
    description: "Lists repositories for an organization.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true]
    ],
    security: [%{"bearer" => ["repositories:read"]}],
    responses: %{
      200 => {"Repository list", "application/json", Schemas.RepositoryList},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def index(conn, %{"org" => org_handle}) do
    with {:ok, _user} <- Helpers.fetch_user(conn),
         {:ok, organization} <- Helpers.fetch_organization(org_handle) do
      repositories = Repositories.list_repositories_for_organization(organization.id)

      json(conn, %{
        data: Enum.map(repositories, &serialize_repository(&1, org_handle))
      })
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:show,
    summary: "Get repository",
    description: "Gets a repository by handle.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      handle: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    security: [%{"bearer" => ["repositories:read"]}],
    responses: %{
      200 => {"Repository", "application/json", Schemas.Repository},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def show(conn, %{"org" => org_handle, "handle" => handle}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, handle),
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      json(conn, %{data: serialize_repository(repository, org_handle)})
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:create,
    summary: "Create repository",
    description: "Creates a new repository in an organization.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true]
    ],
    request_body: {"Repository params", "application/json", Schemas.CreateRepositoryRequest},
    security: [%{"bearer" => ["repositories:write"]}],
    responses: %{
      201 => {"Created repository", "application/json", Schemas.Repository},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def create(conn, %{"org" => org_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, organization} <- Helpers.fetch_organization(org_handle),
         :ok <- Authorization.authorize(:repository_create, user, organization) do
      repo_attrs =
        params
        |> Map.take(["handle", "name", "description", "visibility"])
        |> Map.put("organization_id", organization.id)

      case Repositories.create_repository(repo_attrs, user: user) do
        {:ok, repository} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_repository(repository, org_handle)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})

        {:error, reason} when is_binary(reason) ->
          Helpers.error_response(conn, :unprocessable_entity, "validation_error", reason)
      end
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:update,
    summary: "Update repository",
    description: "Updates a repository's metadata.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      handle: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    request_body: {"Update params", "application/json", Schemas.UpdateRepositoryRequest},
    security: [%{"bearer" => ["repositories:write"]}],
    responses: %{
      200 => {"Updated repository", "application/json", Schemas.Repository},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def update(conn, %{"org" => org_handle, "handle" => handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, handle),
         :ok <- Authorization.authorize(:repository_update, user, repository) do
      update_attrs = Map.take(params, ["name", "description", "visibility"])

      case Repositories.update_repository(repository, update_attrs, user: user) do
        {:ok, updated} ->
          json(conn, %{data: serialize_repository(updated, org_handle)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:delete,
    summary: "Delete repository",
    description: "Deletes a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      handle: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    security: [%{"bearer" => ["repositories:write"]}],
    responses: %{
      204 => "No content",
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def delete(conn, %{"org" => org_handle, "handle" => handle}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, handle),
         :ok <- Authorization.authorize(:repository_delete, user, repository),
         {:ok, _} <- Repositories.delete_repository(repository, user: user) do
      send_resp(conn, :no_content, "")
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  defp serialize_repository(repository, org_handle) do
    %{
      id: repository.id,
      handle: repository.handle,
      name: repository.name,
      description: repository.description,
      url: repository.url,
      visibility: repository.visibility,
      organization_handle: org_handle,
      inserted_at: Helpers.format_datetime(repository.inserted_at),
      updated_at: Helpers.format_datetime(repository.updated_at)
    }
  end
end
