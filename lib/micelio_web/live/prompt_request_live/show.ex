defmodule MicelioWeb.PromptRequestLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.PromptRequests.PromptSuggestion
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{
          "organization_handle" => org_handle,
          "repository_handle" => repository_handle,
          "id" => id
        },
        _session,
        socket
      ) do
    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             repository_handle
           ),
         :ok <- Authorization.authorize(:repository_read, socket.assigns.current_user, repository),
         prompt_request when not is_nil(prompt_request) <-
           PromptRequests.get_prompt_request_for_repository(repository, id) do
      diff_rows = build_diff_rows(prompt_request.prompt, prompt_request.result)

      socket =
        socket
        |> assign(:page_title, prompt_request.title)
        |> PageMeta.assign(
          description: "Prompt request for #{repository.name}.",
          canonical_url:
            url(
              ~p"/projects/#{organization.account.handle}/#{repository.handle}/prompt-requests/#{prompt_request.id}"
            )
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:prompt_request, prompt_request)
        |> assign(:attestation_status, PromptRequests.attestation_status(prompt_request))
        |> assign(:diff_rows, diff_rows)
        |> assign_suggestions(prompt_request)
        |> assign_validation_runs(prompt_request)
        |> assign(:can_validate, can_validate?(socket.assigns.current_user, repository))

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Prompt request not found or access denied.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("run_validation", _params, socket) do
    if can_validate?(socket.assigns.current_user, socket.assigns.repository) do
      case PromptRequests.run_validation_async(socket.assigns.prompt_request, self()) do
        {:ok, _pid} ->
          {:noreply, put_flash(socket, :info, "Validation started.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Unable to start validation: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to run validation.")}
    end
  end

  def handle_event("validate_suggestion", %{"prompt_suggestion" => params}, socket) do
    changeset =
      %PromptSuggestion{}
      |> PromptRequests.change_prompt_suggestion(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, suggestion_form: to_form(changeset, as: :prompt_suggestion))}
  end

  def handle_event("save_suggestion", %{"prompt_suggestion" => params}, socket) do
    case PromptRequests.create_prompt_suggestion(
           socket.assigns.prompt_request,
           params,
           user: socket.assigns.current_user
         ) do
      {:ok, _suggestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Suggestion submitted.")
         |> assign_suggestions(socket.assigns.prompt_request)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, suggestion_form: to_form(Map.put(changeset, :action, :validate)))}
    end
  end

  @impl true
  def handle_info({:validation_started, _run}, socket) do
    {:noreply, assign_validation_runs(socket, socket.assigns.prompt_request)}
  end

  @impl true
  def handle_info({:validation_finished, _prompt_request_id, {:ok, _run}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Validation passed.")
     |> assign_validation_runs(socket.assigns.prompt_request)}
  end

  @impl true
  def handle_info({:validation_finished, _prompt_request_id, {:error, _run}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Validation failed.")
     |> assign_validation_runs(socket.assigns.prompt_request)}
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
        <div class="prompt-request-show">
          <header class="prompt-request-show-header">
            <div class="prompt-request-breadcrumb">
              <.link navigate={~p"/projects"}>Projects</.link>
              <span>/</span>
              <.link navigate={~p"/projects/#{@organization.account.handle}/#{@repository.handle}"}>
                {@repository.name}
              </.link>
              <span>/</span>
              <.link navigate={
                ~p"/projects/#{@organization.account.handle}/#{@repository.handle}/prompt-requests"
              }>
                Prompt Requests
              </.link>
              <span>/</span>
              <span>{@prompt_request.title}</span>
            </div>
            <div class="prompt-request-title">
              <h1>{@prompt_request.title}</h1>
              <div class="prompt-request-meta">
                <span class={"badge badge--caps prompt-request-origin prompt-request-origin-#{origin_value(@prompt_request.origin)}"}>
                  {origin_label(@prompt_request.origin)}
                </span>
                <span>Model: {format_model(@prompt_request.model)}</span>
                <span>Version: {format_model(@prompt_request.model_version)}</span>
                <span>Tokens: {format_token_count(@prompt_request.token_count)}</span>
                <span>Generated: {format_datetime(@prompt_request.generated_at)}</span>
                <span>Submitted: {format_datetime(@prompt_request.inserted_at)}</span>
                <span>Attestation: {attestation_label(@attestation_status)}</span>
                <span>Submitted by {@prompt_request.user.email}</span>
              </div>
            </div>
          </header>

          <section class="prompt-request-section prompt-request-transparency">
            <h2>Contribution Transparency</h2>
            <div class="prompt-request-transparency-grid">
              <div>
                <span class="prompt-request-label">Origin</span>
                <span>{origin_label(@prompt_request.origin)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Model</span>
                <span>{format_model(@prompt_request.model)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Model version</span>
                <span>{format_model(@prompt_request.model_version)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Token count</span>
                <span>{format_token_count(@prompt_request.token_count)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Generated at</span>
                <span>{format_datetime(@prompt_request.generated_at)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Submitted at</span>
                <span>{format_datetime(@prompt_request.inserted_at)}</span>
              </div>
              <div>
                <span class="prompt-request-label">Attestation</span>
                <span>{attestation_label(@attestation_status)}</span>
              </div>
            </div>
          </section>

          <section class="prompt-request-section">
            <h2>Prompt/Result Diff</h2>
            <div class="prompt-request-diff" id="prompt-request-diff">
              <div class="prompt-request-diff-header">
                <span>Prompt</span>
                <span>Result</span>
              </div>
              <div class="prompt-request-diff-body">
                <%= for row <- @diff_rows do %>
                  <div class={"prompt-request-diff-row prompt-request-diff-#{row.type}"}>
                    <pre class="prompt-request-diff-cell">{row.left || ""}</pre>
                    <pre class="prompt-request-diff-cell">{row.right || ""}</pre>
                  </div>
                <% end %>
              </div>
            </div>
          </section>

          <section class="prompt-request-section">
            <h2>System Prompt</h2>
            <pre class="prompt-request-block">{@prompt_request.system_prompt}</pre>
          </section>

          <section class="prompt-request-section">
            <h2>Conversation History</h2>
            <pre class="prompt-request-block">
    {Jason.encode!(@prompt_request.conversation, pretty: true)}
          </pre>
          </section>

          <section class="prompt-request-section">
            <h2>Generated Result</h2>
            <pre class="prompt-request-block">{@prompt_request.result}</pre>
          </section>

          <section class="prompt-request-section">
            <div class="prompt-request-section-header">
              <h2>Validation Runs</h2>
              <%= if @can_validate do %>
                <button
                  type="button"
                  class="prompt-request-button prompt-request-button-secondary"
                  phx-click="run_validation"
                  id="prompt-request-run-validation"
                >
                  Run validation
                </button>
              <% end %>
            </div>
            <div class="prompt-request-validation">
              <%= if Enum.empty?(@validation_runs) do %>
                <p class="prompt-request-empty">No validation runs yet.</p>
              <% else %>
                <%= for run <- @validation_runs do %>
                  <div class="prompt-request-validation-run">
                    <div class="prompt-request-validation-summary">
                      <span class={"prompt-request-validation-status prompt-request-validation-#{run.status}"}>
                        {status_label(run.status)}
                      </span>
                      <span>Provider: {run.provider || "n/a"}</span>
                      <span>
                        Duration: {format_duration_ms(metric_value(run.metrics, "duration_ms"))}
                      </span>
                      <span>Coverage delta: {format_coverage(run.coverage_delta)}</span>
                    </div>
                    <div class="prompt-request-validation-details">
                      <span>
                        Resources: {format_resource_usage(run.resource_usage)}
                      </span>
                      <span>
                        Checks: {format_check_count(run.check_results["checks"])}
                      </span>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </section>

          <section class="prompt-request-section">
            <h2>Prompt Improvement Suggestions</h2>
            <div class="prompt-request-suggestions">
              <%= if Enum.empty?(@suggestions) do %>
                <p class="prompt-request-empty">No suggestions yet.</p>
              <% else %>
                <%= for suggestion <- @suggestions do %>
                  <div class="prompt-request-suggestion">
                    <p>{suggestion.suggestion}</p>
                    <span>By {suggestion.user.email}</span>
                  </div>
                <% end %>
              <% end %>
            </div>

            <.form
              for={@suggestion_form}
              id="prompt-suggestion-form"
              phx-change="validate_suggestion"
              phx-submit="save_suggestion"
              class="prompt-request-suggestion-form"
            >
              <div class="prompt-request-form-group">
                <.input
                  field={@suggestion_form[:suggestion]}
                  type="textarea"
                  label="Add a suggestion"
                  placeholder="Offer a prompt improvement idea"
                  class="prompt-request-input prompt-request-textarea"
                  error_class="prompt-request-input prompt-request-input-error"
                />
              </div>
              <div class="prompt-request-form-actions">
                <button type="submit" class="prompt-request-button" id="prompt-suggestion-submit">
                  Submit suggestion
                </button>
              </div>
            </.form>
          </section>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp assign_suggestions(socket, prompt_request) do
    suggestions = PromptRequests.list_prompt_suggestions(prompt_request)

    form =
      %PromptSuggestion{}
      |> PromptRequests.change_prompt_suggestion()
      |> to_form(as: :prompt_suggestion)

    socket
    |> assign(:suggestions, suggestions)
    |> assign(:suggestion_form, form)
  end

  defp assign_validation_runs(socket, prompt_request) do
    socket
    |> assign(:validation_runs, PromptRequests.list_validation_runs(prompt_request))
  end

  defp can_validate?(user, repository) do
    Authorization.authorize(:repository_update, user, repository) == :ok
  end

  defp status_label(:passed), do: "Passed"
  defp status_label(:failed), do: "Failed"
  defp status_label(:running), do: "Running"
  defp status_label(:pending), do: "Pending"
  defp status_label(other), do: to_string(other)

  defp format_duration_ms(nil), do: "n/a"

  defp format_duration_ms(milliseconds) when is_integer(milliseconds) do
    seconds = milliseconds / 1000
    :io_lib.format("~.2fs", [seconds]) |> IO.iodata_to_binary()
  end

  defp format_model(nil), do: "n/a"
  defp format_model(""), do: "n/a"
  defp format_model(value), do: value

  defp format_token_count(nil), do: "n/a"
  defp format_token_count(value) when is_integer(value), do: Integer.to_string(value)

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

  defp origin_label(origin), do: PromptRequest.origin_label(origin)

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: "unknown"

  defp attestation_label(:verified), do: "Verified"
  defp attestation_label(:invalid), do: "Invalid"
  defp attestation_label(:missing), do: "Missing"

  defp format_coverage(nil), do: "n/a"

  defp format_coverage(delta) when is_number(delta) do
    percent = delta * 100
    :io_lib.format("~.2f%%", [percent]) |> IO.iodata_to_binary()
  end

  defp format_resource_usage(resource_usage) when map_size(resource_usage) == 0, do: "n/a"

  defp format_resource_usage(resource_usage) do
    cpu = Map.get(resource_usage, "cpu_seconds") || Map.get(resource_usage, :cpu_seconds)
    memory = Map.get(resource_usage, "memory_mb") || Map.get(resource_usage, :memory_mb)

    [
      format_resource_value("CPU", cpu, "s"),
      format_resource_value("Memory", memory, "MB")
    ]
    |> Enum.reject(&(&1 == nil))
    |> Enum.join(" · ")
    |> case do
      "" -> "n/a"
      value -> value
    end
  end

  defp format_resource_value(_label, nil, _unit), do: nil

  defp format_resource_value(label, value, unit) when is_number(value) do
    float_value = if is_integer(value), do: value / 1, else: value
    formatted = :io_lib.format("~.2f", [float_value]) |> IO.iodata_to_binary()
    "#{label}: #{formatted}#{unit}"
  end

  defp format_check_count(nil), do: "n/a"

  defp format_check_count(checks) when is_list(checks) do
    "#{length(checks)} total"
  end

  defp metric_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp build_diff_rows(left, right) do
    left_lines = split_lines(left)
    right_lines = split_lines(right)

    left_lines
    |> List.myers_difference(right_lines)
    |> Enum.flat_map(fn
      {:eq, lines} ->
        Enum.map(lines, &%{left: &1, right: &1, type: :eq})

      {:del, lines} ->
        Enum.map(lines, &%{left: &1, right: nil, type: :del})

      {:ins, lines} ->
        Enum.map(lines, &%{left: nil, right: &1, type: :ins})
    end)
  end

  defp split_lines(nil), do: [""]

  defp split_lines(text) do
    text
    |> String.split("\n", trim: false)
  end
end
