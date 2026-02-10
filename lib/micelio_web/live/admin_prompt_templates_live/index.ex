defmodule MicelioWeb.AdminPromptTemplatesLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptTemplate
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    form =
      %PromptTemplate{}
      |> PromptRequests.change_prompt_template()
      |> to_form(as: :prompt_template)

    socket =
      socket
      |> assign(:page_title, "Prompt Templates")
      |> PageMeta.assign(
        description: "Admin prompt templates for common tasks.",
        canonical_url: url(~p"/admin/prompt-templates")
      )
      |> assign(:filters, default_filters())
      |> assign(:prompt_templates, [])
      |> assign(:form, form)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = build_filters(params)

    prompt_templates =
      PromptRequests.list_prompt_templates(
        only_approved: filters["approved_only"] in ["true", "on", "1"]
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:prompt_templates, prompt_templates)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      %{"filters" => filters}
      |> prune_params()

    {:noreply, push_patch(socket, to: ~p"/admin/prompt-templates?#{params}")}
  end

  @impl true
  def handle_event("validate", %{"prompt_template" => params}, socket) do
    changeset =
      %PromptTemplate{}
      |> PromptRequests.change_prompt_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :prompt_template))}
  end

  @impl true
  def handle_event("save", %{"prompt_template" => params}, socket) do
    case PromptRequests.create_prompt_template(params, created_by: socket.assigns.current_user) do
      {:ok, _template} ->
        form =
          %PromptTemplate{}
          |> PromptRequests.change_prompt_template()
          |> to_form(as: :prompt_template)

        {:noreply,
         socket
         |> put_flash(:info, "Prompt template created.")
         |> assign(:form, form)
         |> refresh_templates()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
    end
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    case PromptRequests.get_prompt_template(id) do
      %PromptTemplate{} = template ->
        case PromptRequests.approve_prompt_template(template, socket.assigns.current_user) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prompt template approved.")
             |> refresh_templates()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Unable to approve template.")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Template not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <div class="admin-prompts" id="admin-prompt-templates">
        <.header>
          Prompt templates
          <:subtitle>Curated starting points for common prompt requests.</:subtitle>
        </.header>

        <section class="admin-prompts-section" id="admin-prompt-templates-form">
          <h2 class="admin-section-title">Create template</h2>
          <.form
            for={@form}
            id="prompt-template-form"
            phx-change="validate"
            phx-submit="save"
            class="admin-prompts-form"
          >
            <div class="admin-prompts-form-grid">
              <.input
                field={@form[:name]}
                type="text"
                label="Name"
                placeholder="Bug fix prompt"
              />
              <.input
                field={@form[:category]}
                type="text"
                label="Category"
                placeholder="Bug fixes"
              />
              <.input
                field={@form[:description]}
                type="text"
                label="Description"
                placeholder="Short summary of when to use this template"
              />
            </div>
            <div class="admin-prompts-form-stack">
              <.input
                field={@form[:system_prompt]}
                type="textarea"
                label="System prompt"
                placeholder="System instructions for the agent"
              />
              <.input
                field={@form[:prompt]}
                type="textarea"
                label="User prompt"
                placeholder="Base prompt for the agent"
              />
            </div>
            <button type="submit" class="button">Create template</button>
          </.form>
        </section>

        <section class="admin-prompts-section" id="admin-prompt-templates-list">
          <div class="admin-prompts-toolbar">
            <form class="admin-prompts-filters" phx-change="filter">
              <label class="admin-prompts-toggle">
                <input
                  type="checkbox"
                  name="filters[approved_only]"
                  value="true"
                  checked={@filters["approved_only"] in ["true", "on", "1"]}
                /> Approved only
              </label>
            </form>
          </div>

          <%= if Enum.empty?(@prompt_templates) do %>
            <p class="admin-empty">No prompt templates yet.</p>
          <% else %>
            <div class="admin-prompts-list">
              <%= for template <- @prompt_templates do %>
                <article class="admin-prompts-card" id={"admin-template-#{template.id}"}>
                  <div class="admin-prompts-card-main">
                    <div class="admin-prompts-card-header">
                      <h3 class="admin-prompts-card-title">{template.name}</h3>
                      <span class={"admin-prompts-status admin-prompts-status-#{template_status(template)}"}>
                        {template_label(template)}
                      </span>
                    </div>
                    <div class="admin-prompts-card-meta">
                      <span>{template.category || "Uncategorized"}</span>
                      <%= if template.description do %>
                        <span>·</span>
                        <span>{template.description}</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="admin-prompts-card-actions">
                    <%= if is_nil(template.approved_at) do %>
                      <button
                        type="button"
                        class="button button--secondary"
                        phx-click="approve"
                        phx-value-id={template.id}
                      >
                        Approve
                      </button>
                    <% end %>
                  </div>
                </article>
              <% end %>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp default_filters do
    %{"approved_only" => ""}
  end

  defp build_filters(params) do
    filters = Map.get(params, "filters", %{})
    %{"approved_only" => Map.get(filters, "approved_only", "")}
  end

  defp refresh_templates(socket) do
    prompt_templates =
      PromptRequests.list_prompt_templates(
        only_approved: socket.assigns.filters["approved_only"] in ["true", "on", "1"]
      )

    assign(socket, :prompt_templates, prompt_templates)
  end

  defp template_label(%PromptTemplate{approved_at: nil}), do: "Pending"
  defp template_label(%PromptTemplate{}), do: "Approved"

  defp template_status(%PromptTemplate{approved_at: nil}), do: "pending"
  defp template_status(%PromptTemplate{}), do: "approved"

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
end
