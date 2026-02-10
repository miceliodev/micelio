defmodule MicelioWeb.RepositoryLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    organizations =
      Accounts.list_organizations_for_user_with_role(socket.assigns.current_user, "admin")

    default_org = List.first(organizations)
    default_org_id = default_org && default_org.id

    form =
      %Repository{}
      |> Repositories.change_repository(%{organization_id: default_org_id},
        organization: default_org
      )
      |> to_form(as: :repository)

    socket =
      socket
      |> assign(:page_title, "New Project")
      |> PageMeta.assign(
        description: "Create a new project.",
        canonical_url: url(~p"/repositories/new")
      )
      |> assign(:organizations, organizations)
      |> assign(:organization_options, organization_options(organizations))
      |> assign(:form, form)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"repository" => params}, socket) do
    organization = find_organization(socket.assigns.organizations, params["organization_id"])

    changeset =
      %Repository{}
      |> Repositories.change_repository(params, organization: organization)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :repository))}
  end

  @impl true
  def handle_event("save", %{"repository" => params}, socket) do
    case find_organization(socket.assigns.organizations, params["organization_id"]) do
      nil ->
        changeset =
          %Repository{}
          |> Repositories.change_repository(params)
          |> Ecto.Changeset.add_error(:organization_id, "is not available")
          |> Map.put(:action, :validate)

        {:noreply, assign(socket, form: to_form(changeset, as: :repository))}

      organization ->
        if Authorization.authorize(:repository_create, socket.assigns.current_user, organization) ==
             :ok do
          attrs = Map.put(params, "organization_id", organization.id)

          case Micelio.Repositories.create_repository(attrs,
                 user: socket.assigns.current_user,
                 organization: organization
               ) do
            {:ok, repository} ->
              {:noreply,
               socket
               |> put_flash(:info, "Project created successfully!")
               |> push_navigate(to: ~p"/#{organization.account.handle}/#{repository.handle}")}

            {:error, changeset} ->
              {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
          end
        else
          {:noreply, put_flash(socket, :error, "You do not have access to this organization.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="repository-form-container">
        <.header>
          New project
          <:subtitle>
            <p>Create a repository under one of your organizations.</p>
          </:subtitle>
        </.header>

        <%= if Enum.empty?(@organizations) do %>
          <div class="projects-empty">
            <h2>No organizations available</h2>
            <p>You need to own an organization before you can create projects.</p>
            <.link
              navigate={~p"/organizations/new"}
              class="repository-button"
              id="create-organization-from-projects"
            >
              Create an organization
            </.link>
          </div>
        <% else %>
          <.form
            for={@form}
            id="repository-form"
            phx-change="validate"
            phx-submit="save"
            class="repository-form"
          >
            <div class="repository-form-group">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                options={@organization_options}
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:name]}
                type="text"
                label="Project name"
                placeholder="My Awesome Project"
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:handle]}
                type="text"
                label="Project handle"
                placeholder="awesome-project"
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
              <p class="repository-form-hint">Handles appear in project URLs.</p>
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description"
                placeholder="Optional description"
                class="repository-input project-textarea"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:visibility]}
                type="select"
                label="Visibility"
                options={visibility_options()}
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
              <p class="repository-form-hint">Public repositories are visible to everyone.</p>
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:url]}
                type="url"
                label="URL"
                placeholder="https://example.com"
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
              <p class="repository-form-hint">Optional homepage or project URL.</p>
            </div>

            <div class="repository-form-actions">
              <button type="submit" class="repository-button" id="project-submit">
                Create project
              </button>
              <.link
                navigate={~p"/repositories"}
                class="repository-button repository-button-secondary"
                id="project-cancel"
              >
                Cancel
              </.link>
            </div>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp organization_options(organizations) do
    Enum.map(organizations, fn organization ->
      {organization.account.handle, organization.id}
    end)
  end

  defp visibility_options do
    [
      {"Private", "private"},
      {"Public", "public"}
    ]
  end

  defp find_organization(organizations, organization_id) do
    Enum.find(organizations, fn organization -> organization.id == organization_id end)
  end
end
