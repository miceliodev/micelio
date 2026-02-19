defmodule MicelioWeb.PlanLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Plans
  alias Micelio.Plans.Plan
  alias MicelioWeb.PageMeta

  @impl true
  def mount(params, _session, socket) do
    with {:ok, repository, organization} <-
           MicelioWeb.RepositoryResolver.resolve(params, socket.assigns),
         :ok <- Authorization.authorize(:repository_read, socket.assigns.current_user, repository) do
      base_path = MicelioWeb.RepositoryURL.base_path(repository, organization)

      form =
        %Plan{}
        |> Plans.change_simple_plan()
        |> to_form(as: :plan)

      socket =
        socket
        |> assign(:page_title, gettext("New Plan"))
        |> assign(:base_path, base_path)
        |> PageMeta.assign(
          description: gettext("Create a plan for %{name}.", name: repository.name),
          canonical_url: unverified_url(MicelioWeb.Endpoint, "#{base_path}/prompt-requests/new")
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:form, form)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Repository not found or access denied."))
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    changeset =
      %Plan{}
      |> Plans.change_simple_plan(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :plan))}
  end

  @impl true
  def handle_event("save", %{"plan" => params}, socket) do
    repository = socket.assigns.repository
    user = socket.assigns.current_user

    case Plans.create_simple_plan(params, repository: repository, user: user) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Plan created."))
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

            <div class="pr-form-description-group">
              <textarea
                id="plan-description"
                name={@form[:description].name}
                placeholder={gettext("Leave a comment")}
                class="pr-form-description-textarea"
                phx-debounce="300"
                rows="12"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:description].value)}</textarea>
            </div>

            <div class="pr-form-actions">
              <button type="submit" class="repository-button" id="plan-submit">
                {gettext("Submit new plan")}
              </button>
              <.link
                navigate={"#{@base_path}/prompt-requests"}
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
end
