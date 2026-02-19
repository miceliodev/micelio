defmodule MicelioWeb.PlanLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Plans
  alias MicelioWeb.PageMeta

  @impl true
  def mount(params, _session, socket) do
    case MicelioWeb.RepositoryResolver.resolve(params, socket.assigns) do
      {:ok, repository, organization} ->
        base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)
        plans = Plans.list_plans_for_repository(repository)

        socket =
          socket
          |> assign(:page_title, gettext("Plans"))
          |> assign(:base_path, base_path)
          |> PageMeta.assign(
            description: gettext("Plans for %{name}.", name: repository.name),
            canonical_url: unverified_url(MicelioWeb.Endpoint, "#{base_path}/prompt-requests")
          )
          |> assign(:repository, repository)
          |> assign(:organization, organization)
          |> assign(:plans, plans)

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
        <div class="plans-container">
          <div class="plans-toolbar">
            <div class="plans-toolbar-left">
              <span class="plans-count">
                <svg
                  class="plans-count-icon"
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
                {gettext("%{count} Open", count: length(@plans))}
              </span>
            </div>
            <%= if assigns[:current_user] do %>
              <.link
                navigate={"#{@base_path}/prompt-requests/new"}
                class="repository-button"
                id="new-plan"
              >
                {gettext("New plan")}
              </.link>
            <% end %>
          </div>

          <%= if Enum.empty?(@plans) do %>
            <div class="plans-empty" id="plans-empty">
              <svg
                class="plans-empty-icon"
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
              <h3>{gettext("There aren't any open plans.")}</h3>
              <p>
                {gettext(
                  "Plans let you tell collaborators about changes you'd like an agent to make."
                )}
              </p>
            </div>
          <% else %>
            <div class="plans-list" id="plans-list">
              <%= for pr <- @plans do %>
                <div class="plan-row" id={"pr-#{pr.id}"}>
                  <div class="plan-row-icon">
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
                  <div class="plan-row-content">
                    <div class="plan-row-main">
                      <.link
                        navigate={"#{@base_path}/prompt-requests/#{pr.number}"}
                        class="plan-row-title"
                      >
                        {pr.title}
                      </.link>
                    </div>
                    <div class="plan-row-meta">
                      #{pr.number}
                      {gettext("opened %{time_ago} by",
                        time_ago: format_time_ago(pr.inserted_at)
                      )}
                      <span class="plan-row-author">{pr.user.email}</span>
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
