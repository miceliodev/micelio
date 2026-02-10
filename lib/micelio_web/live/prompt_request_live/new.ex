defmodule MicelioWeb.PromptRequestLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{"organization_handle" => org_handle, "repository_handle" => repository_handle},
        _session,
        socket
      ) do
    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             repository_handle
           ),
         :ok <- Authorization.authorize(:repository_read, socket.assigns.current_user, repository) do
      templates = PromptRequests.list_prompt_templates(only_approved: true)

      form =
        %PromptRequest{conversation: nil}
        |> PromptRequests.change_prompt_request()
        |> to_form(as: :prompt_request)

      socket =
        socket
        |> assign(:page_title, "New Prompt Request")
        |> PageMeta.assign(
          description: "Submit a prompt request for #{repository.name}.",
          canonical_url:
            url(
              ~p"/projects/#{organization.account.handle}/#{repository.handle}/prompt-requests/new"
            )
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:form, form)
        |> assign(:prompt_templates, templates)
        |> assign(:template_options, template_options(templates))
        |> assign(:selected_template, nil)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found or access denied.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("validate", %{"prompt_request" => params}, socket) do
    changeset =
      %PromptRequest{}
      |> PromptRequests.change_prompt_request(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :prompt_request))
     |> assign(:selected_template, template_from_params(params))}
  end

  @impl true
  def handle_event("save", %{"prompt_request" => params}, socket) do
    case PromptRequests.submit_prompt_request(params,
           project: socket.assigns.repository,
           user: socket.assigns.current_user
         ) do
      {:ok, prompt_request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt request submitted.")
         |> push_navigate(
           to:
             ~p"/projects/#{socket.assigns.organization.account.handle}/#{socket.assigns.repository.handle}/prompt-requests/#{prompt_request.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}

      {:error, {:validation_failed, feedback, prompt_request}} ->
        feedback_message = PromptRequests.validation_feedback_summary(feedback)

        {:noreply,
         socket
         |> put_flash(:error, feedback_message)
         |> push_navigate(
           to:
             ~p"/projects/#{socket.assigns.organization.account.handle}/#{socket.assigns.repository.handle}/prompt-requests/#{prompt_request.id}"
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to submit prompt request.")}
    end
  end

  @impl true
  def handle_event("load_template", %{"template_id" => template_id}, socket) do
    template =
      case template_id do
        nil -> nil
        "" -> nil
        id -> PromptRequests.get_prompt_template(id)
      end

    if template do
      params =
        (socket.assigns.form.params || %{})
        |> Map.merge(%{
          "prompt_template_id" => template.id,
          "system_prompt" => template.system_prompt,
          "prompt" => template.prompt
        })

      changeset =
        %PromptRequest{}
        |> PromptRequests.change_prompt_request(params)

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, as: :prompt_request))
       |> assign(:selected_template, template)}
    else
      {:noreply, put_flash(socket, :error, "Select a template to load.")}
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
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:sessions}
      >
        <div class="prompt-request-form-container">
          <.header>
            New prompt request
            <:subtitle>
              <p>Share the prompt, generated result, and full agent context.</p>
            </:subtitle>
          </.header>

          <.form
            for={@form}
            id="prompt-request-form"
            phx-change="validate"
            phx-submit="save"
            class="prompt-request-form"
          >
            <div class="prompt-request-form-group">
              <.input
                field={@form[:title]}
                type="text"
                label="Title"
                placeholder="Summarize the request"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:prompt_template_id]}
                type="select"
                label="Prompt template"
                options={@template_options}
                prompt="Select a template (optional)"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
              <div class="prompt-request-template-actions">
                <button
                  type="button"
                  class="prompt-request-button prompt-request-button-secondary"
                  id="prompt-request-load-template"
                  phx-click="load_template"
                  phx-value-template-id={@form[:prompt_template_id].value}
                >
                  Load template
                </button>
                <%= if @selected_template do %>
                  <span class="prompt-request-template-meta">
                    {template_meta(@selected_template)}
                  </span>
                <% end %>
              </div>
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:model]}
                type="text"
                label="Model"
                placeholder="e.g., gpt-4.1"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:origin]}
                type="select"
                label="Contribution origin"
                options={origin_options()}
                prompt="Select origin"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:model_version]}
                type="text"
                label="Model version"
                placeholder="e.g., 2025-02-01"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:token_count]}
                type="number"
                label="Token count"
                placeholder="Tokens consumed during generation"
                min="0"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:generated_at]}
                type="datetime-local"
                label="Generation timestamp (UTC)"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:execution_duration_ms]}
                type="number"
                label="Execution duration (ms)"
                placeholder="e.g., 15420"
                min="0"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:execution_environment]}
                type="textarea"
                label="Execution environment (JSON)"
                placeholder={~s({"runtime":"phoenix","os":"linux"})}
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:parent_prompt_request_id]}
                type="text"
                label="Parent prompt request ID (optional)"
                placeholder="Link to the prompt this builds on"
                class="prompt-request-input"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:system_prompt]}
                type="textarea"
                label="System prompt"
                placeholder="System prompt used for the agent"
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:prompt]}
                type="textarea"
                label="User prompt"
                placeholder="Prompt submitted to the agent"
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:result]}
                type="textarea"
                label="Generated result"
                placeholder="Paste the generated result or diff"
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-group">
              <.input
                field={@form[:conversation]}
                type="textarea"
                label="Conversation history (JSON)"
                placeholder={~s({"messages": [{"role": "user", "content": "..."}]})}
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>

            <div class="prompt-request-form-actions">
              <button type="submit" class="prompt-request-button" id="prompt-request-submit">
                Submit prompt request
              </button>
              <.link
                navigate={
                  ~p"/projects/#{@organization.account.handle}/#{@repository.handle}/prompt-requests"
                }
                class="prompt-request-button prompt-request-button-secondary"
                id="prompt-request-cancel"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp origin_options do
    [
      {"AI-generated", "ai_generated"},
      {"AI-assisted", "ai_assisted"},
      {"Human", "human"}
    ]
  end

  defp template_options(templates) do
    Enum.map(templates, fn template -> {template.name, template.id} end)
  end

  defp template_from_params(%{"prompt_template_id" => ""}), do: nil
  defp template_from_params(%{"prompt_template_id" => nil}), do: nil

  defp template_from_params(%{"prompt_template_id" => template_id}) do
    PromptRequests.get_prompt_template(template_id)
  end

  defp template_from_params(_params), do: nil

  defp template_meta(template) do
    description =
      case template.description do
        nil -> ""
        "" -> ""
        value -> " · #{value}"
      end

    "#{template.name}#{description}"
  end
end
