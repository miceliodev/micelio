defmodule MicelioWeb.OrganizationLive.Settings do
  use MicelioWeb, :live_view

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.LLM
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"organization_handle" => handle}, _session, socket) do
    case Accounts.get_organization_by_handle(handle) do
      {:ok, organization} ->
        if Authorization.authorize(
             :organization_update,
             socket.assigns.current_user,
             organization
           ) ==
             :ok do
          account = organization.account
          {form, llm_default_options} = build_form(account, %{})

          socket =
            socket
            |> assign(:page_title, gettext("Organization settings"))
            |> PageMeta.assign(
              description: gettext("Edit organization settings."),
              canonical_url: url(~p"/organizations/#{account.handle}/settings")
            )
            |> assign(:organization, organization)
            |> assign(:account, account)
            |> assign(:form, form)
            |> assign(:llm_default_options, llm_default_options)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You do not have access to this organization."))
           |> push_navigate(to: ~p"/#{organization.account.handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Organization not found."))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    params = strip_empty_api_key(params)

    {changeset, llm_default_options} =
      socket.assigns.account
      |> Accounts.change_account_settings(params)
      |> Map.put(:action, :validate)
      |> form_with_options(socket.assigns.account)

    {:noreply,
     assign(socket,
       form: to_form(changeset, as: :account),
       llm_default_options: llm_default_options
     )}
  end

  @impl true
  def handle_event("save", %{"account" => params}, socket) do
    params = strip_empty_api_key(params)

    if Authorization.authorize(
         :organization_update,
         socket.assigns.current_user,
         socket.assigns.organization
       ) ==
         :ok do
      case Accounts.update_account_settings(socket.assigns.account, params) do
        {:ok, account} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Organization updated successfully!"))
           |> push_navigate(to: ~p"/#{account.handle}")}

        {:error, changeset} ->
          {changeset, llm_default_options} =
            Map.put(changeset, :action, :validate)
            |> form_with_options(socket.assigns.account)

          {:noreply,
           assign(socket,
             form: to_form(changeset, as: :account),
             llm_default_options: llm_default_options
           )}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("You do not have access to this organization."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="repository-form-container">
        <.header>
          {gettext("Organization settings")}
          <:subtitle>
            <p>
              {@account.handle}
            </p>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="organization-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="repository-form"
        >
          <fieldset class="settings-section">
            <legend class="settings-section-title">{gettext("AI provider")}</legend>
            <p class="settings-section-description">
              {gettext("Configure the AI provider and credentials for agentic sessions.")}
            </p>

            <div class="repository-form-group">
              <.input
                field={@form[:llm_provider]}
                type="select"
                label={gettext("Provider")}
                options={provider_options()}
                prompt={gettext("Select a provider")}
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:llm_api_key_encrypted]}
                type="password"
                label={gettext("API key")}
                placeholder={
                  if @account.llm_api_key_encrypted, do: gettext("(saved)"), else: "sk-..."
                }
                class="repository-input"
                error_class="repository-input repository-input-error"
                autocomplete="off"
              />
              <p class="repository-form-hint">
                {gettext("Stored encrypted. Leave blank to keep the current key.")}
              </p>
            </div>
          </fieldset>

          <fieldset class="settings-section">
            <legend class="settings-section-title">{gettext("Models")}</legend>
            <p class="settings-section-description">
              {gettext("Control which models are available and which one is used by default.")}
            </p>

            <div class="repository-form-group">
              <.input
                field={@form[:llm_models]}
                type="select"
                label={gettext("Allowed models")}
                options={llm_model_options()}
                multiple
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:llm_default_model]}
                type="select"
                label={gettext("Default model")}
                options={@llm_default_options}
                prompt={gettext("Use platform default")}
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>
          </fieldset>

          <fieldset class="settings-section">
            <legend class="settings-section-title">{gettext("Forge")}</legend>
            <p class="settings-section-description">
              {gettext("Link this organization to an external forge like GitHub or GitLab.")}
            </p>

            <div class="repository-form-group">
              <.input
                field={@form[:forge_provider]}
                type="select"
                label={gettext("Forge provider")}
                options={forge_provider_options()}
                prompt={gettext("None")}
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
            </div>

            <div class="repository-form-group">
              <.input
                field={@form[:forge_host]}
                type="text"
                label={gettext("Forge host")}
                placeholder="github.com"
                class="repository-input"
                error_class="repository-input repository-input-error"
              />
              <p class="repository-form-hint">
                {gettext("The hostname of the forge (e.g., github.com or gitlab.com).")}
              </p>
            </div>
          </fieldset>

          <div class="repository-form-actions">
            <button type="submit" class="repository-button" id="organization-settings-submit">
              {gettext("Save changes")}
            </button>
            <.link
              navigate={~p"/#{@account.handle}"}
              class="repository-button repository-button-secondary"
              id="organization-settings-cancel"
            >
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp strip_empty_api_key(params) do
    case Map.get(params, "llm_api_key_encrypted") do
      nil -> params
      "" -> Map.delete(params, "llm_api_key_encrypted")
      _ -> params
    end
  end

  defp build_form(account, attrs) do
    changeset = Accounts.change_account_settings(account, attrs)
    {changeset, llm_default_options} = form_with_options(changeset, account)
    {to_form(changeset, as: :account), llm_default_options}
  end

  defp form_with_options(changeset, account) do
    {changeset, llm_default_options(changeset, account)}
  end

  defp provider_options do
    [
      {"OpenAI", "openai"},
      {"Anthropic", "anthropic"},
      {"Google", "google"}
    ]
  end

  defp forge_provider_options do
    [
      {"GitHub", "github"},
      {"GitLab", "gitlab"}
    ]
  end

  defp llm_model_options do
    LLM.repository_model_options()
  end

  defp llm_default_options(changeset, account) do
    available = LLM.repository_models()

    selected_models =
      case Ecto.Changeset.get_field(changeset, :llm_models) do
        models when is_list(models) and models != [] -> Enum.filter(models, &(&1 in available))
        _ -> LLM.repository_models_for_account(account)
      end

    models = if selected_models == [], do: available, else: selected_models
    Enum.map(models, &{&1, &1})
  end
end
