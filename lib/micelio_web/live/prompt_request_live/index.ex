defmodule MicelioWeb.PromptRequestLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.PromptRequests
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => org_handle, "repository" => repository_handle}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case Repositories.get_repository_for_user_by_handle(
           current_user,
           org_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        prompt_requests = PromptRequests.list_prompt_requests_for_repository(repository)

        socket =
          socket
          |> assign(:page_title, gettext("Prompt Requests"))
          |> PageMeta.assign(
            description: gettext("Prompt requests for %{name}.", name: repository.name),
            canonical_url: url(~p"/#{organization.account.handle}/#{repository.handle}/prs")
          )
          |> assign(:repository, repository)
          |> assign(:organization, organization)
          |> assign(:prompt_requests, prompt_requests)

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Repository not found or access denied."))
         |> push_navigate(to: ~p"/repositories")}
    end
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
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:prompt_requests}
      >
        <div class="prompt-requests-container">
          <div class="prompt-requests-toolbar">
            <div class="prompt-requests-toolbar-left">
              <span class="prompt-requests-count">
                <svg
                  class="prompt-requests-count-icon"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.5"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M8 9h8" />
                  <path d="M8 13h6" />
                  <path d="M9 18h-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-3l-3 3-3-3z" />
                </svg>
                {gettext("%{count} Open", count: length(@prompt_requests))}
              </span>
            </div>
            <%= if assigns[:current_user] do %>
              <.link
                navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/prs/new"}
                class="repository-button"
                id="new-prompt-request"
              >
                {gettext("New prompt request")}
              </.link>
            <% end %>
          </div>

          <%= if Enum.empty?(@prompt_requests) do %>
            <div class="prompt-requests-empty" id="prompt-requests-empty">
              <svg
                class="prompt-requests-empty-icon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M8 9h8" />
                <path d="M8 13h6" />
                <path d="M9 18h-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-3l-3 3-3-3z" />
              </svg>
              <h3>{gettext("There aren't any open prompt requests.")}</h3>
              <p>
                {gettext(
                  "Prompt requests let you tell collaborators about changes you'd like an agent to make."
                )}
              </p>
            </div>
          <% else %>
            <div class="prompt-requests-list" id="prompt-requests-list">
              <%= for pr <- @prompt_requests do %>
                <div class="prompt-request-row" id={"pr-#{pr.id}"}>
                  <div class="prompt-request-row-icon">
                    <svg
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      aria-hidden="true"
                    >
                      <path d="M8 9h8" />
                      <path d="M8 13h6" />
                      <path d="M9 18h-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-3l-3 3-3-3z" />
                    </svg>
                  </div>
                  <div class="prompt-request-row-content">
                    <div class="prompt-request-row-main">
                      <.link
                        navigate={
                          ~p"/#{@organization.account.handle}/#{@repository.handle}/prs/#{pr.number}"
                        }
                        class="prompt-request-row-title"
                      >
                        {pr.title}
                      </.link>
                    </div>
                    <div class="prompt-request-row-meta">
                      #{pr.number}
                      {gettext("opened %{time_ago} by",
                        time_ago: format_time_ago(pr.inserted_at)
                      )}
                      <span class="prompt-request-row-author">{pr.user.email}</span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </.repository_header>
    </Layouts.app>
    """
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
end
