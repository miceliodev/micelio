defmodule MicelioWeb.Browser.OrganizationController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.Accounts
  alias Micelio.Accounts.OrganizationRegistration
  alias MicelioWeb.PageMeta

  @doc """
  Renders the new organization form.
  """
  def new(conn, _params) do
    form =
      Accounts.change_organization_registration()
      |> to_form(as: :organization)

    conn
    |> put_new_org_meta()
    |> render(:new, form: form)
  end

  @doc """
  Creates a new organization.
  """
  def create(conn, %{"organization" => organization_params}) do
    case Accounts.create_organization_for_user(conn.assigns.current_user, organization_params) do
      {:ok, organization} ->
        conn
        |> put_flash(:info, "Organization created successfully!")
        |> redirect(to: ~p"/#{organization.account.handle}")

      {:error, changeset} ->
        form =
          Accounts.change_organization_registration(organization_params)
          |> OrganizationRegistration.merge_errors(changeset)
          |> Map.put(:action, :insert)
          |> to_form(as: :organization)

        conn
        |> put_new_org_meta()
        |> render(:new, form: form)
    end
  end

  defp put_new_org_meta(conn) do
    PageMeta.put(conn,
      title_parts: ["New organization"],
      description: "Create a new organization to group repositories and collaborators.",
      canonical_url: url(~p"/organizations/new")
    )
  end
end
