defmodule MicelioWeb.RepositoryLive.Index do
  use MicelioWeb, :live_view
  use Gettext, backend: MicelioWeb.Gettext

  alias Micelio.Accounts
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    repositories = Repositories.list_repositories_for_user(socket.assigns.current_user)

    admin_organizations =
      Accounts.list_organizations_for_user_with_role(socket.assigns.current_user, "admin")

    socket =
      socket
      |> assign(:page_title, gettext("Repositories"))
      |> PageMeta.assign(
        description: gettext("Manage your repositories."),
        canonical_url: url(~p"/projects")
      )
      |> assign(:repositories_count, length(repositories))
      |> assign(:can_create_repository, admin_organizations != [])
      |> stream(:repositories, repositories)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="repositories-container">
        <.header>
          {gettext("Repositories")}
          <:actions>
            <.link
              navigate={~p"/organizations/new"}
              class="repository-button repository-button-secondary"
              id="new-organization-link"
            >
              {gettext("New organization")}
            </.link>
            <%= if @can_create_repository do %>
              <.link navigate={~p"/projects/new"} class="repository-button" id="new-repository-link">
                {gettext("New repository")}
              </.link>
            <% end %>
          </:actions>
        </.header>

        <%= if @repositories_count == 0 do %>
          <div class="repositories-empty">
            <h2>{gettext("No repositories yet")}</h2>
            <p>{gettext("Repositories help you organize your code and collaborate with others.")}</p>
            <%= if @can_create_repository do %>
              <.link
                navigate={~p"/projects/new"}
                class="repository-button"
                id="repositories-empty-create"
              >
                {gettext("Create your first repository")}
              </.link>
            <% end %>
          </div>
        <% else %>
          <div id="repositories" phx-update="stream" class="content-card-list">
            <.content_card
              :for={{id, repository} <- @streams.repositories}
              id={id}
              navigate={~p"/#{repository.organization.account.handle}/#{repository.handle}"}
            >
              <:title>{repository.name}</:title>
              <:subtitle>
                @{repository.organization.account.handle}/{repository.handle}
              </:subtitle>
              <:description>
                <%= if repository.description do %>
                  {repository.description}
                <% end %>
              </:description>
            </.content_card>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
