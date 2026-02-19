defmodule MicelioWeb.PlanLive.Edit do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Mic.Project, as: MicProject
  alias Micelio.Plans
  alias MicelioWeb.PageMeta

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user
    number_str = params["number"]

    with {:ok, repository, organization} <-
           MicelioWeb.RepositoryResolver.resolve(params, socket.assigns),
         :ok <- Authorization.authorize(:repository_read, current_user, repository),
         {number, ""} <- Integer.parse(number_str),
         %{} = plan <-
           Plans.get_plan_by_number(repository, number),
         true <- plan.user_id == current_user.id do
      base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)

      form =
        plan
        |> Plans.change_simple_plan()
        |> to_form(as: :plan)

      file_paths = load_file_paths(repository)

      socket =
        socket
        |> assign(:page_title, gettext("Edit Plan"))
        |> assign(:base_path, base_path)
        |> PageMeta.assign(
          description: gettext("Edit plan #%{number}.", number: plan.number),
          canonical_url:
            unverified_url(MicelioWeb.Endpoint, "#{base_path}/prompt-requests/#{plan.number}/edit")
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:plan, plan)
        |> assign(:form, form)
        |> assign(:file_paths_json, Jason.encode!(file_paths))

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Plan not found or access denied."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    changeset =
      socket.assigns.plan
      |> Plans.change_simple_plan(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :plan))}
  end

  @impl true
  def handle_event("save", %{"plan" => params}, socket) do
    case Plans.update_plan(socket.assigns.plan, params) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Plan updated."))
         |> push_navigate(to: "#{socket.assigns.base_path}/prompt-requests/#{plan.number}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(Map.put(changeset, :action, :validate), as: :plan)
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
      repository_nav={
        %{
          account_handle: @organization.account.handle,
          repository_handle: @repository.handle,
          active: :prompt_requests,
          show_settings?: true,
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
        <div class="pr-form-container">
          <.form
            for={@form}
            id="plan-form"
            phx-change="validate"
            phx-submit="save"
            class="pr-form"
          >
            <div class="pr-form-title-group">
              <input
                type="text"
                id="plan-title"
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
                id="plan-description"
                name={@form[:description].name}
                placeholder={gettext("Describe the change you want. Use @ to reference files.")}
                class="pr-form-description-textarea"
                phx-debounce="300"
                rows="12"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:description].value)}</textarea>
            </div>

            <div class="pr-form-actions">
              <button type="submit" class="repository-button" id="plan-submit">
                {gettext("Update plan")}
              </button>
              <.link
                navigate={"#{@base_path}/prompt-requests/#{@plan.number}"}
                class="repository-button repository-button-secondary"
                id="plan-cancel"
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
