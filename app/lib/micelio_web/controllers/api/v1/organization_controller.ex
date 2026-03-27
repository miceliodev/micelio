defmodule MicelioWeb.Api.V1.OrganizationController do
  use MicelioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Micelio.Accounts
  alias MicelioWeb.Api.Helpers
  alias MicelioWeb.Api.Schemas

  plug MicelioWeb.Plugs.ApiScopePlug, ["organizations:read"]

  tags(["Organizations"])

  operation(:index,
    summary: "List organizations",
    description: "Lists organizations the authenticated user belongs to.",
    security: [%{"bearer" => ["organizations:read"]}],
    responses: %{
      200 => {"Organization list", "application/json", Schemas.OrganizationList},
      401 => {"Unauthorized", "application/json", Schemas.Error}
    }
  )

  def index(conn, _params) do
    case Helpers.fetch_user(conn) do
      {:ok, user} ->
        organizations = Accounts.list_organizations_for_user(user)

        json(conn, %{
          data: Enum.map(organizations, &serialize_organization/1)
        })

      error ->
        Helpers.handle_error(conn, error)
    end
  end

  operation(:show,
    summary: "Get organization",
    description: "Gets an organization by its handle.",
    parameters: [
      handle: [in: :path, type: :string, description: "Organization handle", required: true]
    ],
    security: [%{"bearer" => ["organizations:read"]}],
    responses: %{
      200 => {"Organization", "application/json", Schemas.Organization},
      401 => {"Unauthorized", "application/json", Schemas.Error},
      404 => {"Not found", "application/json", Schemas.Error}
    }
  )

  def show(conn, %{"handle" => handle}) do
    with {:ok, _user} <- Helpers.fetch_user(conn),
         {:ok, organization} <- Helpers.fetch_organization(handle) do
      json(conn, %{data: serialize_organization(organization)})
    else
      error -> Helpers.handle_error(conn, error)
    end
  end

  defp serialize_organization(%Accounts.Organization{} = org) do
    handle = if org.account, do: org.account.handle

    %{
      id: org.id,
      handle: handle,
      name: org.name,
      inserted_at: Helpers.format_datetime(org.inserted_at),
      updated_at: Helpers.format_datetime(org.updated_at)
    }
  end
end
