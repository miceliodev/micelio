defmodule MicelioWeb.Api.V1.PlanController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.Plans
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug,
       ["plans:read"] when action in [:index, :show, :create, :comments_index, :comments_create]

  plug MicelioWeb.Plugs.ApiScopePlug,
       ["plans:write"]
       when action in [
              :update,
              :close,
              :reopen,
              :start_session,
              :stop_session,
              :send_session_message
            ]

  tags(["Plans"])

  operation(:index,
    summary: "List plans",
    description: "Lists plans for a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    security: [%{"bearer" => ["plans:read"]}],
    responses: %{
      200 => {"Plan list", "application/json", Schemas.PlanList},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def index(conn, %{"org" => org_handle, "repo" => repo_handle}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      plans = Plans.list_plans_for_repository(repository)
      json(conn, %{data: Enum.map(plans, &serialize_plan/1)})
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:show,
    summary: "Get plan",
    description: "Gets a plan by number.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Plan number", required: true]
    ],
    security: [%{"bearer" => ["plans:read"]}],
    responses: %{
      200 => {"Plan", "application/json", Schemas.Plan},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def show(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         %Plans.Plan{} = pr <-
           Plans.get_plan_by_number(repository, number) do
      json(conn, %{data: serialize_plan(pr)})
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:create,
    summary: "Create plan",
    description: "Creates a new plan in a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    request_body: {"Plan params", "application/json", Schemas.CreatePlanRequest},
    security: [%{"bearer" => ["plans:read"]}],
    responses: %{
      201 => {"Created plan", "application/json", Schemas.Plan},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def create(conn, %{"org" => org_handle, "repo" => repo_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      attrs = Map.take(params, ["title", "description"])

      case Plans.create_simple_plan(attrs,
             repository: repository,
             user: user
           ) do
        {:ok, pr} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_plan(pr)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:update,
    summary: "Update plan",
    description: "Updates a plan's title or description.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Plan number", required: true]
    ],
    request_body: {"Update params", "application/json", Schemas.UpdatePlanRequest},
    security: [%{"bearer" => ["plans:write"]}],
    responses: %{
      200 => {"Updated plan", "application/json", Schemas.Plan},
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
         %Plans.Plan{} = pr <-
           Plans.get_plan_by_number(repository, number) do
      attrs = Map.take(params, ["title", "description"])

      case Plans.update_plan(pr, attrs) do
        {:ok, updated} ->
          json(conn, %{data: serialize_plan(updated)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:close,
    summary: "Close plan",
    description: "Closes a plan.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Plan number", required: true]
    ],
    security: [%{"bearer" => ["plans:write"]}],
    responses: %{
      200 => {"Closed plan", "application/json", Schemas.Plan},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def close(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %Plans.Plan{} = pr <-
           Plans.get_plan_by_number(repository, number) do
      case Plans.close_plan(pr) do
        {:ok, closed} ->
          json(conn, %{data: serialize_plan(closed)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:reopen,
    summary: "Reopen plan",
    description: "Reopens a closed plan.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true],
      number: [in: :path, type: :integer, description: "Plan number", required: true]
    ],
    security: [%{"bearer" => ["plans:write"]}],
    responses: %{
      200 => {"Reopened plan", "application/json", Schemas.Plan},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def reopen(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %Plans.Plan{} = pr <-
           Plans.get_plan_by_number(repository, number) do
      case Plans.reopen_plan(pr) do
        {:ok, reopened} ->
          json(conn, %{data: serialize_plan(reopened)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  def comments_index(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         %Plans.Plan{} = plan <- Plans.get_plan_by_number(repository, number) do
      comments = Plans.list_plan_comments(plan)
      json(conn, %{data: Enum.map(comments, &serialize_comment/1)})
    else
      nil ->
        Helpers.handle_error(conn, {:error, :not_found})

      {:error, :empty_comment} ->
        Helpers.error_response(conn, :unprocessable_entity, "validation_error")

      error ->
        Helpers.handle_error(conn, error)
    end
  end

  def comments_create(
        conn,
        %{"org" => org_handle, "repo" => repo_handle, "number" => number} = params
      ) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         %Plans.Plan{} = plan <- Plans.get_plan_by_number(repository, number),
         {:ok, comment} <- Plans.add_plan_comment(plan, user, params) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_comment(comment)})
    else
      nil ->
        Helpers.handle_error(conn, {:error, :not_found})

      {:error, :empty_comment} ->
        Helpers.error_response(conn, :unprocessable_entity, "validation_error")

      error ->
        Helpers.handle_error(conn, error)
    end
  end

  def start_session(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, organization, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %Plans.Plan{} = plan <- Plans.get_plan_by_number(repository, number),
         {:ok, updated_plan} <-
           Plans.start_agentic_session(plan,
             user: user,
             notify_pid: self(),
             account: organization.account
           ) do
      json(conn, %{data: serialize_plan(updated_plan)})
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  def stop_session(conn, %{"org" => org_handle, "repo" => repo_handle, "number" => number}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _organization, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %Plans.Plan{} = plan <- Plans.get_plan_by_number(repository, number),
         {:ok, updated_plan} <- Plans.stop_agentic_session(plan) do
      json(conn, %{data: serialize_plan(updated_plan)})
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  def send_session_message(
        conn,
        %{"org" => org_handle, "repo" => repo_handle, "number" => number} = params
      ) do
    content = String.trim(Map.get(params, "content", ""))

    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _organization, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         %Plans.Plan{} = plan <- Plans.get_plan_by_number(repository, number),
         false <- content == "",
         sequence = Plans.next_message_sequence(plan),
         {:ok, message} <-
           Plans.create_plan_message(plan, %{
             role: "human",
             content: content,
             author: user.email,
             status: "complete",
             sequence: sequence
           }),
         :ok <- Plans.send_agentic_message(plan, content) do
      json(conn, %{data: serialize_message(message)})
    else
      true -> Helpers.error_response(conn, :unprocessable_entity, "validation_error")
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  defp serialize_plan(pr) do
    %{
      id: pr.id,
      number: pr.number,
      title: pr.title,
      description: pr.description,
      status: pr.status,
      sandbox_provider: pr.sandbox_provider,
      sandbox_status: pr.sandbox_status,
      sandbox_workspace_id: pr.sandbox_workspace_id,
      sandbox_preview_url: sandbox_metadata_url(pr, "preview_url"),
      sandbox_dashboard_url: sandbox_metadata_url(pr, "dashboard_url"),
      forge_branch_name: pr.forge_branch_name,
      forge_pr_provider: pr.forge_pr_provider,
      forge_pr_number: pr.forge_pr_number,
      forge_pr_url: pr.forge_pr_url,
      forge_pr_state: pr.forge_pr_state,
      forge_pr_draft: pr.forge_pr_draft,
      user: serialize_user(pr.user),
      inserted_at: Helpers.format_datetime(pr.inserted_at),
      updated_at: Helpers.format_datetime(pr.updated_at)
    }
  end

  defp serialize_user(nil), do: nil
  defp serialize_user(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_user(user), do: %{id: user.id, email: user.email}

  defp serialize_comment(comment) do
    %{
      id: comment.id,
      role: comment.role,
      content: comment.content,
      author: comment.author,
      inserted_at: Helpers.format_datetime(comment.inserted_at)
    }
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      role: message.role,
      content: message.content,
      author: message.author,
      status: message.status,
      sequence: message.sequence,
      inserted_at: Helpers.format_datetime(message.inserted_at)
    }
  end

  defp sandbox_metadata_url(%{sandbox_metadata: metadata}, key) when is_map(metadata) do
    value =
      case key do
        "preview_url" -> Map.get(metadata, "preview_url") || Map.get(metadata, :preview_url)
        "dashboard_url" -> Map.get(metadata, "dashboard_url") || Map.get(metadata, :dashboard_url)
        _ -> nil
      end

    case value do
      url when is_binary(url) ->
        trimmed = String.trim(url)
        if trimmed != "", do: trimmed

      _ ->
        nil
    end
  end

  defp sandbox_metadata_url(_, _), do: nil
end
