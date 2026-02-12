defmodule MicelioWeb.DocsLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Docs
  alias MicelioWeb.DocsI18n
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:query, "")
      |> assign(:results, [])
      |> assign(:categories, DocsI18n.translate_categories(Docs.categories()))
      |> assign(:guide_categories, DocsI18n.translate_categories(Docs.categories_by_kind(:guide)))
      |> assign(
        :reference_categories,
        DocsI18n.translate_categories(Docs.categories_by_kind(:reference))
      )
      |> assign(:searching, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket =
      PageMeta.assign(socket,
        title_parts: [gettext("docs")],
        description: gettext("Documentation for Micelio users and hosters."),
        canonical_url: url(~p"/docs")
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    {results, searching} =
      if String.length(query) >= 2 do
        {Docs.search(query), true}
      else
        {[], false}
      end

    {:noreply, assign(socket, query: query, results: results, searching: searching)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, query: "", results: [], searching: false)}
  end

  defp category_title(category_id, categories) do
    case Map.get(categories, category_id) do
      %{title: title} -> title
      _ -> category_id
    end
  end

  # Tabler icons for reference categories
  defp reference_icon("rest-api") do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M14 3v4a1 1 0 0 0 1 1h4" /><path d="M17 21H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7l5 5v11a2 2 0 0 1-2 2z" /><path d="M10 13l-1 2l1 2" /><path d="M14 13l1 2l-1 2" />
    </svg>
    """
  end

  defp reference_icon("auth") do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <rect width="18" height="11" x="3" y="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
    """
  end

  defp reference_icon("grpc") do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="m16 3 4 4-4 4" /><path d="M20 7H4" /><path d="m8 21-4-4 4-4" /><path d="M4 17h16" />
    </svg>
    """
  end

  defp reference_icon(_) do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 20h9" /><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
    """
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
    >
      <div class="docs-container">
        <.header>
          {gettext("Documentation")}
          <:subtitle>
            {gettext("Learn how to use mic and Micelio, or how to host your own instance.")}
          </:subtitle>
        </.header>

        <form phx-change="search" phx-submit="search" class="docs-search-form">
          <div class="docs-search-input-wrapper">
            <input
              type="search"
              name="q"
              value={@query}
              placeholder={gettext("Search docs...")}
              class="docs-search-input"
              phx-debounce="150"
              autocomplete="off"
            />
            <%= if @query != "" do %>
              <button
                type="button"
                phx-click="clear"
                class="docs-search-clear"
                aria-label={gettext("Clear search")}
              >
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
                  <path d="M18 6 6 18" /><path d="m6 6 12 12" />
                </svg>
              </button>
            <% else %>
              <span class="docs-search-icon">
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
                  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.3-4.3" />
                </svg>
              </span>
            <% end %>
          </div>
        </form>

        <%= if @searching do %>
          <div class="docs-search-status">
            {ngettext(
              "%{count} result",
              "%{count} results",
              length(@results),
              count: length(@results)
            )}
          </div>

          <%= if length(@results) > 0 do %>
            <div class="docs-search-results">
              <%= for {page, _score} <- @results do %>
                <.link navigate={~p"/docs/#{page.category}/#{page.id}"} class="docs-search-result">
                  <div class="docs-search-result-category">
                    {category_title(page.category, @categories)}
                  </div>
                  <h3 class="docs-search-result-title">{page.title}</h3>
                  <p class="docs-search-result-description">{page.description}</p>
                </.link>
              <% end %>
            </div>
          <% else %>
            <div class="docs-search-empty">
              <p>{gettext("No results found. Try a different search term.")}</p>
            </div>
          <% end %>
        <% else %>
          <%!-- Guides Section --%>
          <section class="docs-section">
            <h2 class="docs-section-title">{gettext("Guides")}</h2>
            <div class="docs-categories">
              <%= for {category_id, category_info} <- @guide_categories do %>
                <.link navigate={~p"/docs/#{category_id}"} class="docs-category-card">
                  <div class="docs-category-icon">
                    <%= if category_id == "users" do %>
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        width="20"
                        height="20"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      >
                        <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                        <circle cx="9" cy="7" r="4" />
                        <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
                        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                      </svg>
                    <% else %>
                      <%= if category_id == "hosters" do %>
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          width="20"
                          height="20"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <rect width="20" height="8" x="2" y="14" rx="2" />
                          <rect width="20" height="8" x="2" y="2" rx="2" />
                          <line x1="6" x2="6" y1="6" y2="6" />
                          <line x1="6" x2="6" y1="18" y2="18" />
                        </svg>
                      <% else %>
                        <%= if category_id == "contributors" do %>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="20"
                            height="20"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="2"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          >
                            <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                            <circle cx="9" cy="7" r="4" />
                            <line x1="19" x2="19" y1="8" y2="14" />
                            <line x1="22" x2="16" y1="11" y2="11" />
                          </svg>
                        <% else %>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="20"
                            height="20"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="2"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          >
                            <path d="M12 20h9" />
                            <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
                          </svg>
                        <% end %>
                      <% end %>
                    <% end %>
                  </div>
                  <h3 class="docs-category-title">{category_info.title}</h3>
                  <p class="docs-category-description">{category_info.description}</p>
                </.link>
              <% end %>
            </div>
          </section>

          <%!-- References Section --%>
          <section class="docs-section">
            <h2 class="docs-section-title">{gettext("References")}</h2>
            <div class="docs-categories">
              <.link navigate={~p"/docs/cli-reference"} class="docs-category-card">
                <div class="docs-category-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="4 17 10 11 4 5" />
                    <line x1="12" x2="20" y1="19" y2="19" />
                  </svg>
                </div>
                <h3 class="docs-category-title">{gettext("CLI Reference")}</h3>
                <p class="docs-category-description">
                  {gettext("Complete reference for the mic command-line interface.")}
                </p>
              </.link>
              <%= for {category_id, category_info} <- @reference_categories do %>
                <.link navigate={~p"/docs/#{category_id}"} class="docs-category-card">
                  <div class="docs-category-icon">
                    {reference_icon(category_id)}
                  </div>
                  <h3 class="docs-category-title">{category_info.title}</h3>
                  <p class="docs-category-description">{category_info.description}</p>
                </.link>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
