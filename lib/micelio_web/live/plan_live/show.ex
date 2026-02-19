defmodule MicelioWeb.PlanLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Plans
  alias MicelioWeb.PageMeta

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns[:current_user]
    number_str = params["number"]

    with {:ok, repository, organization} <-
           MicelioWeb.RepositoryResolver.resolve(params, socket.assigns),
         {number, ""} <- Integer.parse(number_str),
         %{} = plan <-
           Plans.get_plan_by_number(repository, number) do
      base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)

      can_edit =
        current_user != nil and
          Authorization.authorize(:repository_read, current_user, repository) == :ok and
          plan.user_id == current_user.id

      messages = Plans.list_plan_messages(plan)
      comments = Plans.list_plan_comments(plan)
      sandbox_running = plan.sandbox_status in ["running", "provisioning"]

      socket =
        socket
        |> assign(:page_title, plan.title)
        |> assign(:base_path, base_path)
        |> PageMeta.assign(
          description: plan.title,
          canonical_url:
            unverified_url(MicelioWeb.Endpoint, "#{base_path}/prompt-requests/#{plan.number}")
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:plan, plan)
        |> assign(:can_edit, can_edit)
        |> assign(:sandbox_running, sandbox_running)
        |> assign(:has_messages, messages != [])
        |> assign(:comments, comments)
        |> assign(:agent_status, if(sandbox_running, do: "connecting", else: "idle"))
        |> assign(:chat_input, "")
        |> assign(:comment_input, "")
        |> stream(:messages, messages)

      {plan, socket} =
        if can_edit and should_ensure_pull_request?(plan) do
          case Plans.ensure_plan_forge_pull_request(plan, current_user) do
            {:ok, updated_plan} ->
              {updated_plan, assign(socket, :plan, updated_plan)}

            {:error, _reason} ->
              {plan, socket}
          end
        else
          {plan, socket}
        end

      socket =
        if sandbox_running do
          case Plans.reconnect_agentic_session(plan, notify_pid: self()) do
            :ok ->
              assign(socket, :agent_status, "connected")

            {:error, _} ->
              # Agent process is gone (server restart, crash, etc.) - reset DB status
              Plans.reset_stale_sandbox(plan)
              assign(socket, sandbox_running: false, agent_status: "idle")
          end
        else
          socket
        end

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Prompt request not found."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  # --- Plan Actions ---

  @impl true
  def handle_event("close", _params, socket) do
    plan = socket.assigns.plan

    case Plans.close_plan(plan) do
      {:ok, updated} ->
        {:noreply, assign(socket, :plan, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to close prompt request."))}
    end
  end

  @impl true
  def handle_event("reopen", _params, socket) do
    plan = socket.assigns.plan

    case Plans.reopen_plan(plan) do
      {:ok, updated} ->
        {:noreply, assign(socket, :plan, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to reopen prompt request."))}
    end
  end

  # --- Agentic Session Actions ---

  @impl true
  def handle_event("start_session", _params, socket) do
    plan = socket.assigns.plan
    current_user = socket.assigns.current_user

    socket = assign(socket, :agent_status, "connecting")

    case Plans.start_agentic_session(plan,
           user: current_user,
           notify_pid: self(),
           account: socket.assigns.organization.account
         ) do
      {:ok, updated_plan} ->
        {:noreply,
         socket
         |> assign(:plan, updated_plan)
         |> assign(:sandbox_running, true)}

      {:error, :max_concurrent_reached} ->
        {:noreply,
         socket
         |> assign(:agent_status, "idle")
         |> put_flash(:error, gettext("You already have an active session. Stop it first."))}

      {:error, :daily_limit_reached} ->
        {:noreply,
         socket
         |> assign(:agent_status, "idle")
         |> put_flash(:error, gettext("Daily session limit reached. Try again tomorrow."))}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(:agent_status, "idle")
         |> put_flash(:error, gettext("You need write access to start a coding session."))}

      {:error, :integration_required} ->
        {:noreply,
         socket
         |> assign(:agent_status, "idle")
         |> put_flash(
           :error,
           gettext("Install and authorize the forge app to open a draft PR first.")
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:agent_status, "idle")
         |> put_flash(
           :error,
           gettext("Failed to start session: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @impl true
  def handle_event("stop_session", _params, socket) do
    plan = socket.assigns.plan

    case Plans.stop_agentic_session(plan) do
      {:ok, updated_plan} ->
        {:noreply,
         socket
         |> assign(:plan, updated_plan)
         |> assign(:sandbox_running, false)
         |> assign(:has_messages, true)
         |> assign(:agent_status, "idle")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to stop session."))}
    end
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      plan = socket.assigns.plan
      sequence = Plans.next_message_sequence(plan)

      case Plans.create_plan_message(plan, %{
             role: "human",
             content: content,
             author: socket.assigns.current_user.email,
             status: "complete",
             sequence: sequence
           }) do
        {:ok, message} ->
          socket =
            socket
            |> stream_insert(:messages, message)
            |> assign(:chat_input, "")
            |> assign(:has_messages, true)

          socket =
            case Plans.send_agentic_message(plan, content) do
              :ok -> assign(socket, :agent_status, "streaming")
              {:error, _} -> socket
            end

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to send message."))}
      end
    end
  end

  @impl true
  def handle_event("add_comment", %{"content" => content}, socket) do
    plan = socket.assigns.plan
    user = socket.assigns.current_user

    case Plans.add_plan_comment(plan, user, %{"content" => content}) do
      {:ok, comment} ->
        {:noreply,
         socket
         |> update(:comments, fn comments -> comments ++ [comment] end)
         |> assign(:comment_input, "")}

      {:error, :empty_comment} ->
        {:noreply, put_flash(socket, :error, gettext("Comment cannot be empty."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to post comment."))}
    end
  end

  # --- Agent Event Handlers ---

  @impl true
  def handle_info({:agent_event, :connected}, socket) do
    {:noreply, assign(socket, :agent_status, "connected")}
  end

  def handle_info({:agent_event, {:init, _session_id}}, socket) do
    {:noreply, assign(socket, :agent_status, "streaming")}
  end

  def handle_info({:agent_event, {:streaming, message}}, socket) do
    {:noreply,
     socket
     |> stream_insert(:messages, message)
     |> assign(:agent_status, "streaming")}
  end

  def handle_info({:agent_event, {:message_finalized, message}}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_info({:agent_event, {:complete, _result}}, socket) do
    {:noreply, assign(socket, :agent_status, "connected")}
  end

  def handle_info({:agent_event, :idle}, socket) do
    {:noreply, assign(socket, :agent_status, "connected")}
  end

  def handle_info({:agent_event, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:agent_status, "error")
     |> put_flash(:error, gettext("Agent error: %{reason}", reason: to_string(reason)))}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={assigns[:current_scope]}
      current_user={assigns[:current_user]}
      locale={assigns[:locale] || "en"}
      current_path={assigns[:current_path] || "/"}
      repository_nav={
        %{
          account_handle: @organization.account.handle,
          repository_handle: @repository.handle,
          active: :prompt_requests,
          show_settings?: @current_user != nil,
          base_path: @base_path
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:plans}
        base_path={@base_path}
      >
        <div class={["plan-show", @sandbox_running && "plan-show--session-active"]}>
          <%!-- Header --%>
          <div class="plan-show-header">
            <div class="plan-show-title-row">
              <h1 class="plan-show-title">
                {@plan.title}
                <span class="plan-show-number">#{@plan.number}</span>
              </h1>
              <span class={"pr-status-badge pr-status-badge-#{@plan.status}"}>
                {String.capitalize(@plan.status)}
              </span>
            </div>
            <div class="plan-show-header-actions">
              <div class="plan-show-meta">
                {gettext("Opened %{time_ago} by %{author}",
                  time_ago: format_time_ago(@plan.inserted_at),
                  author: @plan.user.email
                )}
              </div>
              <div class="plan-show-resource-links">
                <.link
                  :if={@plan.forge_pr_url}
                  href={@plan.forge_pr_url}
                  class="repository-button repository-button-secondary"
                  target="_blank"
                  rel="noreferrer"
                >
                  {gettext("View draft PR")}
                </.link>
                <.link
                  :if={sandbox_preview_url(@plan)}
                  href={sandbox_preview_url(@plan)}
                  class="repository-button repository-button-secondary"
                  target="_blank"
                  rel="noreferrer"
                >
                  {gettext("Open preview")}
                </.link>
                <.link
                  :if={sandbox_dashboard_url(@plan)}
                  href={sandbox_dashboard_url(@plan)}
                  class="repository-button repository-button-secondary"
                  target="_blank"
                  rel="noreferrer"
                >
                  {gettext("Open sandbox")}
                </.link>
              </div>
              <%= if @can_edit do %>
                <div class="plan-show-actions">
                  <.link
                    navigate={"#{@base_path}/prompt-requests/#{@plan.number}/edit"}
                    class="repository-button repository-button-secondary"
                    id="edit-plan"
                  >
                    {gettext("Edit")}
                  </.link>
                  <%= if @plan.status == "open" do %>
                    <button
                      phx-click="close"
                      class="repository-button repository-button-secondary"
                      id="close-plan"
                    >
                      {gettext("Close")}
                    </button>
                  <% else %>
                    <button
                      phx-click="reopen"
                      class="repository-button repository-button-secondary"
                      id="reopen-plan"
                    >
                      {gettext("Reopen")}
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Plan body (shown when not in active session) --%>
          <%= if !@sandbox_running do %>
            <%= if @plan.description do %>
              <div class="plan-show-body" id="plan-description">
                <div class="plan-show-body-content">
                  {raw(render_markdown(@plan.description))}
                </div>
              </div>
            <% end %>

            <%= if @can_edit do %>
              <div class="plan-show-session-controls">
                <button
                  phx-click="start_session"
                  class="repository-button"
                  id="start-session"
                >
                  <svg
                    width="16"
                    height="16"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    style="display:inline;vertical-align:middle;margin-right:4px"
                  >
                    <polygon points="5 3 19 12 5 21 5 3" />
                  </svg>
                  {gettext("Start agentic session")}
                </button>
              </div>
            <% end %>

            <div class="plan-comments-section" id="plan-comments">
              <h3 class="plan-history-section-title">{gettext("Comments")}</h3>
              <%= if Enum.empty?(@comments) do %>
                <p class="plan-comments-empty">{gettext("No comments yet.")}</p>
              <% else %>
                <div class="plan-comments-list">
                  <div
                    :for={comment <- @comments}
                    class="plan-comment-item"
                    id={"comment-#{comment.id}"}
                  >
                    <div class="plan-comment-meta">
                      <span class="plan-comment-author">{comment.author || gettext("User")}</span>
                      <span class="plan-comment-date">
                        {format_time_ago(comment.inserted_at)}
                      </span>
                    </div>
                    <div class="plan-comment-content">{comment.content}</div>
                  </div>
                </div>
              <% end %>

              <form :if={@current_user} phx-submit="add_comment" class="plan-comment-form">
                <textarea
                  name="content"
                  rows="3"
                  placeholder={gettext("Add a comment")}
                  class="plan-chat-textarea"
                ></textarea>
                <div class="plan-comment-actions">
                  <button type="submit" class="repository-button">
                    {gettext("Comment")}
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <%!-- Session history (non-interactive, shown when not in session and messages exist) --%>
          <%= if !@sandbox_running && @has_messages do %>
            <div class="plan-history-section">
              <h3 class="plan-history-section-title">{gettext("Session history")}</h3>
            </div>
          <% end %>

          <%!-- Messages container (always present for stream, styled differently) --%>
          <div
            id="plan-terminal-output"
            phx-update="stream"
            phx-hook=".PlanShowScroll"
            class={[
              if(@sandbox_running, do: "plan-terminal-output", else: "plan-history"),
              !@sandbox_running && !@has_messages && "plan-messages-empty"
            ]}
          >
            <div
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class={
                if(@sandbox_running,
                  do: "plan-terminal-entry plan-terminal-entry--#{message.role}",
                  else: "plan-history-entry plan-history-entry--#{message.role}"
                )
              }
            >
              <%= if @sandbox_running do %>
                <%!-- Interactive terminal mode --%>
                <%= if message.role == "human" do %>
                  <div class="plan-terminal-prompt-line">
                    <span class="plan-terminal-prompt-marker">&gt;</span>
                    <span class="plan-terminal-prompt-text">{message.content || ""}</span>
                  </div>
                <% else %>
                  <div class="plan-terminal-agent-output">
                    <span
                      :if={message.status == "streaming"}
                      class="plan-terminal-cursor"
                    >
                    </span>
                    <div class="plan-terminal-markdown">
                      {raw(render_markdown(message.content))}
                    </div>
                  </div>
                <% end %>
              <% else %>
                <%!-- Non-interactive history mode --%>
                <%= if message.role == "human" do %>
                  <div class="plan-history-human">
                    <span class="plan-history-author">{message.author || gettext("User")}</span>
                    <div class="plan-history-human-content">{message.content || ""}</div>
                  </div>
                <% else %>
                  <div class="plan-history-agent">
                    <span class="plan-history-author">{gettext("Agent")}</span>
                    <div class="plan-history-agent-content plan-terminal-markdown">
                      {raw(render_markdown(message.content))}
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Input bar (only during active session) --%>
          <%= if @sandbox_running && @can_edit do %>
            <form
              phx-submit="send_message"
              class="plan-terminal-input-bar"
              id="plan-chat-form"
            >
              <div class="plan-terminal-input-status">
                <span class={"plan-terminal-status-dot plan-terminal-status-dot--#{@agent_status}"}>
                </span>
                <span class="plan-terminal-status-label">
                  <%= case @agent_status do %>
                    <% "connecting" -> %>
                      {gettext("Connecting...")}
                    <% "connected" -> %>
                      {gettext("Ready")}
                    <% "streaming" -> %>
                      {gettext("Working...")}
                    <% "error" -> %>
                      {gettext("Error")}
                    <% _ -> %>
                      {gettext("Idle")}
                  <% end %>
                </span>
              </div>
              <div class="plan-terminal-input-row">
                <span class="plan-terminal-input-chevron">&gt;</span>
                <input
                  type="text"
                  id="plan-chat-input"
                  name="content"
                  placeholder={gettext("Type a message...")}
                  class="plan-terminal-input"
                  disabled={@agent_status == "streaming"}
                  autocomplete="off"
                  phx-hook=".PlanShowFocus"
                />
                <button
                  type="submit"
                  class="plan-terminal-send-btn"
                  disabled={@agent_status == "streaming"}
                  aria-label={gettext("Send")}
                >
                  <svg
                    width="16"
                    height="16"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <line x1="5" y1="12" x2="19" y2="12" /><polyline points="12 5 19 12 12 19" />
                  </svg>
                </button>
              </div>
              <div class="plan-terminal-input-actions">
                <button
                  type="button"
                  phx-click="stop_session"
                  class="plan-terminal-stop-btn"
                  id="stop-session"
                >
                  {gettext("Stop session")}
                </button>
              </div>
            </form>
          <% end %>
        </div>
      </.repository_header>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PlanShowScroll">
        export default {
          mounted() { this.el.scrollTop = this.el.scrollHeight; },
          updated() { this.el.scrollTop = this.el.scrollHeight; }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PlanShowFocus">
        export default {
          mounted() {
            this.el.focus();
          },
          updated() {
            if (!this.el.disabled) this.el.focus();
          }
        }
      </script>
    </Layouts.app>
    """
  end

  # --- Private Helpers ---

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(content) do
    case MicelioWeb.Markdown.render(content) do
      {:ok, html} -> html
      {:error, html} -> html
    end
  end

  defp format_time_ago(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> gettext("just now")
      diff < 3600 -> gettext("%{count} minutes ago", count: div(diff, 60))
      diff < 86_400 -> gettext("%{count} hours ago", count: div(diff, 3600))
      diff < 2_592_000 -> gettext("%{count} days ago", count: div(diff, 86_400))
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp format_time_ago(_), do: ""

  defp should_ensure_pull_request?(plan) do
    plan.forge_pr_url in [nil, ""] and plan.forge_pr_provider in [nil, "github", "gitlab"]
  end

  defp sandbox_preview_url(plan), do: sandbox_metadata_url(plan, "preview_url")
  defp sandbox_dashboard_url(plan), do: sandbox_metadata_url(plan, "dashboard_url")

  defp sandbox_metadata_url(%{sandbox_metadata: metadata}, key) when is_map(metadata) do
    value =
      case key do
        "preview_url" -> Map.get(metadata, "preview_url") || Map.get(metadata, :preview_url)
        "dashboard_url" -> Map.get(metadata, "dashboard_url") || Map.get(metadata, :dashboard_url)
        _ -> nil
      end

    normalize_sandbox_url(value)
  end

  defp sandbox_metadata_url(_, _), do: nil

  defp normalize_sandbox_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    if trimmed != "", do: trimmed
  end

  defp normalize_sandbox_url(_), do: nil
end
