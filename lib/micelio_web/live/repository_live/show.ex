defmodule MicelioWeb.RepositoryLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Notifications
  alias Micelio.Plans
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => org_handle, "repository" => repository_handle}, _session, socket) do
    case Micelio.Repositories.get_repository_for_user_by_handle(
           socket.assigns.current_user,
           org_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_read, socket.assigns.current_user, repository) ==
             :ok do
          recent_sessions =
            Sessions.list_sessions_for_repository(repository)
            |> Enum.take(5)

          session_count = Sessions.count_sessions_for_repository(repository)
          plan_count = Plans.count_plans_for_repository(repository)

          socket =
            socket
            |> assign(:page_title, repository.name)
            |> PageMeta.assign(
              description: repository.description || "Project overview.",
              canonical_url: url(~p"/#{organization.account.handle}/#{repository.handle}")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:recent_sessions, recent_sessions)
            |> assign(:session_count, session_count)
            |> assign(:plan_count, plan_count)
            |> assign_star_data()

          _ =
            Repositories.record_repository_interaction(
              socket.assigns.current_user,
              repository,
              "view"
            )

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
  def handle_event("delete", _params, socket) do
    repository = socket.assigns.repository
    user = socket.assigns.current_user

    if Authorization.authorize(:repository_delete, user, repository) == :ok do
      {:ok, _} = Repositories.delete_repository(repository, user: user)

      {:noreply,
       socket
       |> put_flash(:info, "Project deleted successfully.")
       |> push_navigate(to: ~p"/repositories")}
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
    end
  end

  @impl true
  def handle_event("toggle_star", _params, socket) do
    repository = socket.assigns.repository
    user = socket.assigns.current_user

    if socket.assigns.starred? do
      _ = Repositories.unstar_repository(user, repository)
    else
      case Micelio.Repositories.star_repository(user, repository) do
        {:ok, _star} ->
          _ = Notifications.dispatch_repository_starred(repository, user)
          :ok

        {:error, _changeset} ->
          :error
      end
    end

    _ = Repositories.record_repository_interaction(user, repository, "pulse")

    {:noreply, assign_star_data(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="project-show-container">
        <.header>
          {@repository.name}
          <:subtitle>
            <div class="project-show-handle">
              {@organization.account.handle}/{@repository.handle}
            </div>
            <%= if @repository.description do %>
              <p class="project-show-description">{@repository.description}</p>
            <% end %>
            <%= if @repository.url do %>
              <p class="project-show-url">
                <a href={@repository.url} target="_blank" rel="noopener noreferrer">
                  {@repository.url}
                </a>
              </p>
            <% end %>
          </:subtitle>
          <:actions>
            <div class="project-show-stars">
              <button
                type="button"
                class="project-show-action project-show-action-star"
                id="repository-star-toggle"
                phx-click="toggle_star"
              >
                <%= if @starred? do %>
                  Unstar
                <% else %>
                  Star
                <% end %>
              </button>
              <span class="project-show-stars-count" id="repository-stars-count">
                Stars: {@stars_count}
              </span>
            </div>
            <%= if Authorization.authorize(:repository_update, @current_user, @repository) == :ok do %>
              <.link
                navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/edit"}
                class="project-show-action project-show-action-edit"
                id="project-edit"
              >
                Edit
              </.link>
              <button
                type="button"
                class="project-show-action project-show-action-delete"
                id="project-delete"
                phx-click="delete"
                phx-confirm="Delete this repository?"
              >
                Delete
              </button>
            <% end %>
          </:actions>
        </.header>

        <div class="project-show-navigation">
          <.link
            navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/sessions"}
            class="project-show-nav-link"
          >
            Sessions ({@session_count})
          </.link>
          <.link
            navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/prs"}
            class="project-show-nav-link"
          >
            Plans ({@plan_count})
          </.link>
        </div>

        <%= if not Enum.empty?(@recent_sessions) do %>
          <div class="project-recent-sessions">
            <h2>Recent Sessions</h2>
            <div class="sessions-list-compact">
              <%= for session <- @recent_sessions do %>
                <.link
                  navigate={
                    ~p"/#{@organization.account.handle}/#{@repository.handle}/sessions/#{session.id}"
                  }
                  class="session-card-compact"
                >
                  <div class="session-card-content">
                    <div class="session-goal-compact">{session.goal}</div>
                    <span class={"status-badge status-badge-#{session.status}"}>
                      {String.capitalize(session.status)}
                    </span>
                  </div>
                </.link>
              <% end %>
            </div>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/sessions"}
              class="project-show-action"
            >
              View all sessions
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp assign_star_data(socket) do
    repository = socket.assigns.repository
    user = socket.assigns.current_user

    socket
    |> assign(:starred?, Repositories.repository_starred?(user, repository))
    |> assign(:stars_count, Repositories.count_repository_stars(repository))
  end
end
