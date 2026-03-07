defmodule MicelioWeb.Api.V1.RepositoryController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.Mic.{Binary, Landing, Project}
  alias Micelio.Notifications
  alias Micelio.Repositories
  alias Micelio.Security.SecretScanner
  alias Micelio.Sessions
  alias Micelio.Sessions.ChangeStore
  alias Micelio.Storage
  alias Micelio.Webhooks
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug, ["repositories:read"] when action in [:index, :show]

  plug MicelioWeb.Plugs.ApiScopePlug,
       ["repositories:write"] when action in [:create, :update, :delete, :push]

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
        |> Map.take([
          "handle",
          "name",
          "description",
          "visibility",
          "push_protocol",
          "push_host",
          "push_namespace",
          "push_repository",
          "storage_backend",
          "storage_key_prefix"
        ])
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
      update_attrs =
        Map.take(params, [
          "name",
          "description",
          "visibility",
          "push_protocol",
          "push_host",
          "push_namespace",
          "push_repository",
          "storage_backend",
          "storage_key_prefix"
        ])

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

  operation(:push,
    summary: "Push changes to repository",
    description:
      "Pushes file-level changes directly to a repository using the repository-first workflow.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repository: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    request_body: {"Push request", "application/json", Schemas.PushRequest},
    security: [%{"bearer" => ["repositories:write"]}],
    responses: %{
      200 => {"Push result", "application/json", Schemas.PushResponse},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error},
      409 => {"Conflict", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def push(conn, %{"org" => org_handle, "repository" => repository_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repository_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository),
         {:ok, goal, changes} <- parse_push_payload(params),
         {:ok, head} <- fetch_repository_head(repository),
         {:ok, session} <- create_push_session(user, repository, repository_handle, goal, head),
         {:ok, pushed_session, stats} <-
           ChangeStore.store_session_changes(session, changes, storage_opts(repository)),
         :ok <- scan_push_session(pushed_session),
         {:ok, landing} <- Landing.land_session(pushed_session, storage_opts(repository)),
         {:ok, landed_session} <-
           land_push_session(
             pushed_session,
             landing.position,
             landing.landed_at
           ) do
      _ = Repositories.record_repository_interaction(user, repository, "push")

      Webhooks.dispatch_session_landed(repository, landed_session, landing.position)
      Notifications.dispatch_session_landed(repository, landed_session)

      conn
      |> json(%{
        data: %{
          session: serialize_session(landed_session),
          landing_position: landing.position,
          landed_at: Helpers.format_datetime(landing.landed_at),
          stats: stats
        }
      })
    else
      {:error, :invalid_goal} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "validation_error",
          "goal is required"
        )

      {:error, :invalid_changes} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "validation_error",
          "changes must be a non-empty list"
        )

      {:error, {:invalid_change, errors}} ->
        Helpers.error_response(conn, :unprocessable_entity, "validation_error", errors)

      {:error, :head_unavailable} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "validation_error",
          "Failed to read repository head"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        Helpers.handle_error(conn, {:error, changeset})

      {:error, {:conflicts, conflicts}} ->
        Helpers.error_response(
          conn,
          :conflict,
          "conflict",
          "Conflicts detected: #{Enum.join(conflicts, ", ")}"
        )

      {:error, :secret_scanned, info} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "secret_scan",
          SecretScanner.format_scan_error(info)
        )

      {:error, :change_store_failed} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "validation_error",
          "Failed to store changes"
        )

      {:error, :storage_error} ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "storage_error",
          "Failed to read repository head"
        )

      error ->
        Helpers.error_response(
          conn,
          :unprocessable_entity,
          "push_failed",
          "Unable to push changes: #{inspect(error)}"
        )
    end
  end

  defp serialize_repository(repository, org_handle) do
    %{
      id: repository.id,
      handle: repository.handle,
      name: repository.name,
      description: repository.description,
      url: repository.url,
      push_protocol: repository.push_protocol,
      push_host: repository.push_host,
      push_namespace: repository.push_namespace,
      push_repository: repository.push_repository,
      storage_backend: repository.storage_backend,
      storage_key_prefix: repository.storage_key_prefix,
      visibility: repository.visibility,
      organization_handle: org_handle,
      inserted_at: Helpers.format_datetime(repository.inserted_at),
      updated_at: Helpers.format_datetime(repository.updated_at)
    }
  end

  defp parse_push_payload(params) do
    with {:ok, goal} <- extract_goal(params["goal"]),
         {:ok, raw_changes} <- extract_changes(params["changes"]),
         {:ok, changes} <- validate_push_changes(raw_changes) do
      {:ok, goal, changes}
    end
  end

  defp extract_goal(nil), do: {:error, :invalid_goal}

  defp extract_goal(value) when is_binary(value) do
    goal = String.trim(value)

    if goal == "" do
      {:error, :invalid_goal}
    else
      {:ok, goal}
    end
  end

  defp extract_goal(_), do: {:error, :invalid_goal}

  defp extract_changes(nil), do: {:error, :invalid_changes}
  defp extract_changes(changes) when is_list(changes) and changes != [], do: {:ok, changes}
  defp extract_changes(_), do: {:error, :invalid_changes}

  defp validate_push_changes(changes) when is_list(changes) do
    normalized =
      Enum.reduce_while(changes, [], fn change, acc ->
        case validate_push_change(change) do
          {:ok, change} -> {:cont, [change | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case normalized do
      {:error, reason} -> {:error, {:invalid_change, reason}}
      changes -> {:ok, Enum.reverse(changes)}
    end
  end

  defp validate_push_change(change) do
    path = Map.get(change, "path") || Map.get(change, :path)
    change_type = Map.get(change, "change_type") || Map.get(change, :change_type) || "modified"
    content = Map.get(change, "content") || Map.get(change, :content)

    with {:ok, normalized_path} <- normalize_change_path(path),
         {:ok, normalized_type} <- normalize_change_type(change_type) do
      if normalized_type == "deleted" || is_binary(content) do
        {:ok,
         %{"path" => normalized_path, "change_type" => normalized_type, "content" => content}}
      else
        {:error,
         "Change #{inspect(normalized_path)} requires content unless change_type is \"deleted\""}
      end
    end
  end

  defp normalize_change_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" do
      {:error, "path must be a non-empty string"}
    else
      segments = String.split(trimmed, "/", trim: true)

      if Enum.empty?(segments) || Enum.any?(segments, &(&1 in [".", ".."])) do
        {:error, "path must not contain path traversal segments"}
      else
        {:ok, trimmed}
      end
    end
  end

  defp normalize_change_path(_), do: {:error, "path must be a non-empty string"}

  defp normalize_change_type(change_type) when is_binary(change_type) do
    case String.downcase(change_type) do
      "added" -> {:ok, "added"}
      "modified" -> {:ok, "modified"}
      "deleted" -> {:ok, "deleted"}
      _ -> {:error, "change_type must be one of added, modified, or deleted"}
    end
  end

  defp normalize_change_type(change_type) when is_atom(change_type) do
    normalize_change_type(to_string(change_type))
  end

  defp normalize_change_type(_),
    do: {:error, "change_type must be one of added, modified, or deleted"}

  defp fetch_repository_head(repository) do
    case Storage.get(Project.head_key(repository.id), storage_opts(repository)) do
      {:ok, content} ->
        case Binary.decode_head(content) do
          {:ok, head} -> {:ok, head}
          {:error, _reason} -> {:error, :head_unavailable}
        end

      {:error, :not_found} ->
        {:ok, %{position: 0, tree_hash: Binary.zero_hash()}}

      {:error, _reason} ->
        {:error, :storage_error}
    end
  end

  defp create_push_session(user, repository, repository_handle, goal, %{
         position: position,
         tree_hash: tree_hash
       }) do
    attrs = %{
      "goal" => goal,
      "repository_id" => repository.id,
      "user_id" => user.id,
      "session_id" => Ecto.UUID.generate(),
      "status" => "active",
      "started_at" => DateTime.utc_now() |> DateTime.truncate(:second),
      "metadata" => %{
        "base_position" => position,
        "base_tree_hash" => Base.encode64(tree_hash),
        "repository_handle" => repository_handle
      }
    }

    Sessions.create_session(attrs)
  end

  defp land_push_session(session, position, landed_at) do
    metadata =
      session.metadata
      |> normalize_session_metadata()
      |> Map.put("landing_position", position)

    Sessions.land_session(session, %{
      landed_at: landed_at,
      status: "landed",
      metadata: metadata
    })
  end

  defp scan_push_session(session) do
    case SecretScanner.scan_session_changes(session) do
      :ok -> :ok
      {:error, info} -> {:error, :secret_scanned, info}
    end
  end

  defp normalize_session_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_session_metadata(_), do: %{}

  defp storage_opts(repository) do
    [repository: repository, repository_id: repository.id]
  end

  defp serialize_session(session) do
    %{
      id: session.id,
      session_id: session.session_id,
      goal: session.goal,
      status: session.status,
      started_at: Helpers.format_datetime(session.started_at),
      landed_at: Helpers.format_datetime(session.landed_at),
      inserted_at: Helpers.format_datetime(session.inserted_at),
      updated_at: Helpers.format_datetime(session.updated_at)
    }
  end
end
