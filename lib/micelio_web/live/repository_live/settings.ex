defmodule MicelioWeb.RepositoryLive.Settings do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => account_handle, "repository" => repository_handle}, _session, socket) do
    case Micelio.Repositories.get_repository_for_user_by_handle(
           socket.assigns.current_user,
           account_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_update, socket.assigns.current_user, repository) ==
             :ok do
          form =
            repository
            |> Repositories.change_repository_settings(%{}, organization: organization)
            |> to_form(as: :repository)

          socket =
            socket
            |> assign(:page_title, "Repository settings")
            |> PageMeta.assign(
              description: "Edit repository settings.",
              canonical_url:
                url(~p"/#{organization.account.handle}/#{repository.handle}/settings")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:form, form)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Repository not found.")
         |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
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
        {:ok, repository} ->
          {:noreply,
           socket
           |> put_flash(:info, "Repository updated successfully!")
           |> push_navigate(
             to: ~p"/#{socket.assigns.organization.account.handle}/#{repository.handle}"
           )}

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
          show_settings?: true
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:settings}
      >
        <.settings_layout
          base_path={~p"/#{@organization.account.handle}/#{@repository.handle}/settings"}
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
                navigate={~p"/#{@organization.account.handle}/#{@repository.handle}"}
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
