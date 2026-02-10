defmodule MicelioWeb.RepositoryLive.Edit do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => org_handle, "repository" => repository_handle}, _session, socket) do
    case Micelio.Repositories.get_repository_for_user_by_handle(
           socket.assigns.current_user,
           org_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_update, socket.assigns.current_user, repository) ==
             :ok do
          form =
            repository
            |> Repositories.change_repository()
            |> to_form(as: :repository)

          socket =
            socket
            |> assign(:page_title, "Edit Project")
            |> PageMeta.assign(
              description: "Edit project settings.",
              canonical_url: url(~p"/#{organization.account.handle}/#{repository.handle}/edit")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:form, form)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/repositories")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("validate", %{"repository" => params}, socket) do
    changeset =
      socket.assigns.repository
      |> Repositories.change_repository(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :repository))}
  end

  @impl true
  def handle_event("save", %{"repository" => params}, socket) do
    if Authorization.authorize(
         :repository_update,
         socket.assigns.current_user,
         socket.assigns.repository
       ) ==
         :ok do
      case Micelio.Repositories.update_repository(socket.assigns.repository, params,
             user: socket.assigns.current_user
           ) do
        {:ok, repository} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project updated successfully!")
           |> push_navigate(
             to: ~p"/#{socket.assigns.organization.account.handle}/#{repository.handle}"
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
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
          Edit project
          <:subtitle>
            <p>
              {@organization.account.handle}/{@repository.handle}
            </p>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="repository-form"
          phx-change="validate"
          phx-submit="save"
          class="repository-form"
        >
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
              Save changes
            </button>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@repository.handle}"}
              class="repository-button repository-button-secondary"
              id="project-cancel"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp visibility_options do
    [
      {"Private", "private"},
      {"Public", "public"}
    ]
  end
end
