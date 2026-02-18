defmodule MicelioWeb.AdminPromptRegistryLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.ContributionConfidence
  alias Micelio.Plans
  alias Micelio.Plans.Plan
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Prompt Registry")
      |> PageMeta.assign(
        description: "Admin prompt registry with provenance details.",
        canonical_url: url(~p"/admin/prompts")
      )
      |> assign(:filters, default_filters())
      |> assign(:plans, [])
      |> assign(:confidence_scores, %{})
      |> assign(:review_statuses, [:pending, :accepted, :rejected])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = build_filters(params)

    plans =
      Plans.list_plan_registry(
        search: filters["search"],
        review_status: parse_review_status(filters["review_status"]),
        curated_only: filters["curated_only"] in ["true", "on", "1"]
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:plans, plans)
     |> assign(:confidence_scores, Plans.confidence_scores(plans))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      %{"filters" => filters}
      |> prune_params()

    {:noreply, push_patch(socket, to: ~p"/admin/prompts?#{params}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <div class="admin-prompts" id="admin-prompt-registry">
        <.header>
          Prompt registry
          <:subtitle>Search prompts, review outcomes, and curated favorites.</:subtitle>
        </.header>

        <section class="admin-prompts-section" id="admin-prompt-registry-controls">
          <form class="admin-prompts-filters" phx-change="filter">
            <input
              type="search"
              name="filters[search]"
              placeholder="Search prompts"
              value={@filters["search"]}
            />
            <select name="filters[review_status]" aria-label="Filter by review status">
              <option value="" selected={@filters["review_status"] in ["", nil]}>All reviews</option>
              <%= for status <- @review_statuses do %>
                <option value={status} selected={@filters["review_status"] == Atom.to_string(status)}>
                  {review_label(status)}
                </option>
              <% end %>
            </select>
            <label class="admin-prompts-toggle">
              <input
                type="checkbox"
                name="filters[curated_only]"
                value="true"
                checked={@filters["curated_only"] in ["true", "on", "1"]}
              /> Curated only
            </label>
          </form>
        </section>

        <section class="admin-prompts-section" id="admin-prompt-registry-list">
          <%= if Enum.empty?(@plans) do %>
            <p class="admin-empty">No plans match the current filters.</p>
          <% else %>
            <div class="admin-prompts-list">
              <%= for plan <- @plans do %>
                <article class="admin-prompts-card" id={"admin-prompt-#{plan.id}"}>
                  <div class="admin-prompts-card-main">
                    <div class="admin-prompts-card-header">
                      <h3 class="admin-prompts-card-title">{plan.title}</h3>
                      <span class={"admin-prompts-status admin-prompts-status-#{review_value(plan.review_status)}"}>
                        {review_label(plan.review_status)}
                      </span>
                    </div>
                    <div class="admin-prompts-card-meta">
                      <span>
                        {plan.repository.organization.account.handle}/{plan.repository.handle}
                      </span>
                      <span>·</span>
                      <span>{plan.user.email}</span>
                      <span>·</span>
                      <span>{origin_label(plan.origin)}</span>
                      <span>·</span>
                      <span>Tokens: {plan.token_count || 0}</span>
                      <span>·</span>
                      <span>
                        Confidence: {format_confidence(Map.get(@confidence_scores, plan.id))}
                      </span>
                    </div>
                    <div class="admin-prompts-card-meta">
                      <span>Model: {plan.model || "n/a"}</span>
                      <%= if plan.prompt_template do %>
                        <span>·</span>
                        <span>Template: {plan.prompt_template.name}</span>
                      <% end %>
                      <%= if plan.curated_at do %>
                        <span>·</span>
                        <span>Curated</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="admin-prompts-card-actions">
                    <.link
                      navigate={
                        ~p"/#{plan.repository.organization.account.handle}/#{plan.repository.handle}/prs/#{plan.id}"
                      }
                      class="button button--secondary"
                    >
                      View
                    </.link>
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
    %{"search" => "", "review_status" => "", "curated_only" => ""}
  end

  defp build_filters(params) do
    filters = Map.get(params, "filters", %{})

    %{
      "search" => Map.get(filters, "search", ""),
      "review_status" => Map.get(filters, "review_status", ""),
      "curated_only" => Map.get(filters, "curated_only", "")
    }
  end

  defp parse_review_status("pending"), do: :pending
  defp parse_review_status("accepted"), do: :accepted
  defp parse_review_status("rejected"), do: :rejected
  defp parse_review_status(_), do: nil

  defp review_label(:pending), do: "Pending"
  defp review_label(:accepted), do: "Accepted"
  defp review_label(:rejected), do: "Rejected"
  defp review_label(_), do: "Unknown"

  defp review_value(:pending), do: "pending"
  defp review_value(:accepted), do: "accepted"
  defp review_value(:rejected), do: "rejected"
  defp review_value(_), do: "unknown"

  defp origin_label(origin), do: Plan.origin_label(origin)

  defp format_confidence(%ContributionConfidence.Score{overall: overall, label: label}) do
    "#{overall} (#{label})"
  end

  defp format_confidence(_score), do: "n/a"

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
