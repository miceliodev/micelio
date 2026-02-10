defmodule MicelioWeb.SessionLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Sessions.{EventSchema, Session}
  alias Micelio.{Authorization, Sessions}
  alias MicelioWeb.PageMeta

  @event_snapshot_limit 50

  @impl true
  def mount(
        %{
          "organization_handle" => org_handle,
          "repository_handle" => repository_handle,
          "id" => session_id
        },
        _session,
        socket
      ) do
    case Micelio.Repositories.get_repository_for_user_by_handle(
           socket.assigns.current_user,
           org_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_read, socket.assigns.current_user, repository) ==
             :ok do
          case Sessions.get_session_with_changes(session_id) do
            nil ->
              {:ok,
               socket
               |> put_flash(:error, "Session not found.")
               |> push_navigate(to: ~p"/projects/#{org_handle}/#{repository_handle}/sessions")}

            session ->
              if session.repository_id == repository.id do
                change_stats = Sessions.get_session_change_stats(session)

                socket =
                  socket
                  |> assign(:page_title, "Session: #{session.goal}")
                  |> PageMeta.assign(
                    description: "Session details for #{repository.name}.",
                    canonical_url:
                      url(
                        ~p"/projects/#{organization.account.handle}/#{repository.handle}/sessions/#{session.id}"
                      ),
                    open_graph: %{
                      image_template: "agent_session",
                      image_stats: session_og_stats(change_stats)
                    }
                  )
                  |> assign(:repository, repository)
                  |> assign(:organization, organization)
                  |> assign(:session, session)
                  |> assign(:change_stats, change_stats)
                  |> assign(:event_types, EventSchema.event_types())
                  |> assign(:max_session_events, @event_snapshot_limit)
                  |> assign(:contributor_type, Session.contributor_type(session))
                  |> assign(:model_id, Session.model_id(session))
                  |> assign(:tool_name, Session.tool_name(session))
                  |> load_event_snapshot()
                  |> assign_timeline()
                  |> assign_session_og_summary()

                {:ok, socket}
              else
                {:ok,
                 socket
                 |> put_flash(:error, "Session not found.")
                 |> push_navigate(to: ~p"/projects/#{org_handle}/#{repository_handle}/sessions")}
              end
          end
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/projects")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("abandon", _params, socket) do
    session = socket.assigns.session

    if session.status == "active" do
      case Sessions.abandon_session(session) do
        {:ok, updated_session} ->
          {:noreply,
           socket
           |> assign(:session, updated_session)
           |> put_flash(:info, "Session abandoned successfully.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to abandon session.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only active sessions can be abandoned.")}
    end
  end

  # Timeline builder

  defp assign_timeline(socket) do
    session = socket.assigns.session
    event_snapshot = socket.assigns.event_snapshot

    timeline = build_timeline(session, event_snapshot)
    assign(socket, :timeline, timeline)
  end

  defp build_timeline(session, event_snapshot) do
    conversation_items =
      (session.conversation || [])
      |> Enum.map(fn msg ->
        %{
          type: :message,
          role: msg["role"] || "unknown",
          content: msg["content"] || "",
          timestamp: msg["timestamp"]
        }
      end)

    decision_items =
      (session.decisions || [])
      |> Enum.map(fn dec ->
        %{type: :decision, decision: dec["decision"], reasoning: dec["reasoning"]}
      end)

    event_items =
      event_snapshot
      |> Enum.map(fn %{event: event} ->
        %{type: :event, event: event}
      end)

    conversation_items ++ decision_items ++ event_items
  end

  # Helpers

  defp status_badge_class("active"), do: "status-badge-active"
  defp status_badge_class("landed"), do: "status-badge-landed"
  defp status_badge_class("abandoned"), do: "status-badge-abandoned"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M UTC")
  end

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  defp format_file_size(_), do: ""

  defp prompt_request_title(%{title: title, id: id}) do
    case title do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: "Prompt request #{id}", else: trimmed

      _ ->
        "Prompt request #{id}"
    end
  end

  defp session_og_stats(%{total: total, added: added, modified: modified, deleted: deleted})
       when is_integer(total) and is_integer(added) and is_integer(modified) and
              is_integer(deleted) do
    %{
      files: total,
      added: added,
      modified: modified,
      deleted: deleted
    }
  end

  defp session_og_stats(_), do: %{}

  defp assign_session_og_summary(socket) do
    session = socket.assigns.session

    case Sessions.get_or_generate_og_summary(session, session.changes) do
      {:ok, summary} when is_binary(summary) and summary != "" ->
        PageMeta.assign(socket, description: summary)

      _ ->
        socket
    end
  end

  defp load_event_snapshot(socket) do
    session = socket.assigns.session

    case Sessions.list_session_events(session.session_id, limit: @event_snapshot_limit) do
      {:ok, events} ->
        last_cursor =
          case List.last(events) do
            %{storage_key: storage_key} -> storage_key
            _ -> nil
          end

        socket
        |> assign(:event_snapshot, events)
        |> assign(:event_after_cursor, last_cursor)

      {:error, _reason} ->
        socket
        |> assign(:event_snapshot, [])
        |> assign(:event_after_cursor, nil)
    end
  end

  # Event helpers

  defp event_type(%{"type" => type}) when is_binary(type), do: type
  defp event_type(_event), do: "unknown"

  defp event_payload(%{"payload" => payload}) when is_map(payload), do: payload
  defp event_payload(_event), do: %{}

  defp event_output_text(event) do
    payload = event_payload(event)

    if event_type(event) == "output" and is_binary(payload["text"]) do
      payload["text"]
    end
  end

  defp event_output_stream(event) do
    payload = event_payload(event)

    if event_type(event) == "output" and is_binary(payload["stream"]) do
      payload["stream"]
    end
  end

  defp output_open?(output) when is_binary(output) do
    String.length(output) <= 240
  end

  defp output_open?(_output), do: false

  defp event_summary(event) do
    payload = event_payload(event)

    case event_type(event) do
      "status" ->
        parts =
          []
          |> maybe_push(payload["state"])
          |> maybe_push(payload["message"])

        Enum.join(parts, " - ")

      "progress" ->
        cond do
          is_number(payload["percent"]) ->
            join_parts([format_percent(payload["percent"]), payload["message"]])

          is_number(payload["current"]) and is_number(payload["total"]) ->
            unit = payload["unit"] || ""

            "#{payload["current"]}/#{payload["total"]} #{unit}"
            |> String.trim()
            |> then(&join_parts([&1, payload["message"]]))

          is_binary(payload["message"]) ->
            payload["message"]

          true ->
            ""
        end

      "error" ->
        if is_binary(payload["message"]), do: payload["message"], else: ""

      _ ->
        ""
    end
  end

  defp format_percent(nil), do: nil
  defp format_percent(percent) when is_number(percent), do: "#{percent}%"
  defp format_percent(_), do: nil

  defp join_parts(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn part -> is_binary(part) and part != "" end)
    |> Enum.join(" - ")
  end

  defp event_progress_percent(event) do
    payload = event_payload(event)

    percent =
      cond do
        is_number(payload["percent"]) ->
          payload["percent"]

        is_number(payload["current"]) and is_number(payload["total"]) and payload["total"] > 0 ->
          payload["current"] / payload["total"] * 100

        true ->
          nil
      end

    if is_number(percent) do
      percent
      |> max(0)
      |> min(100)
    end
  end

  defp maybe_push(list, value) when is_binary(value) and value != "", do: list ++ [value]
  defp maybe_push(list, value) when is_number(value), do: list ++ ["#{value}"]
  defp maybe_push(list, _value), do: list

  defp format_event_timestamp(nil), do: nil

  defp format_event_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%H:%M:%S")

      _ ->
        timestamp
    end
  end

  defp event_timestamp_attr(nil), do: nil

  defp event_timestamp_attr(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> DateTime.to_iso8601(datetime)
      _ -> nil
    end
  end

  defp artifact_uri(%{"uri" => uri}) when is_binary(uri) and uri != "", do: uri
  defp artifact_uri(_payload), do: nil

  defp artifact_label(payload) do
    cond do
      is_binary(payload["name"]) and payload["name"] != "" -> payload["name"]
      is_binary(payload["uri"]) and payload["uri"] != "" -> payload["uri"]
      true -> "Artifact"
    end
  end

  defp artifact_detail(payload) do
    parts =
      []
      |> maybe_push(payload["kind"])
      |> maybe_push(format_file_size(payload["size_bytes"]))

    join_parts(parts)
  end

  defp artifact_image?(payload) do
    kind = payload["kind"]
    content_type = payload["content_type"]
    uri = payload["uri"]

    cond do
      kind == "image" ->
        true

      is_binary(content_type) and String.starts_with?(content_type, "image/") ->
        true

      is_binary(uri) ->
        String.downcase(uri)
        |> String.ends_with?([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"])

      true ->
        false
    end
  end

  defp contributor_label("ai"), do: gettext("AI")
  defp contributor_label("human"), do: gettext("Human")
  defp contributor_label("mixed"), do: gettext("AI + Human")
  defp contributor_label(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:sessions}
      >
        <div class="session-layout">
          <%!-- Main content column --%>
          <div class="session-main">
            <header class="session-main-header">
              <div class="session-main-title">
                <h1>{@session.goal}</h1>
                <span class={"status-badge #{status_badge_class(@session.status)}"}>
                  {String.capitalize(@session.status)}
                </span>
              </div>
              <div class="session-main-meta">
                <%= if @session.user do %>
                  <span>{@session.user.email}</span>
                  <span class="session-main-dot">&middot;</span>
                <% end %>
                <time>{format_datetime(@session.started_at)}</time>
              </div>
            </header>

            <%!-- Conversation timeline --%>
            <div class="session-timeline" id="session-timeline">
              <%= for item <- @timeline do %>
                <%= case item.type do %>
                  <% :message -> %>
                    <div class={"session-tl-message session-tl-message-#{item.role}"}>
                      <div class="session-tl-avatar">
                        <%= if item.role == "user" do %>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="16"
                            height="16"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="2"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          >
                            <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" /><circle
                              cx="12"
                              cy="7"
                              r="4"
                            />
                          </svg>
                        <% else %>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="16"
                            height="16"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="2"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          >
                            <path d="M12 8V4H8" /><rect
                              width="16"
                              height="12"
                              x="4"
                              y="8"
                              rx="2"
                            /><path d="M2 14h2" /><path d="M20 14h2" /><path d="M15 13v2" /><path d="M9 13v2" />
                          </svg>
                        <% end %>
                      </div>
                      <div class="session-tl-bubble">
                        <div class="session-tl-role">
                          <%= if item.role == "user" && @session.user && @session.user.account do %>
                            {@session.user.account.handle}
                          <% else %>
                            {String.capitalize(item.role)}
                          <% end %>
                          <%= if timestamp = format_event_timestamp(item.timestamp) do %>
                            <time
                              class="session-tl-role-time"
                              datetime={event_timestamp_attr(item.timestamp)}
                            >
                              {timestamp}
                            </time>
                          <% end %>
                        </div>
                        <div class="session-tl-body">{item.content}</div>
                      </div>
                    </div>
                  <% :decision -> %>
                    <div class="session-tl-decision">
                      <div class="session-tl-decision-icon">
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          width="16"
                          height="16"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5" /><path d="M9 18h6" /><path d="M10 22h4" />
                        </svg>
                      </div>
                      <div class="session-tl-decision-content">
                        <%= if item.decision do %>
                          <div class="session-tl-decision-title">{item.decision}</div>
                        <% end %>
                        <%= if item.reasoning do %>
                          <div class="session-tl-decision-reasoning">{item.reasoning}</div>
                        <% end %>
                      </div>
                    </div>
                  <% :event -> %>
                    <.render_timeline_event event={item.event} />
                <% end %>
              <% end %>
            </div>

            <%!-- Event streaming (SSE hook) --%>
            <div
              id="session-event-viewer"
              phx-hook="SessionEventViewer"
              data-events-url={~p"/api/sessions/#{@session.session_id}/events/stream"}
              data-after={@event_after_cursor}
              data-max-events={@max_session_events}
              data-target-id="session-timeline"
              data-session-status={@session.status}
            >
              <div class="session-tl-event-controls">
                <span
                  class="session-tl-event-status"
                  data-role="event-status"
                  data-state="connecting"
                >
                  {gettext("Connecting...")}
                </span>
                <div
                  class="session-tl-event-filters"
                  role="group"
                  aria-label={gettext("Filter session events")}
                >
                  <%= for type <- @event_types do %>
                    <label class="session-tl-event-filter">
                      <input type="checkbox" name="event-types" value={type} checked />
                      {String.capitalize(type)}
                    </label>
                  <% end %>
                </div>
              </div>
              <p
                class="session-tl-event-empty"
                data-role="event-empty"
                hidden={Enum.any?(@event_snapshot)}
              >
                {gettext("No events yet.")}
              </p>
            </div>

            <%!-- Changes file tree --%>
            <section class="session-changes-section">
              <div class="session-changes-header">
                <h2>{gettext("Changes")}</h2>
                <%= if @change_stats.total > 0 do %>
                  <div class="session-changes-stats">
                    <%= if @change_stats.added > 0 do %>
                      <span class="session-changes-stat-added">+{@change_stats.added}</span>
                    <% end %>
                    <%= if @change_stats.modified > 0 do %>
                      <span class="session-changes-stat-modified">~{@change_stats.modified}</span>
                    <% end %>
                    <%= if @change_stats.deleted > 0 do %>
                      <span class="session-changes-stat-deleted">-{@change_stats.deleted}</span>
                    <% end %>
                  </div>
                <% end %>
              </div>
              <%= if @change_stats.total > 0 do %>
                <div class="session-file-tree">
                  <%= for change <- @session.changes do %>
                    <div class="session-file-tree-item">
                      <span class={"session-file-change-badge session-file-change-#{change.change_type}"}>
                        <%= case change.change_type do %>
                          <% "added" -> %>
                            +
                          <% "modified" -> %>
                            ~
                          <% "deleted" -> %>
                            -
                        <% end %>
                      </span>
                      <span class="session-file-path">{change.file_path}</span>
                      <%= if change.metadata["size"] do %>
                        <span class="session-file-size">
                          {format_file_size(change.metadata["size"])}
                        </span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="session-changes-empty">
                  {gettext("No file changes in this session")}
                </p>
              <% end %>
            </section>

            <%!-- Raw metadata (collapsible) --%>
            <%= if @session.metadata && map_size(@session.metadata) > 0 do %>
              <details class="session-raw-metadata">
                <summary>{gettext("Raw metadata")}</summary>
                <pre><code>{Jason.encode!(@session.metadata, pretty: true)}</code></pre>
              </details>
            <% end %>
          </div>

          <%!-- Right sidebar --%>
          <aside class="session-sidebar">
            <div class="session-sidebar-section">
              <span class="session-sidebar-label">{gettext("Status")}</span>
              <span class={"status-badge #{status_badge_class(@session.status)}"}>
                {String.capitalize(@session.status)}
              </span>
            </div>

            <%= if @session.user do %>
              <div class="session-sidebar-section">
                <span class="session-sidebar-label">{gettext("Author")}</span>
                <span class="session-sidebar-value">{@session.user.email}</span>
              </div>
            <% end %>

            <%= if contributor_label(@contributor_type) do %>
              <div class="session-sidebar-section">
                <span class="session-sidebar-label">{gettext("Attribution")}</span>
                <div class="session-sidebar-value">
                  <div>
                    <span class="session-sidebar-badge">
                      <%= if @contributor_type in ["ai", "mixed"] do %>
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          width="12"
                          height="12"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <path d="M12 8V4H8" /><rect
                            width="16"
                            height="12"
                            x="4"
                            y="8"
                            rx="2"
                          /><path d="M2 14h2" /><path d="M20 14h2" /><path d="M15 13v2" /><path d="M9 13v2" />
                        </svg>
                      <% else %>
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          width="12"
                          height="12"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" /><circle
                            cx="12"
                            cy="7"
                            r="4"
                          />
                        </svg>
                      <% end %>
                      {contributor_label(@contributor_type)}
                    </span>
                  </div>
                  <%= if @model_id do %>
                    <div style="margin-top: 4px;">
                      <span class="session-sidebar-badge">{@model_id}</span>
                    </div>
                  <% end %>
                  <%= if @tool_name do %>
                    <div style="margin-top: 4px;">
                      <span class="session-sidebar-value">{@tool_name}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @change_stats.total > 0 do %>
              <div class="session-sidebar-section">
                <span class="session-sidebar-label">{gettext("Changes")}</span>
                <div class="session-sidebar-changes">
                  <%= if @change_stats.added > 0 do %>
                    <span class="session-changes-stat-added">
                      +{@change_stats.added} {gettext("added")}
                    </span>
                  <% end %>
                  <%= if @change_stats.modified > 0 do %>
                    <span class="session-changes-stat-modified">
                      ~{@change_stats.modified} {gettext("modified")}
                    </span>
                  <% end %>
                  <%= if @change_stats.deleted > 0 do %>
                    <span class="session-changes-stat-deleted">
                      -{@change_stats.deleted} {gettext("deleted")}
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @session.prompt_request do %>
              <div class="session-sidebar-section">
                <span class="session-sidebar-label">{gettext("Prompt Request")}</span>
                <.link
                  navigate={
                    ~p"/projects/#{@organization.account.handle}/#{@repository.handle}/prompt-requests/#{@session.prompt_request.id}"
                  }
                  class="session-prompt-request-link"
                  id="session-prompt-request-link"
                >
                  {prompt_request_title(@session.prompt_request)}
                </.link>
              </div>
            <% end %>

            <%= if @session.status == "active" do %>
              <div class="session-sidebar-section">
                <span class="session-sidebar-label">{gettext("Actions")}</span>
                <div class="session-sidebar-actions">
                  <button
                    type="button"
                    class="session-action session-action-abandon"
                    phx-click="abandon"
                    phx-confirm={gettext("Abandon this session?")}
                  >
                    {gettext("Abandon")}
                  </button>
                </div>
              </div>
            <% end %>
          </aside>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp render_timeline_event(assigns) do
    ~H"""
    <%= case event_type(@event) do %>
      <% "output" -> %>
        <% output = event_output_text(@event) %>
        <%= if output do %>
          <div class="session-tl-tool-call" data-type="output">
            <details open={output_open?(output)}>
              <summary class="session-tl-tool-summary">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="14"
                  height="14"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <polyline points="4 17 10 11 4 5" /><line x1="12" x2="20" y1="19" y2="19" />
                </svg>
                <span>{gettext("Output")}</span>
                <%= if stream = event_output_stream(@event) do %>
                  <span class="session-tl-stream-badge">{String.upcase(stream)}</span>
                <% end %>
                <%= if timestamp = format_event_timestamp(@event["timestamp"]) do %>
                  <time
                    class="session-tl-tool-time"
                    datetime={event_timestamp_attr(@event["timestamp"])}
                  >
                    {timestamp}
                  </time>
                <% end %>
              </summary>
              <pre class="session-tl-tool-output">{output}</pre>
            </details>
          </div>
        <% end %>
      <% "status" -> %>
        <div class="session-tl-status" data-type="status">
          <span class="session-tl-status-dot"></span>
          <span class="session-tl-status-text">{event_summary(@event)}</span>
          <%= if timestamp = format_event_timestamp(@event["timestamp"]) do %>
            <time
              class="session-tl-status-time"
              datetime={event_timestamp_attr(@event["timestamp"])}
            >
              {timestamp}
            </time>
          <% end %>
        </div>
      <% "error" -> %>
        <div class="session-tl-error" data-type="error">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <circle cx="12" cy="12" r="10" /><line x1="12" x2="12" y1="8" y2="12" /><line
              x1="12"
              x2="12.01"
              y1="16"
              y2="16"
            />
          </svg>
          <span>{event_summary(@event)}</span>
          <%= if timestamp = format_event_timestamp(@event["timestamp"]) do %>
            <time
              class="session-tl-event-time"
              datetime={event_timestamp_attr(@event["timestamp"])}
            >
              {timestamp}
            </time>
          <% end %>
        </div>
      <% "progress" -> %>
        <% percent = event_progress_percent(@event) %>
        <div class="session-tl-progress" data-type="progress">
          <%= if percent do %>
            <div
              class="session-tl-progress-track"
              role="progressbar"
              aria-valuemin="0"
              aria-valuemax="100"
              aria-valuenow={percent}
            >
              <div class="session-tl-progress-bar" style={"width: #{percent}%"}></div>
            </div>
            <span class="session-tl-progress-label">{format_percent(percent)}</span>
          <% end %>
          <% summary = event_summary(@event) %>
          <%= if summary != "" do %>
            <span class="session-tl-progress-message">{summary}</span>
          <% end %>
          <%= if timestamp = format_event_timestamp(@event["timestamp"]) do %>
            <time
              class="session-tl-event-time"
              datetime={event_timestamp_attr(@event["timestamp"])}
            >
              {timestamp}
            </time>
          <% end %>
        </div>
      <% "artifact" -> %>
        <% payload = event_payload(@event) %>
        <%= if uri = artifact_uri(payload) do %>
          <div class="session-tl-artifact" data-type="artifact">
            <%= if artifact_image?(payload) do %>
              <a class="session-tl-artifact-link" href={uri} target="_blank" rel="noopener">
                <img
                  class="session-tl-artifact-image"
                  src={uri}
                  alt={artifact_label(payload)}
                  loading="lazy"
                />
              </a>
            <% else %>
              <a class="session-tl-artifact-link" href={uri} target="_blank" rel="noopener">
                {artifact_label(payload)}
              </a>
            <% end %>
            <% detail = artifact_detail(payload) %>
            <%= if detail != "" do %>
              <div class="session-tl-artifact-meta">{detail}</div>
            <% end %>
            <%= if timestamp = format_event_timestamp(@event["timestamp"]) do %>
              <time
                class="session-tl-event-time"
                datetime={event_timestamp_attr(@event["timestamp"])}
              >
                {timestamp}
              </time>
            <% end %>
          </div>
        <% end %>
      <% _ -> %>
        <div class="session-tl-status" data-type={event_type(@event)}>
          <span class="session-tl-status-dot"></span>
          <span class="session-tl-status-text">{event_summary(@event)}</span>
        </div>
    <% end %>
    """
  end
end
