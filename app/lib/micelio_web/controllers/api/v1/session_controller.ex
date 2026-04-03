defmodule MicelioWeb.Api.V1.SessionController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Authorization
  alias Micelio.Sessions
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug(MicelioWeb.Plugs.ApiScopePlug, ["sessions:read"] when action in [:index, :show])
  plug(MicelioWeb.Plugs.ApiScopePlug, ["sessions:write"] when action in [:create, :land])

  tags(["Sessions"])

  operation(:index,
    summary: "List sessions",
    description: "Lists sessions for a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    security: [%{"bearer" => ["sessions:read"]}],
    responses: %{
      200 => {"Session list", "application/json", Schemas.SessionList},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def index(conn, %{"org" => org_handle, "repo" => repo_handle}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      sessions = Sessions.list_sessions_for_repository(repository)

      json(conn, %{
        data: Enum.map(sessions, &serialize_session/1)
      })
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:show,
    summary: "Get session",
    description: "Gets a session by its identifier (database ID or session_id).",
    parameters: [
      session_id: [
        in: :path,
        type: :string,
        description: "Session database ID or session_id",
        required: true
      ]
    ],
    security: [%{"bearer" => ["sessions:read"]}],
    responses: %{
      200 => {"Session", "application/json", Schemas.Session},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def show(conn, %{"session_id" => session_id}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         %Sessions.Session{} = session <-
           Sessions.get_session_with_associations_by_identifier(session_id),
         :ok <- Authorization.authorize(:repository_read, user, session.repository) do
      json(conn, %{data: serialize_session(session)})
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:create,
    summary: "Start session",
    description: "Starts a new session in a repository.",
    parameters: [
      org: [in: :path, type: :string, description: "Organization handle", required: true],
      repo: [in: :path, type: :string, description: "Repository handle", required: true]
    ],
    request_body: {"Session params", "application/json", Schemas.StartSessionRequest},
    security: [%{"bearer" => ["sessions:write"]}],
    responses: %{
      201 => {"Created session", "application/json", Schemas.Session},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error},
      422 => {"Validation error", "application/json", Schemas.Error}
    }
  )

  def create(conn, %{"org" => org_handle, "repo" => repo_handle} = params) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
         :ok <- Authorization.authorize(:repository_write, user, repository) do
      session_attrs = %{
        "goal" => params["goal"],
        "repository_id" => repository.id,
        "user_id" => user.id,
        "session_id" => Ecto.UUID.generate(),
        "status" => "active",
        "started_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Sessions.create_session(session_attrs) do
        {:ok, session} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_session(session)})

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})
      end
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  operation(:land,
    summary: "Land session",
    description: "Lands (completes) a session.",
    parameters: [
      session_id: [
        in: :path,
        type: :string,
        description: "Session database ID or session_id",
        required: true
      ]
    ],
    security: [%{"bearer" => ["sessions:write"]}],
    responses: %{
      200 => {"Landed session", "application/json", Schemas.Session},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      403 => {"Forbidden", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def land(conn, %{"session_id" => session_id}) do
    with {:ok, user} <- Helpers.fetch_user(conn),
         %Sessions.Session{} = session <-
           Sessions.get_session_with_associations_by_identifier(session_id),
         :ok <- Authorization.authorize(:repository_write, user, session.repository) do
      case Sessions.land_session_to_trunk(session) do
        {:ok, landed} ->
          json(conn, %{data: serialize_session(landed)})

        {:error, :not_active} ->
          Helpers.error_response(
            conn,
            :unprocessable_entity,
            "validation_error",
            "Only active sessions can be landed"
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          Helpers.handle_error(conn, {:error, changeset})

        {:error, reason} ->
          Helpers.error_response(
            conn,
            :unprocessable_entity,
            "landing_failed",
            "Unable to land session: #{inspect(reason)}"
          )
      end
    else
      nil -> Helpers.handle_error(conn, {:error, :not_found})
      error -> Helpers.handle_error(conn, error)
    end
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
