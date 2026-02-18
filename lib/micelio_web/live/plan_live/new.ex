defmodule MicelioWeb.PlanLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.LLM
  alias Micelio.Plans
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => org_handle, "repository" => repository_handle}, _session, socket) do
    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             repository_handle
           ),
         :ok <- Authorization.authorize(:repository_read, socket.assigns.current_user, repository) do
      account = organization.account
      available_models = LLM.repository_models_for_account(account)
      default_model = LLM.repository_default_model_for_account(account)

      socket =
        socket
        |> assign(:page_title, gettext("New Plan"))
        |> PageMeta.assign(
          description: gettext("Create a plan for %{name}.", name: repository.name),
          canonical_url: url(~p"/#{organization.account.handle}/#{repository.handle}/prs/new")
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:plan, nil)
        |> assign(:plan_loading, true)
        |> assign(:available_models, available_models)
        |> assign(:selected_model, default_model)
        |> assign(:agent_status, "idle")
        |> assign(:chat_input, "")
        |> assign(:show_model_menu, false)
        |> assign(:first_message_sent, false)
        |> assign(:sandbox_running, false)

      if connected?(socket) do
        case Plans.create_simple_plan(
               %{title: gettext("Untitled plan")},
               repository: repository,
               user: socket.assigns.current_user
             ) do
          {:ok, plan} ->
            {:ok,
             socket
             |> assign(:plan, plan)
             |> assign(:plan_loading, false)
             |> stream(:messages, [])}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Unable to create plan."))
             |> push_navigate(to: ~p"/#{org_handle}/#{repository_handle}/prs")}
        end
      else
        {:ok, socket}
      end
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Repository not found or access denied."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      plan = socket.assigns.plan

      socket =
        if socket.assigns.first_message_sent do
          socket
        else
          title = String.slice(content, 0, 80)
          Plans.update_plan_title(plan, title)

          assign(socket, :plan, %{plan | title: title})
          |> assign(:first_message_sent, true)
        end

      # Start agentic session if not already running
      socket =
        if socket.assigns.sandbox_running do
          socket
        else
          socket = assign(socket, :agent_status, "connecting")

          case Plans.start_agentic_session(plan,
                 user: socket.assigns.current_user,
                 notify_pid: self(),
                 account: socket.assigns.organization.account,
                 model: socket.assigns.selected_model
               ) do
            {:ok, updated_plan} ->
              socket
              |> assign(:plan, updated_plan)
              |> assign(:sandbox_running, true)

            {:error, :max_concurrent_reached} ->
              socket
              |> assign(:agent_status, "idle")
              |> put_flash(:error, gettext("You already have an active session. Stop it first."))

            {:error, :daily_limit_reached} ->
              socket
              |> assign(:agent_status, "idle")
              |> put_flash(:error, gettext("Daily session limit reached. Try again tomorrow."))

            {:error, :forbidden} ->
              socket
              |> assign(:agent_status, "idle")
              |> put_flash(:error, gettext("You need write access to start a coding session."))

            {:error, :integration_required} ->
              socket
              |> assign(:agent_status, "idle")
              |> put_flash(
                :error,
                gettext("Install and authorize the forge app to open a draft PR first.")
              )

            {:error, reason} ->
              socket
              |> assign(:agent_status, "idle")
              |> put_flash(
                :error,
                gettext("Failed to start session: %{reason}", reason: inspect(reason))
              )
          end
        end

      if socket.assigns.sandbox_running do
        sequence = Plans.next_message_sequence(socket.assigns.plan)

        case Plans.create_plan_message(socket.assigns.plan, %{
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

            socket =
              case Plans.send_agentic_message(socket.assigns.plan, content) do
                :ok -> assign(socket, :agent_status, "streaming")
                {:error, _} -> socket
              end

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to send message."))}
        end
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("stop_agent", _params, socket) do
    plan = socket.assigns.plan

    case Plans.stop_agentic_session(plan) do
      {:ok, updated_plan} ->
        {:noreply,
         socket
         |> assign(:plan, updated_plan)
         |> assign(:sandbox_running, false)
         |> assign(:agent_status, "idle")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to stop session."))}
    end
  end

  @impl true
  def handle_event("toggle_model_menu", _params, socket) do
    {:noreply, assign(socket, :show_model_menu, !socket.assigns.show_model_menu)}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply,
     socket
     |> assign(:selected_model, model)
     |> assign(:show_model_menu, false)}
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
          show_settings?: @current_user != nil
        }
      }
    >
      <%= if @plan_loading do %>
        <div class="plan-chat-page">
          <div class="plan-chat-header">
            <div class="plan-chat-header-left">
              <h2>{gettext("Preparing plan...")}</h2>
            </div>
          </div>
        </div>
      <% else %>
        <div class="plan-chat-page">
          <div class="plan-chat-header">
            <div class="plan-chat-header-left">
              <.link
                navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/prs"}
                class="plan-chat-back-link"
                aria-label={gettext("Back to plans")}
              >
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M19 12H5" /><path d="M12 19l-7-7 7-7" />
                </svg>
              </.link>
              <h2>{@plan.title}</h2>
              <span class={"plan-chat-status plan-chat-status--#{@agent_status}"}>
                <%= case @agent_status do %>
                  <% "connecting" -> %>
                    {gettext("Connecting...")}
                  <% "connected" -> %>
                    {gettext("Connected")}
                  <% "streaming" -> %>
                    {gettext("Thinking...")}
                  <% "error" -> %>
                    {gettext("Error")}
                  <% _ -> %>
                    {gettext("Idle")}
                <% end %>
              </span>
            </div>
            <div class="plan-chat-header-actions">
              <button
                :if={@sandbox_running}
                phx-click="stop_agent"
                class="repository-button repository-button-secondary plan-chat-header-btn"
              >
                {gettext("Stop")}
              </button>
              <.link
                navigate={
                  ~p"/#{@organization.account.handle}/#{@repository.handle}/prs/#{@plan.number}"
                }
                class="repository-button plan-chat-header-btn"
              >
                {gettext("View plan")}
              </.link>
            </div>
          </div>

          <div
            id="plan-chat-messages"
            phx-update="stream"
            phx-hook=".PlanChatScroll"
            class="plan-chat-messages"
          >
            <div
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class={"plan-chat-message plan-chat-message--#{message.role}"}
            >
              <div :if={message.role == "assistant"} class="plan-chat-message-header">
                <span class="plan-chat-message-role">{gettext("Agent")}</span>
                <span :if={message.status == "streaming"} class="plan-chat-typing-indicator">
                  <span></span><span></span><span></span>
                </span>
              </div>
              <div class="plan-chat-message-content">
                {message.content || ""}
              </div>
            </div>
          </div>

          <form phx-submit="send_message" class="plan-chat-input-box" id="plan-chat-form">
            <textarea
              id="plan-chat-input"
              name="content"
              rows="3"
              placeholder={gettext("Describe what you want to build...")}
              class="plan-chat-textarea"
              disabled={@agent_status == "streaming"}
              phx-hook=".PlanChatSubmit"
            ></textarea>
            <div class="plan-chat-toolbar">
              <div class="plan-chat-toolbar-left">
                <%= if @available_models != [] do %>
                  <div class="plan-chat-model-picker" id="model-picker">
                    <button
                      type="button"
                      class="plan-chat-agent-toggle"
                      phx-click="toggle_model_menu"
                      disabled={@sandbox_running}
                    >
                      <.provider_icon provider={
                        provider_for_model(@selected_model, @organization.account.llm_provider)
                      } />
                      <span class="plan-chat-agent-toggle-label">
                        {model_display_label(@selected_model, @organization.account.llm_provider)}
                      </span>
                      <svg
                        class="plan-chat-agent-toggle-caret"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <path d="M6 9l6 6 6-6" />
                      </svg>
                    </button>
                    <div
                      :if={@show_model_menu}
                      class="plan-chat-agent-menu"
                      phx-click-away="toggle_model_menu"
                    >
                      <%= for model <- @available_models do %>
                        <button
                          type="button"
                          class={[
                            "plan-chat-agent-menu-item",
                            @selected_model == model && "plan-chat-agent-menu-item--active"
                          ]}
                          phx-click="select_model"
                          phx-value-model={model}
                        >
                          <.provider_icon provider={
                            provider_for_model(model, @organization.account.llm_provider)
                          } />
                          <span>{model}</span>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
              <button
                type="submit"
                class="plan-chat-send-btn"
                disabled={@agent_status == "streaming"}
                aria-label={gettext("Send")}
              >
                <svg
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z" />
                </svg>
              </button>
            </div>
          </form>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".PlanChatScroll">
          export default {
            mounted() { this.el.scrollTop = this.el.scrollHeight; },
            updated() { this.el.scrollTop = this.el.scrollHeight; }
          }
        </script>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".PlanChatSubmit">
          export default {
            mounted() {
              this.el.addEventListener("keydown", (e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  const form = this.el.closest("form");
                  if (form) form.dispatchEvent(new Event("submit", { bubbles: true }));
                }
              });
            }
          }
        </script>
      <% end %>
    </Layouts.app>
    """
  end

  # --- Private Helpers ---

  defp model_display_label(model, provider) do
    provider_name = provider_label(provider, model)

    if model do
      "#{provider_name} (#{model})"
    else
      provider_name
    end
  end

  defp provider_for_model(model, provider) do
    cond do
      is_binary(provider) and provider != "" ->
        provider

      is_binary(model) and (String.starts_with?(model, "gpt-") or String.starts_with?(model, "o")) ->
        "openai"

      is_binary(model) and String.starts_with?(model, "claude-") ->
        "anthropic"

      is_binary(model) and String.starts_with?(model, "gemini") ->
        "google"

      true ->
        nil
    end
  end

  defp provider_label(provider, _model) when is_binary(provider) and provider != "" do
    String.capitalize(provider)
  end

  defp provider_label(_provider, model) when is_binary(model) do
    cond do
      String.starts_with?(model, "gpt-") or String.starts_with?(model, "o") -> "OpenAI"
      String.starts_with?(model, "claude-") -> "Anthropic"
      String.starts_with?(model, "gemini") -> "Google"
      true -> "AI"
    end
  end

  defp provider_label(_, _), do: "AI"

  defp provider_icon(%{provider: "openai"} = assigns) do
    ~H"""
    <svg class="plan-chat-provider-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M22.282 9.821a5.985 5.985 0 0 0-.516-4.91 6.046 6.046 0 0 0-6.51-2.9A6.065 6.065 0 0 0 4.981 4.18a5.998 5.998 0 0 0-3.998 2.9 6.042 6.042 0 0 0 .743 7.097 5.98 5.98 0 0 0 .51 4.911 6.05 6.05 0 0 0 6.515 2.9A5.985 5.985 0 0 0 13.26 24a6.056 6.056 0 0 0 5.772-4.206 5.99 5.99 0 0 0 3.997-2.9 6.056 6.056 0 0 0-.747-7.073zM13.26 22.43a4.476 4.476 0 0 1-2.876-1.04l.141-.081 4.779-2.758a.795.795 0 0 0 .392-.681v-6.737l2.02 1.168a.071.071 0 0 1 .038.052v5.583a4.504 4.504 0 0 1-4.494 4.494zM3.6 18.304a4.47 4.47 0 0 1-.535-3.014l.142.085 4.783 2.759a.771.771 0 0 0 .78 0l5.843-3.369v2.332a.08.08 0 0 1-.033.062L9.74 19.95a4.5 4.5 0 0 1-6.14-1.646zM2.34 7.896a4.485 4.485 0 0 1 2.366-1.973V11.6a.766.766 0 0 0 .388.677l5.815 3.355-2.02 1.168a.076.076 0 0 1-.071 0l-4.83-2.786A4.504 4.504 0 0 1 2.34 7.872zm16.597 3.855l-5.833-3.387L15.119 7.2a.076.076 0 0 1 .071 0l4.83 2.791a4.494 4.494 0 0 1-.676 8.105v-5.678a.79.79 0 0 0-.407-.667zm2.01-3.023l-.141-.085-4.774-2.782a.776.776 0 0 0-.785 0L9.409 9.23V6.897a.066.066 0 0 1 .028-.061l4.83-2.787a4.5 4.5 0 0 1 6.68 4.66zm-12.64 4.135l-2.02-1.164a.08.08 0 0 1-.038-.057V6.075a4.5 4.5 0 0 1 7.375-3.453l-.142.08L8.704 5.46a.795.795 0 0 0-.393.681zm1.097-2.365l2.602-1.5 2.607 1.5v2.999l-2.597 1.5-2.607-1.5z" />
    </svg>
    """
  end

  defp provider_icon(%{provider: "anthropic"} = assigns) do
    ~H"""
    <svg class="plan-chat-provider-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M13.827 3.52h3.603L24 20.48h-3.603l-6.57-16.96zm-7.258 0h3.767L16.906 20.48h-3.674l-1.634-4.36H6.21l-1.64 4.36H1L6.569 3.52zM9.741 13.3l-2.156-5.753L5.429 13.3h4.312z" />
    </svg>
    """
  end

  defp provider_icon(%{provider: "google"} = assigns) do
    ~H"""
    <svg class="plan-chat-provider-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
    </svg>
    """
  end

  defp provider_icon(assigns) do
    ~H"""
    <svg
      class="plan-chat-provider-icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <rect x="4" y="4" width="16" height="16" rx="2" /><path d="M9 9h6" /><path d="M9 13h6" /><path d="M9 17h4" />
    </svg>
    """
  end
end
