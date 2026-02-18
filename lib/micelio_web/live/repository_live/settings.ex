defmodule MicelioWeb.RepositoryLive.Settings do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Repositories
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
            |> Repositories.change_repository_settings(%{}, organization: organization)
            |> to_form(as: :repository)

          socket =
            socket
            |> assign(:page_title, "Repository settings")
            |> assign(:base_path, base_path)
            |> PageMeta.assign(
              description: "Edit repository settings.",
              canonical_url: unverified_url(MicelioWeb.Endpoint, "#{base_path}/settings")
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
      |> Repositories.change_repository_settings(params,
        organization: socket.assigns.organization
      )
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
      case Micelio.Repositories.update_repository_settings(socket.assigns.repository, params,
             user: socket.assigns.current_user,
             organization: socket.assigns.organization
           ) do
        {:ok, _repository} ->
          {:noreply,
           socket
           |> put_flash(:info, "Repository updated successfully!")
           |> push_navigate(to: socket.assigns.base_path)}

        {:error, changeset} ->
          {:noreply,
           assign(socket,
             form: to_form(Map.put(changeset, :action, :validate), as: :repository)
           )}
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
      repository_nav={
        %{
          account_handle: @organization.account.handle,
          repository_handle: @repository.handle,
          active: :settings,
          show_settings?: true,
          base_path: @base_path
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:settings}
        base_path={@base_path}
      >
        <.settings_layout
          base_path={"#{@base_path}/settings"}
          active={:general}
        >
          <.header>
            General
          </.header>

          <.form
            for={@form}
            id="project-settings-form"
            phx-change="validate"
            phx-submit="save"
            class="repository-form"
          >
            <div class="repository-form-group">
              <.input
                field={@form[:name]}
                type="text"
                label="Repository name"
                placeholder="My Project"
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
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

            <div class="repository-form-actions">
              <button type="submit" class="repository-button" id="project-settings-submit">
                Save changes
              </button>
              <.link
                navigate={@base_path}
                class="repository-button repository-button-secondary"
                id="project-settings-cancel"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </.settings_layout>
      </.repository_header>
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
