defmodule MicelioWeb.PromptRequestLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @file_icon ~s(<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:inline;vertical-align:middle"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>)

  @impl true
  def mount(
        %{"account" => org_handle, "repository" => repository_handle, "number" => number_str},
        _session,
        socket
      ) do
    current_user = socket.assigns[:current_user]

    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             current_user,
             org_handle,
             repository_handle
           ),
         {number, ""} <- Integer.parse(number_str),
         %{} = prompt_request <-
           PromptRequests.get_prompt_request_by_number(repository, number) do
      can_edit =
        current_user != nil and
          Authorization.authorize(:repository_read, current_user, repository) == :ok and
          prompt_request.user_id == current_user.id

      socket =
        socket
        |> assign(:page_title, prompt_request.title)
        |> PageMeta.assign(
          description: prompt_request.title,
          canonical_url:
            url(
              ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{prompt_request.number}"
            )
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:prompt_request, prompt_request)
        |> assign(:can_edit, can_edit)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Prompt request not found."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    prompt_request = socket.assigns.prompt_request

    case PromptRequests.close_prompt_request(prompt_request) do
      {:ok, updated} ->
        {:noreply, assign(socket, :prompt_request, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to close prompt request."))}
    end
  end

  @impl true
  def handle_event("reopen", _params, socket) do
    prompt_request = socket.assigns.prompt_request

    case PromptRequests.reopen_prompt_request(prompt_request) do
      {:ok, updated} ->
        {:noreply, assign(socket, :prompt_request, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to reopen prompt request."))}
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
        <div class="prompt-request-show">
          <div class="prompt-request-show-header">
            <div class="prompt-request-show-title-row">
              <h1 class="prompt-request-show-title">
                {@prompt_request.title}
                <span class="prompt-request-show-number">#{@prompt_request.number}</span>
              </h1>
              <span class={"pr-status-badge pr-status-badge-#{@prompt_request.status}"}>
                {String.capitalize(@prompt_request.status)}
              </span>
            </div>
            <div class="prompt-request-show-header-actions">
              <div class="prompt-request-show-meta">
                {gettext("Opened %{time_ago} by %{author}",
                  time_ago: format_time_ago(@prompt_request.inserted_at),
                  author: @prompt_request.user.email
                )}
              </div>
              <%= if @can_edit do %>
                <div class="prompt-request-show-actions">
                  <.link
                    navigate={
                      ~p"/#{@organization.account.handle}/#{@repository.handle}/prs/#{@prompt_request.number}/edit"
                    }
                    class="repository-button repository-button-secondary"
                    id="edit-prompt-request"
                  >
                    {gettext("Edit")}
                  </.link>
                  <%= if @prompt_request.status == "open" do %>
                    <button
                      phx-click="close"
                      class="repository-button repository-button-secondary"
                      id="close-prompt-request"
                    >
                      {gettext("Close")}
                    </button>
                  <% else %>
                    <button
                      phx-click="reopen"
                      class="repository-button repository-button-secondary"
                      id="reopen-prompt-request"
                    >
                      {gettext("Reopen")}
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%= if @prompt_request.description do %>
            <div class="prompt-request-show-body" id="prompt-request-description">
              {raw(format_description(@prompt_request.description))}
            </div>
          <% end %>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp format_description(nil), do: ""

  defp format_description(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/@(\S+)/, fn match ->
      path = String.trim_leading(match, "@")

      ~s(<span class="file-mention-inline">#{@file_icon} #{Phoenix.HTML.html_escape(path) |> Phoenix.HTML.safe_to_string()}</span>)
    end)
    |> String.replace("\n", "<br>")
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
