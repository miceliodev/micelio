defmodule MicelioWeb.AdminErrorsLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Errors
  alias Micelio.Errors.Error
  alias MicelioWeb.PageMeta

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Error Dashboard")
      |> PageMeta.assign(
        description: "Admin error tracking dashboard.",
        canonical_url: url(~p"/admin/errors")
      )
      |> assign(:filters, default_filters())
      |> assign(:sort, "newest")
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:errors, [])
      |> assign(:total, 0)
      |> assign(:overview, Errors.error_overview())
      |> assign(:trends, Errors.daily_counts(7))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = build_filters(params)

    result =
      Errors.list_errors(
        filters: filters,
        sort: params["sort"],
        page: params["page"],
        limit: @page_size
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:sort, Atom.to_string(result.sort))
     |> assign(:page, result.page)
     |> assign(:total, result.total)
     |> assign(:errors, result.errors)
     |> assign(:overview, Errors.error_overview())
     |> assign(:trends, Errors.daily_counts(7))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      %{
        "filters" => filters,
        "sort" => socket.assigns.sort,
        "page" => "1"
      }
      |> prune_params()

    {:noreply, push_patch(socket, to: ~p"/admin/errors?#{params}")}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    params =
      %{
        "filters" => socket.assigns.filters,
        "sort" => sort,
        "page" => "1"
      }
      |> prune_params()

    {:noreply, push_patch(socket, to: ~p"/admin/errors?#{params}")}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    params =
      %{
        "filters" => socket.assigns.filters,
        "sort" => socket.assigns.sort,
        "page" => page
      }
      |> prune_params()

    {:noreply, push_patch(socket, to: ~p"/admin/errors?#{params}")}
  end

  @impl true
  def handle_event("resolve", %{"id" => id}, socket) do
    error = Errors.get_error!(id)
    _ = Errors.resolve_error(error, socket.assigns.current_user.id)

    {:noreply, push_patch(socket, to: current_params_path(socket))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    error = Errors.get_error!(id)
    _ = Errors.delete_error(error)

    {:noreply, push_patch(socket, to: current_params_path(socket))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <div class="admin-errors" id="admin-errors">
        <.header>
          Error Dashboard
          <:subtitle>Operational insight for error tracking.</:subtitle>
        </.header>
        <div class="admin-errors-header-actions">
          <.link navigate={~p"/admin/errors/settings"} class="button">
            Notification settings
          </.link>
        </div>

        <section class="admin-errors-overview" id="admin-errors-overview">
          <h2 class="admin-section-title">Severity overview</h2>
          <div class="admin-errors-metrics">
            <.overview_card label="Last 24h" counts={@overview.last_24h} />
            <.overview_card label="Last 7d" counts={@overview.last_7d} />
            <.overview_card label="Last 30d" counts={@overview.last_30d} />
          </div>
          <div class="admin-errors-trend" id="admin-errors-trend">
            <h3 class="admin-section-subtitle">7-day trend</h3>
            <div class="admin-errors-trend-grid">
              <%= for entry <- @trends do %>
                <div class="admin-errors-trend-item">
                  <span class="admin-errors-trend-count">{entry.count}</span>
                  <span class="admin-errors-trend-date">{format_date(entry.date)}</span>
                </div>
              <% end %>
            </div>
          </div>
        </section>

        <section class="admin-errors-section" id="admin-errors-list">
          <div class="admin-errors-toolbar">
            <form class="admin-errors-filters" phx-change="filter">
              <input
                type="search"
                name="filters[query]"
                placeholder="Search messages"
                value={@filters["query"]}
              />
              <select name="filters[kind]" aria-label="Filter by kind">
                <option value="">All kinds</option>
                <%= for kind <- Error.kinds() do %>
                  <option value={kind} selected={@filters["kind"] == Atom.to_string(kind)}>
                    {format_label(kind)}
                  </option>
                <% end %>
              </select>
              <select name="filters[severity]" aria-label="Filter by severity">
                <option value="">All severities</option>
                <%= for severity <- Error.severities() do %>
                  <option value={severity} selected={@filters["severity"] == Atom.to_string(severity)}>
                    {format_label(severity)}
                  </option>
                <% end %>
              </select>
              <select name="filters[status]" aria-label="Filter by status">
                <option value="" selected={@filters["status"] in ["", nil]}>All status</option>
                <option value="unresolved" selected={@filters["status"] == "unresolved"}>
                  Unresolved
                </option>
                <option value="resolved" selected={@filters["status"] == "resolved"}>
                  Resolved
                </option>
              </select>
              <input
                type="text"
                name="filters[user_id]"
                placeholder="User ID"
                value={@filters["user_id"]}
              />
              <input
                type="text"
                name="filters[repository_id]"
                placeholder="Project ID"
                value={@filters["repository_id"]}
              />
              <input
                type="date"
                name="filters[start_date]"
                value={@filters["start_date"]}
                aria-label="Start date"
              />
              <input
                type="date"
                name="filters[end_date]"
                value={@filters["end_date"]}
                aria-label="End date"
              />
            </form>
            <form class="admin-errors-sort" phx-change="sort">
              <label for="admin-errors-sort">Sort</label>
              <select id="admin-errors-sort" name="sort">
                <option value="newest" selected={@sort == "newest"}>Newest</option>
                <option value="oldest" selected={@sort == "oldest"}>Oldest</option>
                <option value="occurrences" selected={@sort == "occurrences"}>
                  Most occurrences
                </option>
              </select>
            </form>
          </div>

          <%= if Enum.empty?(@errors) do %>
            <p class="admin-empty">No errors match the current filters.</p>
          <% else %>
            <div class="admin-errors-list">
              <%= for error <- @errors do %>
                <article class="admin-errors-card" id={"admin-error-#{error.id}"}>
                  <div class="admin-errors-card-main">
                    <div class="admin-errors-card-header">
                      <.link
                        navigate={~p"/admin/errors/#{error.id}"}
                        class="admin-errors-card-title"
                      >
                        {error.message}
                      </.link>
                      <span class={"admin-errors-severity admin-errors-severity-#{error.severity}"}>
                        {format_label(error.severity)}
                      </span>
                    </div>
                    <div class="admin-errors-card-meta">
                      <span>Kind: {format_label(error.kind)}</span>
                      <span>Occurrences: {error.occurrence_count}</span>
                      <span>Users: {affected_users(error)}</span>
                      <span>Last seen: {format_datetime(error.last_seen_at)}</span>
                      <span>Status: {status_label(error)}</span>
                    </div>
                  </div>
                  <div class="admin-errors-card-actions">
                    <button
                      type="button"
                      phx-click="resolve"
                      phx-value-id={error.id}
                      disabled={not is_nil(error.resolved_at)}
                    >
                      Resolve
                    </button>
                    <button
                      type="button"
                      phx-click="delete"
                      phx-confirm="Delete this error?"
                      phx-value-id={error.id}
                      class="danger"
                    >
                      Delete
                    </button>
                  </div>
                </article>
              <% end %>
            </div>

            <div class="admin-errors-pagination" id="admin-errors-pagination">
              <button
                type="button"
                phx-click="paginate"
                phx-value-page={@page - 1}
                disabled={@page <= 1}
              >
                Previous
              </button>
              <span>Page {@page} of {page_count(@total, @page_size)}</span>
              <button
                type="button"
                phx-click="paginate"
                phx-value-page={@page + 1}
                disabled={@page >= page_count(@total, @page_size)}
              >
                Next
              </button>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp default_filters do
    %{
      "query" => "",
      "kind" => "",
      "severity" => "",
      "status" => "unresolved",
      "user_id" => "",
      "repository_id" => "",
      "start_date" => "",
      "end_date" => ""
    }
  end

  defp build_filters(params) do
    defaults = default_filters()

    params
    |> Map.get("filters", %{})
    |> Map.merge(defaults, fn _key, value, _default -> value end)
  end

  defp prune_params(params) do
    {filters, rest} = Map.pop(params, "filters", %{})

    cleaned_filters =
      filters
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    cleaned_rest =
      rest
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    cleaned_params =
      if map_size(cleaned_filters) > 0 do
        Map.put(cleaned_rest, "filters", cleaned_filters)
      else
        cleaned_rest
      end

    Plug.Conn.Query.encode(cleaned_params)
  end

  defp current_params_path(socket) do
    params =
      %{
        "filters" => socket.assigns.filters,
        "sort" => socket.assigns.sort,
        "page" => Integer.to_string(socket.assigns.page)
      }
      |> prune_params()

    ~p"/admin/errors?#{params}"
  end

  defp format_label(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%b %d")
  end

  defp affected_users(%Error{user_id: nil}), do: 0
  defp affected_users(%Error{user_id: _}), do: 1

  defp status_label(%Error{resolved_at: nil}), do: "Unresolved"
  defp status_label(%Error{}), do: "Resolved"

  defp page_count(total, _limit) when total == 0, do: 1

  defp page_count(total, limit) do
    total
    |> Kernel./(limit)
    |> Float.ceil()
    |> trunc()
  end

  defp overview_card(assigns) do
    ~H"""
    <article class="admin-errors-metric">
      <h3 class="admin-errors-metric-title">{@label}</h3>
      <div class="admin-errors-metric-list">
        <%= for severity <- Error.severities() do %>
          <div class="admin-errors-metric-row">
            <span>{format_label(severity)}</span>
            <span class="admin-errors-metric-value">{Map.get(@counts, severity, 0)}</span>
          </div>
        <% end %>
      </div>
    </article>
    """
  end
end
