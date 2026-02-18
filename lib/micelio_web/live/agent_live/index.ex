defmodule MicelioWeb.AgentLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.{Authorization, Sessions}
  alias MicelioWeb.PageMeta

  @refresh_ms 5_000

  @impl true
  def mount(params, session, socket) do
    case MicelioWeb.RepositoryResolver.resolve(params, socket.assigns) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_read, socket.assigns.current_user, repository) ==
             :ok do
          base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)
          og_summary_opts = og_summary_opts_from_session(session)

          socket =
            socket
            |> assign(:page_title, "Agent Progress - #{repository.name}")
            |> assign(:base_path, base_path)
            |> PageMeta.assign(
              description: "Live agent progress for #{repository.name}.",
              canonical_url: unverified_url(MicelioWeb.Endpoint, "#{base_path}/agents")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:og_summary_opts, og_summary_opts)
            |> assign(:refresh_ms, @refresh_ms)
            |> assign(:refresh_seconds, div(@refresh_ms, 1000))
            |> assign(:error_boundary_context, %{
              route: "#{base_path}/agents",
              params: params
            })
            |> assign(
              :error_boundary_retry_path,
              "#{base_path}/agents"
            )
            |> assign(
              :error_boundary_user_id,
              socket.assigns.current_user && socket.assigns.current_user.id
            )
            |> assign(:error_boundary_repository_id, repository.id)
            |> load_sessions()
            |> assign_agent_og_summary()

          {:ok, maybe_schedule_refresh(socket)}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/")}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> load_sessions()
      |> maybe_schedule_refresh()

    {:noreply, socket}
  end

  defp maybe_schedule_refresh(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    socket
  end

  defp load_sessions(socket) do
    repository = socket.assigns.repository

    sessions =
      Sessions.list_sessions_for_repository_with_details(repository,
        status: "active",
        sort: :newest
      )
      |> Enum.map(&build_session_snapshot/1)

    stats = build_agent_og_stats(sessions)

    socket
    |> assign(
      sessions: sessions,
      refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> PageMeta.assign(open_graph: %{image_template: "agent_progress", image_stats: stats})
  end

  defp assign_agent_og_summary(socket) do
    case Sessions.og_summary_for_sessions(
           socket.assigns.sessions,
           socket.assigns.og_summary_opts || []
         ) do
      {:ok, summary} when is_binary(summary) and summary != "" ->
        PageMeta.assign(socket, description: summary)

      _ ->
        socket
    end
  end

  defp og_summary_opts_from_session(session) do
    session
    |> Map.get("og_summary_opts", Map.get(session, :og_summary_opts))
    |> normalize_og_summary_opts()
  end

  defp normalize_og_summary_opts(nil), do: []
  defp normalize_og_summary_opts(opts) when is_list(opts), do: opts
  defp normalize_og_summary_opts(opts) when is_map(opts), do: Enum.to_list(opts)
  defp normalize_og_summary_opts(_opts), do: []

  defp build_session_snapshot(session) do
    last_message =
      case session.conversation do
        [_ | _] = messages ->
          message = List.last(messages) || %{}

          %{
            role: message["role"] || "agent",
            content: message["content"]
          }

        _ ->
          nil
      end

    %{
      session: session,
      agent: agent_label(session.user),
      message_count: length(session.conversation),
      decision_count: length(session.decisions),
      change_count: length(session.changes),
      last_message: last_message
    }
  end

  defp build_agent_og_stats(sessions) when is_list(sessions) do
    commits =
      sessions
      |> Enum.count(fn entry -> entry.change_count > 0 end)

    files =
      sessions
      |> Enum.flat_map(&session_file_paths/1)
      |> MapSet.new()
      |> MapSet.size()

    %{commits: commits, files: files}
  end

  defp session_file_paths(%{session: %{changes: changes}}) when is_list(changes) do
    changes
    |> Enum.map(& &1.file_path)
    |> Enum.filter(&is_binary/1)
  end

  defp session_file_paths(_), do: []

  defp agent_label(%{account: %{handle: handle}}) when is_binary(handle), do: "@#{handle}"
  defp agent_label(%{email: email}) when is_binary(email), do: email
  defp agent_label(_), do: "Unknown agent"

  defp format_datetime(nil), do: "-"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S")
  end

  defp truncate_text(nil, _max), do: nil

  defp truncate_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
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
          active: :sessions,
          show_settings?: @current_user != nil,
          base_path: @base_path
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:sessions}
        base_path={@base_path}
      >
        <.error_boundary
          id="agent-progress-boundary"
          context={@error_boundary_context}
          retry_path={@error_boundary_retry_path}
          user_id={@error_boundary_user_id}
          repository_id={@error_boundary_repository_id}
        >
          <div class="agent-progress" id="agent-progress">
            <header class="agent-progress-header" id="agent-progress-header">
              <div>
                <div class="agent-progress-breadcrumb" id="agent-progress-breadcrumb">
                  <.link navigate={~p"/#{@organization.account.handle}"}>{@organization.name}</.link>
                  <span>/</span>
                  <.link navigate={@base_path}>
                    {@repository.name}
                  </.link>
                  <span>/</span>
                  <span>Agents</span>
                </div>
                <h1>Agent progress</h1>
                <p class="agent-progress-subtitle">
                  Live sessions running for {@repository.name}.
                </p>
              </div>
              <div class="agent-progress-meta" id="agent-progress-meta">
                <span>Updated {format_datetime(@refreshed_at)}</span>
                <span>Refreshes every {@refresh_seconds}s</span>
              </div>
            </header>

            <section class="agent-progress-section" id="agent-progress-section">
              <div class="agent-progress-section-header">
                <h2>Active sessions</h2>
                <span class="badge badge--caps" id="agent-progress-count">
                  {length(@sessions)} active
                </span>
              </div>

              <%= if Enum.empty?(@sessions) do %>
                <div class="agent-progress-empty" id="agent-progress-empty">
                  <p>No active agent sessions yet.</p>
                </div>
              <% else %>
                <div class="agent-progress-list" id="agent-progress-list">
                  <%= for entry <- @sessions do %>
                    <article class="agent-progress-card" id={"agent-session-#{entry.session.id}"}>
                      <div class="agent-progress-card-header">
                        <div>
                          <h3 class="agent-progress-goal">{entry.session.goal}</h3>
                          <div class="agent-progress-agent">{entry.agent}</div>
                        </div>
                        <span class="badge badge--caps agent-progress-status">active</span>
                      </div>
                      <div class="agent-progress-card-meta">
                        <span>Started {format_datetime(entry.session.started_at)}</span>
                        <span>Updated {format_datetime(entry.session.updated_at)}</span>
                      </div>
                      <div class="agent-progress-card-stats">
                        <span>{entry.message_count} messages</span>
                        <span>{entry.decision_count} decisions</span>
                        <span>{entry.change_count} changes</span>
                      </div>
                      <%= if entry.last_message do %>
                        <div class="agent-progress-message">
                          <span class="agent-progress-message-role">
                            {String.capitalize(entry.last_message.role)}
                          </span>
                          <span class="agent-progress-message-content">
                            {truncate_text(entry.last_message.content, 180)}
                          </span>
                        </div>
                      <% else %>
                        <p class="agent-progress-message-empty">No updates yet.</p>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              <% end %>
            </section>
          </div>
        </.error_boundary>
      </.repository_header>
    </Layouts.app>
    """
  end
end
