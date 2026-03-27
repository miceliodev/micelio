defmodule MicelioWeb.RepositoryLive.Edit do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository
  alias MicelioWeb.PageMeta

  @impl true
  def mount(params, _session, socket) do
    case MicelioWeb.RepositoryResolver.resolve(params, socket.assigns) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_update, socket.assigns.current_user, repository) ==
             :ok do
          base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)

          form =
            repository
            |> Repositories.change_repository()
            |> to_form(as: :repository)

          socket =
            socket
            |> assign(:page_title, "Edit Repository")
            |> assign(:base_path, base_path)
            |> PageMeta.assign(
              description: "Edit repository settings.",
              canonical_url: unverified_url(MicelioWeb.Endpoint, "#{base_path}/edit")
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

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Repository not found.")
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
        {:ok, _repository} ->
          {:noreply,
           socket
           |> put_flash(:info, "Repository updated successfully!")
           |> push_navigate(to: socket.assigns.base_path)}

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
          Edit repository
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
              label="Repository name"
              placeholder="My Awesome Repository"
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
          </div>

          <div class="repository-form-group">
            <.input
              field={@form[:handle]}
              type="text"
              label="Repository handle"
              placeholder="awesome-project"
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <p class="repository-form-hint">Handles appear in repository URLs.</p>
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

          <div class="repository-form-group">
            <h3>{gettext("Push Transport")}</h3>
            <.input
              field={@form[:push_protocol]}
              type="select"
              label={gettext("Push protocol")}
              options={[{gettext("Use platform default"), ""} | Repository.push_protocol_options()]}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <.input
              field={@form[:push_host]}
              type="text"
              label={gettext("Push host")}
              placeholder={gettext("forge.example")}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <.input
              field={@form[:push_namespace]}
              type="text"
              label={gettext("Push namespace")}
              placeholder={gettext("organization")}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <.input
              field={@form[:push_repository]}
              type="text"
              label={gettext("Push repository")}
              placeholder={@form[:handle].value || gettext("repository-name")}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
          </div>

          <div class="repository-form-group">
            <h3>{gettext("Storage")}</h3>
            <.input
              field={@form[:storage_backend]}
              type="select"
              label={gettext("Storage backend")}
              options={[{gettext("Use platform default"), ""} | Repository.storage_backend_options()]}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <.input
              field={@form[:storage_key_prefix]}
              type="text"
              label={gettext("Storage key prefix")}
              placeholder={gettext("Optional repository storage prefix")}
              class="repository-input"
              error_class="repository-input repository-input-error"
            />
            <p class="repository-form-hint">
              {gettext(
                "Configure optional per-repository storage behavior for scaling and migration."
              )}
            </p>
          </div>

          <div class="repository-form-actions">
            <button type="submit" class="repository-button" id="repository-submit">
              Save changes
            </button>
            <.link
              navigate={@base_path}
              class="repository-button repository-button-secondary"
              id="repository-cancel"
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
