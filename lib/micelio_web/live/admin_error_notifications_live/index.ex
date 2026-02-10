defmodule MicelioWeb.AdminErrorNotificationsLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Errors
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    settings = Errors.get_notification_settings()
    retention_settings = Errors.get_retention_settings()

    socket =
      socket
      |> assign(:page_title, "Error notification settings")
      |> PageMeta.assign(
        description: "Configure error alert notifications for admins.",
        canonical_url: url(~p"/admin/errors/settings")
      )
      |> assign(:settings, settings)
      |> assign(:form, to_form(Errors.change_notification_settings(settings), as: :settings))
      |> assign(:retention_settings, retention_settings)
      |> assign(
        :retention_form,
        to_form(Errors.change_retention_settings(retention_settings), as: :retention)
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Errors.change_notification_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    case Errors.update_notification_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Notification settings updated.")
         |> assign(:settings, settings)
         |> assign(:form, to_form(Errors.change_notification_settings(settings), as: :settings))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: :settings))}
    end
  end

  @impl true
  def handle_event("validate_retention", %{"retention" => params}, socket) do
    changeset =
      socket.assigns.retention_settings
      |> Errors.change_retention_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :retention_form, to_form(changeset, as: :retention))}
  end

  @impl true
  def handle_event("save_retention", %{"retention" => params}, socket) do
    case Errors.update_retention_settings(params) do
      {:ok, retention_settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Retention settings updated.")
         |> assign(:retention_settings, retention_settings)
         |> assign(
           :retention_form,
           to_form(Errors.change_retention_settings(retention_settings), as: :retention)
         )}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :retention_form,
           to_form(Map.put(changeset, :action, :validate), as: :retention)
         )}
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
      <div class="admin-errors-settings" id="admin-errors-settings">
        <div class="admin-errors-settings-header">
          <.header>
            Error notifications
            <:subtitle>
              <p>Configure how admins are alerted when new errors are captured.</p>
            </:subtitle>
          </.header>
          <div class="admin-errors-settings-actions">
            <.link navigate={~p"/admin/errors"} class="button">
              Back to errors
            </.link>
          </div>
        </div>

        <.form
          for={@form}
          id="admin-error-notifications-form"
          phx-change="validate"
          phx-submit="save"
          class="admin-errors-settings-form"
        >
          <section class="admin-errors-settings-section">
            <h2 class="admin-section-title">Channels</h2>
            <div class="admin-errors-settings-grid">
              <.input
                field={@form[:email_enabled]}
                type="checkbox"
                label="Email admins"
              />
              <.input
                field={@form[:webhook_url]}
                type="url"
                label="Webhook URL"
                placeholder="https://hooks.example.com/errors"
              />
              <.input
                field={@form[:slack_webhook_url]}
                type="url"
                label="Slack webhook URL"
                placeholder="https://hooks.slack.com/services/..."
              />
            </div>
          </section>

          <section class="admin-errors-settings-section">
            <h2 class="admin-section-title">Triggers</h2>
            <div class="admin-errors-settings-grid admin-errors-settings-triggers">
              <.input
                field={@form[:notify_on_new]}
                type="checkbox"
                label="Notify on new error fingerprints"
              />
              <.input
                field={@form[:notify_on_threshold]}
                type="checkbox"
                label="Notify when error rate exceeds threshold"
              />
              <.input
                field={@form[:notify_on_critical]}
                type="checkbox"
                label="Notify on critical severity"
              />
            </div>
            <p class="admin-errors-settings-hint">
              Thresholds use the instance defaults (10 errors in 5 minutes). Rate limits apply.
            </p>
          </section>

          <section class="admin-errors-settings-section">
            <h2 class="admin-section-title">Quiet hours (UTC)</h2>
            <div class="admin-errors-settings-grid admin-errors-settings-quiet">
              <.input
                field={@form[:quiet_hours_enabled]}
                type="checkbox"
                label="Enable quiet hours"
              />
              <.input
                field={@form[:quiet_hours_start]}
                type="select"
                label="Start hour"
                options={hour_options()}
              />
              <.input
                field={@form[:quiet_hours_end]}
                type="select"
                label="End hour"
                options={hour_options()}
              />
            </div>
            <p class="admin-errors-settings-hint">
              During quiet hours, notifications are suppressed.
            </p>
          </section>

          <div class="admin-errors-settings-actions">
            <button type="submit" class="button">
              Save settings
            </button>
          </div>
        </.form>

        <.form
          for={@retention_form}
          id="admin-error-retention-form"
          phx-change="validate_retention"
          phx-submit="save_retention"
          class="admin-errors-settings-form"
        >
          <section class="admin-errors-settings-section">
            <h2 class="admin-section-title">Retention policy</h2>
            <div class="admin-errors-settings-grid admin-errors-settings-retention">
              <.input
                field={@retention_form[:resolved_retention_days]}
                type="number"
                min="1"
                label="Resolved retention (days)"
              />
              <.input
                field={@retention_form[:unresolved_retention_days]}
                type="number"
                min="1"
                label="Unresolved retention (days)"
              />
              <.input
                field={@retention_form[:archive_enabled]}
                type="checkbox"
                label="Archive to storage before deletion"
              />
            </div>
            <p class="admin-errors-settings-hint">
              Archives are written to the storage backend using the configured prefix.
            </p>
          </section>

          <div class="admin-errors-settings-actions">
            <button type="submit" class="button">
              Save retention settings
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp hour_options do
    Enum.map(0..23, fn hour ->
      label = String.pad_leading(Integer.to_string(hour), 2, "0") <> ":00"
      {label, hour}
    end)
  end
end
