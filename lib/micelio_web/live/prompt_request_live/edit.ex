defmodule MicelioWeb.PromptRequestLive.Edit do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Mic.Project, as: MicProject
  alias Micelio.PromptRequests
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{"account" => org_handle, "repository" => repository_handle, "number" => number_str},
        _session,
        socket
      ) do
    current_user = socket.assigns.current_user

    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             current_user,
             org_handle,
             repository_handle
           ),
         :ok <- Authorization.authorize(:repository_read, current_user, repository),
         {number, ""} <- Integer.parse(number_str),
         %{} = prompt_request <-
           PromptRequests.get_prompt_request_by_number(repository, number),
         true <- prompt_request.user_id == current_user.id do
      form =
        prompt_request
        |> PromptRequests.change_simple_prompt_request()
        |> to_form(as: :prompt_request)

      file_paths = load_file_paths(repository)

      socket =
        socket
        |> assign(:page_title, gettext("Edit Prompt Request"))
        |> PageMeta.assign(
          description: gettext("Edit prompt request #%{number}.", number: prompt_request.number),
          canonical_url:
            url(
              ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{prompt_request.number}/edit"
            )
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:prompt_request, prompt_request)
        |> assign(:form, form)
        |> assign(:file_paths_json, Jason.encode!(file_paths))

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Prompt request not found or access denied."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("validate", %{"prompt_request" => params}, socket) do
    changeset =
      socket.assigns.prompt_request
      |> PromptRequests.change_simple_prompt_request(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :prompt_request))}
  end

  @impl true
  def handle_event("save", %{"prompt_request" => params}, socket) do
    case PromptRequests.update_prompt_request(socket.assigns.prompt_request, params) do
      {:ok, prompt_request} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Prompt request updated."))
         |> push_navigate(
           to:
             ~p"/#{socket.assigns.organization.account.handle}/#{socket.assigns.repository.handle}/prs/#{prompt_request.number}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(Map.put(changeset, :action, :validate), as: :prompt_request)
         )}
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
        <div class="pr-form-container">
          <.form
            for={@form}
            id="prompt-request-form"
            phx-change="validate"
            phx-submit="save"
            class="pr-form"
          >
            <div class="pr-form-title-group">
              <input
                type="text"
                id="prompt-request-title"
                name={@form[:title].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
                placeholder={gettext("Title")}
                class="pr-form-title-input"
                phx-debounce="300"
              />
              <%= if Phoenix.Component.used_input?(@form[:title]) do %>
                <%= for err <- @form[:title].errors do %>
                  <p class="form-error">{translate_error(err)}</p>
                <% end %>
              <% end %>
            </div>

            <div
              id="description-mention-wrapper"
              phx-hook="FileMention"
              phx-update="ignore"
              data-file-paths={@file_paths_json}
              class="pr-form-description-group"
            >
              <textarea
                id="prompt-request-description"
                name={@form[:description].name}
                placeholder={gettext("Describe the change you want. Use @ to reference files.")}
                class="pr-form-description-textarea"
                phx-debounce="300"
                rows="12"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:description].value)}</textarea>
            </div>

            <div class="pr-form-actions">
              <button type="submit" class="repository-button" id="prompt-request-submit">
                {gettext("Update prompt request")}
              </button>
              <.link
                navigate={
                  ~p"/#{@organization.account.handle}/#{@repository.handle}/prs/#{@prompt_request.number}"
                }
                class="repository-button repository-button-secondary"
                id="prompt-request-cancel"
              >
                {gettext("Cancel")}
              </.link>
            </div>
          </.form>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp load_file_paths(repository) do
    case MicProject.get_head(repository.id) do
      {:ok, %{tree_hash: tree_hash}} when not is_nil(tree_hash) ->
        case MicProject.get_tree(repository.id, tree_hash) do
          {:ok, tree} -> tree |> Map.keys() |> Enum.sort()
          _ -> []
        end

      _ ->
        []
    end
  end
end
