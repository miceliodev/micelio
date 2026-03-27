defmodule MicelioWeb.RepositoryLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Plans
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository
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
          push_url = Repository.push_url(repository)

          socket =
            socket
            |> assign(:page_title, repository.name)
            |> PageMeta.assign(
              description: repository.description || gettext("Repository overview."),
              canonical_url: url(~p"/#{organization.account.handle}/#{repository.handle}")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:recent_sessions, recent_sessions)
            |> assign(:push_url, push_url)
            |> assign(:session_count, session_count)
            |> assign(:plan_count, plan_count)

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
         |> put_flash(:error, gettext("Repository not found."))
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
       |> put_flash(:info, gettext("Repository deleted successfully."))
       |> push_navigate(to: ~p"/repositories")}
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
      <div class="repository-show-container">
        <.header>
          {@repository.name}
          <:subtitle>
            <div class="repository-show-handle">
              {@organization.account.handle}/{@repository.handle}
            </div>
            <%= if @repository.description do %>
              <p class="repository-show-description">{@repository.description}</p>
            <% end %>
            <%= if @repository.url do %>
              <p class="repository-show-url">
                <a href={@repository.url} target="_blank" rel="noopener noreferrer">
                  {@repository.url}
                </a>
              </p>
            <% end %>

            <%= if @repository.push_protocol do %>
              <p class="repository-show-description">
                {gettext("Push endpoint:")} <code>{@push_url || ""}</code>
              </p>
              <p class="repository-show-description">
                {gettext("Push protocol:")} {@repository.push_protocol} | {gettext("Storage backend:")} {@repository.storage_backend ||
                  gettext("default")}
              </p>
            <% end %>
          </:subtitle>
          <:actions>
            <%= if Authorization.authorize(:repository_update, @current_user, @repository) == :ok do %>
              <.link
                navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/edit"}
                class="repository-show-action repository-show-action-edit"
                id="project-edit"
              >
                Edit
              </.link>
              <button
                type="button"
                class="repository-show-action repository-show-action-delete"
                id="repository-delete"
                phx-click="delete"
                phx-confirm="Delete this repository?"
              >
                Delete
              </button>
            <% end %>
          </:actions>
        </.header>

        <div class="repository-show-navigation">
          <.link
            navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/sessions"}
            class="repository-show-nav-link"
          >
            Sessions ({@session_count})
          </.link>
          <.link
            navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/prompt-requests"}
            class="repository-show-nav-link"
          >
            Plans ({@plan_count})
          </.link>
        </div>

        <%= if not Enum.empty?(@recent_sessions) do %>
          <div class="repository-recent-sessions">
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
              class="repository-show-action"
            >
              View all sessions
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
