defmodule MicelioWeb.RepositoryLive.Webhooks do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Webhooks
  alias Micelio.Webhooks.Webhook
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => account_handle, "repository" => repository_handle}, _session, socket) do
    case Micelio.Repositories.get_repository_for_user_by_handle(
           socket.assigns.current_user,
           account_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:repository_update, socket.assigns.current_user, repository) ==
             :ok do
          socket =
            socket
            |> assign(:page_title, "Repository webhooks")
            |> PageMeta.assign(
              description: "Manage repository webhooks.",
              canonical_url:
                url(~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:webhooks, Webhooks.list_webhooks_for_repository(repository.id))
            |> assign(:form, webhook_form(repository))

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Repository not found.")
         |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
    end
  end

  @impl true
  def handle_event("validate", %{"webhook" => params}, socket) do
    changeset =
      %Webhook{}
      |> Webhooks.change_webhook(params_with_project(params, socket.assigns.repository.id))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :webhook))}
  end

  @impl true
  def handle_event("save", %{"webhook" => params}, socket) do
    if Authorization.authorize(
         :repository_update,
         socket.assigns.current_user,
         socket.assigns.repository
       ) ==
         :ok do
      attrs = params_with_project(params, socket.assigns.repository.id)

      case Webhooks.create_webhook(attrs, user: socket.assigns.current_user) do
        {:ok, _webhook} ->
          {:noreply,
           socket
           |> put_flash(:info, "Webhook created successfully.")
           |> assign(
             :webhooks,
             Webhooks.list_webhooks_for_repository(socket.assigns.repository.id)
           )
           |> assign(:form, webhook_form(socket.assigns.repository))}

        {:error, changeset} ->
          {:noreply,
           assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: :webhook))}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
    end
  end

  @impl true
  def handle_event("toggle", %{"id" => webhook_id}, socket) do
    if Authorization.authorize(
         :repository_update,
         socket.assigns.current_user,
         socket.assigns.repository
       ) ==
         :ok do
      case Webhooks.get_webhook_for_project(socket.assigns.repository.id, webhook_id) do
        %Webhook{} = webhook ->
          case Webhooks.update_webhook(webhook, %{active: !webhook.active},
                 user: socket.assigns.current_user
               ) do
            {:ok, _webhook} ->
              {:noreply,
               socket
               |> put_flash(:info, "Webhook updated successfully.")
               |> assign(
                 :webhooks,
                 Webhooks.list_webhooks_for_repository(socket.assigns.repository.id)
               )}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Unable to update webhook.")}
          end

        nil ->
          {:noreply, put_flash(socket, :error, "Webhook not found.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => webhook_id}, socket) do
    if Authorization.authorize(
         :repository_update,
         socket.assigns.current_user,
         socket.assigns.repository
       ) ==
         :ok do
      case Webhooks.get_webhook_for_project(socket.assigns.repository.id, webhook_id) do
        %Webhook{} = webhook ->
          case Webhooks.delete_webhook(webhook, user: socket.assigns.current_user) do
            {:ok, _webhook} ->
              {:noreply,
               socket
               |> put_flash(:info, "Webhook deleted successfully.")
               |> assign(
                 :webhooks,
                 Webhooks.list_webhooks_for_repository(socket.assigns.repository.id)
               )}

            {:error, _reason} ->
              {:noreply, put_flash(socket, :error, "Unable to delete webhook.")}
          end

        nil ->
          {:noreply, put_flash(socket, :error, "Webhook not found.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
      repository_nav={
        %{
          account_handle: @organization.account.handle,
          repository_handle: @repository.handle,
          active: :settings,
          show_settings?: true
        }
      }
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:settings}
      >
        <.settings_layout
          base_path={~p"/#{@organization.account.handle}/#{@repository.handle}/settings"}
          active={:webhooks}
        >
          <.header>
            Webhooks
          </.header>

          <section class="webhooks-form-section">
            <h2 class="webhooks-section-title">Create a webhook</h2>

            <.form
              for={@form}
              id="webhook-form"
              phx-change="validate"
              phx-submit="save"
              class="repository-form"
            >
              <.input field={@form[:repository_id]} type="hidden" />

              <div class="repository-form-group">
                <.input
                  field={@form[:url]}
                  type="url"
                  label="Webhook URL"
                  placeholder="https://example.com/webhooks"
                  class="repository-input"
                  error_class="repository-input repository-input-error"
                />
              </div>

              <div class="repository-form-group">
                <.input
                  field={@form[:events]}
                  type="select"
                  label="Events"
                  options={event_options()}
                  multiple={true}
                  class="repository-input"
                  error_class="repository-input repository-input-error"
                />
                <p class="repository-form-hint">Select one or more events for this webhook.</p>
              </div>

              <div class="repository-form-group">
                <.input
                  field={@form[:secret]}
                  type="password"
                  label="Secret"
                  placeholder="Optional shared secret"
                  class="repository-input"
                  error_class="repository-input repository-input-error"
                />
              </div>

              <div class="repository-form-actions">
                <button type="submit" class="repository-button" id="webhook-submit">
                  Create webhook
                </button>
              </div>
            </.form>
          </section>

          <section class="webhooks-list-section">
            <h2 class="webhooks-section-title">Existing webhooks</h2>

            <div id="webhook-list" class="webhook-list">
              <p :if={@webhooks == []} class="webhooks-empty">No webhooks yet.</p>
              <div
                :for={webhook <- @webhooks}
                id={"webhook-#{webhook.id}"}
                class="webhook-card"
              >
                <div class="webhook-meta">
                  <div class="webhook-header">
                    <p class="webhook-url">{webhook.url}</p>
                    <span class={["badge", webhook.active && "badge--solid"]}>
                      {if webhook.active, do: "Active", else: "Inactive"}
                    </span>
                  </div>
                  <div class="webhook-events">
                    <span :for={event <- webhook.events} class="badge badge--caps">
                      {format_event(event)}
                    </span>
                  </div>
                </div>
                <div class="webhook-actions">
                  <button
                    type="button"
                    class="webhook-action"
                    id={"webhook-toggle-#{webhook.id}"}
                    phx-click="toggle"
                    phx-value-id={webhook.id}
                  >
                    {if webhook.active, do: "Disable", else: "Enable"}
                  </button>
                  <button
                    type="button"
                    class="webhook-action webhook-action-danger"
                    id={"webhook-delete-#{webhook.id}"}
                    phx-click="delete"
                    phx-value-id={webhook.id}
                    phx-confirm="Delete this webhook?"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </section>
        </.settings_layout>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp webhook_form(repository) do
    %Webhook{events: ["push"]}
    |> Webhooks.change_webhook(%{repository_id: repository.id})
    |> to_form(as: :webhook)
  end

  defp params_with_project(params, repository_id) do
    Map.put(params, "repository_id", repository_id)
  end

  defp event_options do
    Enum.map(Webhook.allowed_events(), fn event ->
      {format_event(event), event}
    end)
  end

  defp format_event(event) do
    event
    |> String.replace(".", " ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
