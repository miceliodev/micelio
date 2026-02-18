defmodule MicelioWeb.SessionLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.{Authorization, Sessions}
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
          socket =
            socket
            |> assign(:page_title, "Sessions - #{repository.name}")
            |> PageMeta.assign(
              description: "Browse sessions for #{repository.name}.",
              canonical_url:
                url(~p"/#{organization.account.handle}/#{repository.handle}/sessions")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:status_filter, "all")
            |> assign(:sort_order, :newest)
            |> load_sessions()

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
  def handle_event("filter", %{"status" => status}, socket) do
    socket =
      socket
      |> assign(:status_filter, status)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    socket =
      socket
      |> assign(:sort_order, normalize_sort(sort))
      |> load_sessions()

    {:noreply, socket}
  end

  defp load_sessions(socket) do
    status_filter = socket.assigns.status_filter
    sort_order = socket.assigns.sort_order
    repository = socket.assigns.repository

    opts =
      []
      |> maybe_put(:status, status_filter)
      |> Keyword.put(:sort, sort_order)

    sessions = Sessions.list_sessions_for_repository(repository, opts)

    assign(socket, :sessions, sessions)
  end

  defp maybe_put(opts, _key, "all"), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_sort("oldest"), do: :oldest
  defp normalize_sort("status"), do: :status
  defp normalize_sort(_), do: :newest

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
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
          active: :sessions,
          show_settings?: true
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:sessions}
      >
        <%!-- Filter bar --%>
        <div class="sessions-toolbar" id="sessions-toolbar">
          <div class="sessions-filter-bar">
            <button
              type="button"
              class={["sessions-filter-btn", @status_filter == "all" && "is-active"]}
              phx-click="filter"
              phx-value-status="all"
            >
              {gettext("All")}
              <span class="sessions-filter-count">{length(@sessions)}</span>
            </button>
            <button
              type="button"
              class={["sessions-filter-btn", @status_filter == "active" && "is-active"]}
              phx-click="filter"
              phx-value-status="active"
            >
              <svg
                class="sessions-filter-icon"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <circle cx="12" cy="12" r="5" />
              </svg>
              {gettext("Active")}
            </button>
            <button
              type="button"
              class={["sessions-filter-btn", @status_filter == "landed" && "is-active"]}
              phx-click="filter"
              phx-value-status="landed"
            >
              <svg
                class="sessions-filter-icon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M20 6L9 17l-5-5" />
              </svg>
              {gettext("Landed")}
            </button>
            <button
              type="button"
              class={["sessions-filter-btn", @status_filter == "abandoned" && "is-active"]}
              phx-click="filter"
              phx-value-status="abandoned"
            >
              <svg
                class="sessions-filter-icon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M18 6L6 18M6 6l12 12" />
              </svg>
              {gettext("Abandoned")}
            </button>
          </div>
          <form class="sessions-sort-form" phx-change="sort">
            <select
              id="sort-order"
              name="sort"
              class="compact-select"
              aria-label={gettext("Sort order")}
            >
              <option value="newest" selected={@sort_order == :newest}>{gettext("Newest")}</option>
              <option value="oldest" selected={@sort_order == :oldest}>{gettext("Oldest")}</option>
              <option value="status" selected={@sort_order == :status}>{gettext("Status")}</option>
            </select>
          </form>
        </div>

        <%!-- Session list --%>
        <%= if Enum.empty?(@sessions) do %>
          <div class="sessions-empty-state" id="sessions-empty">
            <svg
              class="sessions-empty-icon"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <path d="M12 8v4l3 3" />
              <circle cx="12" cy="12" r="9" />
            </svg>
            <h3 class="sessions-empty-title">{gettext("No sessions yet")}</h3>
            <p class="sessions-empty-text">
              {gettext(
                "Sessions are created when you use the mic CLI to make changes to this repository."
              )}
            </p>
          </div>
        <% else %>
          <div class="sessions-list" id="sessions-list">
            <%= for session <- @sessions do %>
              <.link
                navigate={
                  ~p"/#{@organization.account.handle}/#{@repository.handle}/sessions/#{session.id}"
                }
                class="sessions-item"
                id={"session-#{session.id}"}
              >
                <div class="sessions-item-icon">
                  <%= case session.status do %>
                    <% "active" -> %>
                      <svg
                        class="sessions-item-icon-active"
                        viewBox="0 0 24 24"
                        fill="currentColor"
                        aria-hidden="true"
                      >
                        <circle cx="12" cy="12" r="5" />
                      </svg>
                    <% "landed" -> %>
                      <svg
                        class="sessions-item-icon-landed"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2.5"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <path d="M20 6L9 17l-5-5" />
                      </svg>
                    <% "abandoned" -> %>
                      <svg
                        class="sessions-item-icon-abandoned"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2.5"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <path d="M18 6L6 18M6 6l12 12" />
                      </svg>
                    <% _ -> %>
                      <svg
                        class="sessions-item-icon-default"
                        viewBox="0 0 24 24"
                        fill="currentColor"
                        aria-hidden="true"
                      >
                        <circle cx="12" cy="12" r="5" />
                      </svg>
                  <% end %>
                </div>
                <div class="sessions-item-content">
                  <div class="sessions-item-header">
                    <span class="sessions-item-goal">{session.goal}</span>
                  </div>
                  <div class="sessions-item-meta">
                    <span class={"sessions-item-status sessions-item-status-#{session.status}"}>
                      {String.capitalize(session.status)}
                    </span>
                    <span class="sessions-item-dot">&middot;</span>
                    <span>{gettext("started")} {format_datetime(session.started_at)}</span>
                    <%= if session.landed_at do %>
                      <span class="sessions-item-dot">&middot;</span>
                      <span>{gettext("landed")} {format_datetime(session.landed_at)}</span>
                    <% end %>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </.repository_header>
    </Layouts.app>
    """
  end
end
