defmodule MicelioWeb.Api.V1.PromptRequestController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug, ["prompt_requests:read"] when action in [:index, :show]

  plug MicelioWeb.Plugs.ApiScopePlug,
       ["prompt_requests:write"] when action in [:create, :update, :close, :reopen]

  tags(["Prompt Requests"])

  operation(:index,
    summary: "List prompt requests",
    description: "Lists prompt requests for a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    security: [%{"bearer" => ["prompt_requests:read"]}],
    responses: %{
      200 => {"Prompt request list", "application/json", Schemas.PromptRequestList},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def index(conn, %{"org" => org_handle, "repo" => repo_handle}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      prompt_requests = PromptRequests.list_prompt_requests_for_repository(repository)
      json(conn, %{data: Enum.map(prompt_requests, &serialize_prompt_request/1)})
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:show,
    summary: "Get prompt request",
    description: "Gets a prompt request by number.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Prompt request number", required: true]
    ],
    security: [%{"bearer" => ["prompt_requests:read"]}],
    responses: %{
      200 => {"Prompt request", "application/json", Schemas.PromptRequest},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def show(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         %PromptRequests.PromptRequest{} = pr <-
           PromptRequests.get_prompt_request_by_number(repository, number) do
      json(conn, %{data: serialize_prompt_request(pr)})
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:create,
    summary: "Create prompt request",
    description: "Creates a new prompt request in a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    request_body:
      {"Prompt request params", "application/json", Schemas.CreatePromptRequestRequest},
    security: [%{"bearer" => ["prompt_requests:write"]}],
    responses: %{
      201 => {"Created prompt request", "application/json", Schemas.PromptRequest},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def create(conn, %{"org" => org_handle, "repo" => repo_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository) do
      attrs = Map.take(params, ["title", "description"])

      case PromptRequests.create_simple_prompt_request(attrs,
             repository: repository,
             user: user
           ) do
        {:ok, pr} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_prompt_request(pr)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:update,
    summary: "Update prompt request",
    description: "Updates a prompt request's title or description.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Prompt request number", required: true]
    ],
    request_body: {"Update params", "application/json", Schemas.UpdatePromptRequestRequest},
    security: [%{"bearer" => ["prompt_requests:write"]}],
    responses: %{
      200 => {"Updated prompt request", "application/json", Schemas.PromptRequest},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def update(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %PromptRequests.PromptRequest{} = pr <-
           PromptRequests.get_prompt_request_by_number(repository, number) do
      attrs = Map.take(params, ["title", "description"])

      case PromptRequests.update_prompt_request(pr, attrs) do
        {:ok, updated} ->
          json(conn, %{data: serialize_prompt_request(updated)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:close,
    summary: "Close prompt request",
    description: "Closes a prompt request.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Prompt request number", required: true]
    ],
    security: [%{"bearer" => ["prompt_requests:write"]}],
    responses: %{
      200 => {"Closed prompt request", "application/json", Schemas.PromptRequest},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def close(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %PromptRequests.PromptRequest{} = pr <-
           PromptRequests.get_prompt_request_by_number(repository, number) do
      case PromptRequests.close_prompt_request(pr) do
        {:ok, closed} ->
          json(conn, %{data: serialize_prompt_request(closed)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:reopen,
    summary: "Reopen prompt request",
    description: "Reopens a closed prompt request.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Prompt request number", required: true]
    ],
    security: [%{"bearer" => ["prompt_requests:write"]}],
    responses: %{
      200 => {"Reopened prompt request", "application/json", Schemas.PromptRequest},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def reopen(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %PromptRequests.PromptRequest{} = pr <-
           PromptRequests.get_prompt_request_by_number(repository, number) do
      case PromptRequests.reopen_prompt_request(pr) do
        {:ok, reopened} ->
          json(conn, %{data: serialize_prompt_request(reopened)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  defp serialize_prompt_request(pr) do
    %{
      id: pr.id,
      number: pr.number,
      title: pr.title,
      description: pr.description,
      status: pr.status,
      user: serialize_user(pr.user),
      inserted_at: Helpers.format_datetime(pr.inserted_at),
      updated_at: Helpers.format_datetime(pr.updated_at)
    }
  end

  defp serialize_user(nil), do: nil
  defp serialize_user(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_user(user), do: %{id: user.id, email: user.email}
end
