defmodule MicelioWeb.AdminErrorsLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Errors
  alias Micelio.Errors.Error
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    error = Errors.get_error!(id)

    socket =
      socket
      |> assign(:page_title, "Error Details")
      |> PageMeta.assign(
        description: "Error details for admin review.",
        canonical_url: url(~p"/admin/errors/#{error.id}")
      )
      |> assign(:error, error)
      |> assign(:resolution_note, current_note(error))

    {:ok, socket}
  end

  @impl true
  def handle_event("update_note", %{"resolution_note" => note}, socket) do
    {:noreply, assign(socket, :resolution_note, note)}
  end

  @impl true
  def handle_event("resolve", %{"scope" => scope}, socket) do
    %{error: error, current_user: user, resolution_note: note} = socket.assigns

    case scope do
      "similar" ->
        _ = Errors.resolve_similar_errors(error, user.id, note)

      _ ->
        _ = Errors.resolve_error(error, user.id, note)
    end

    updated = Errors.get_error!(error.id)

    {:noreply, assign(socket, error: updated, resolution_note: current_note(updated))}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    _ = Errors.delete_error(socket.assigns.error)

    {:noreply,
     socket
     |> put_flash(:info, "Error deleted.")
     |> push_navigate(to: ~p"/admin/errors")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <div class="admin-error" id={"admin-error-#{@error.id}"}>
        <.header>
          Error Details
          <:subtitle>Fingerprint: {@error.fingerprint}</:subtitle>
          <:actions>
            <.link navigate={~p"/admin/errors"} class="button">
              Back to list
            </.link>
          </:actions>
        </.header>

        <section class="admin-error-summary">
          <div class="admin-error-summary-main">
            <h2>{@error.message}</h2>
            <div class="admin-error-summary-meta">
              <span class={"admin-errors-severity admin-errors-severity-#{@error.severity}"}>
                {format_label(@error.severity)}
              </span>
              <span>Kind: {format_label(@error.kind)}</span>
              <span>Status: {status_label(@error)}</span>
              <span>Occurrences: {@error.occurrence_count}</span>
            </div>
          </div>
          <div class="admin-error-summary-details">
            <div>First seen: {format_datetime(@error.first_seen_at)}</div>
            <div>Last seen: {format_datetime(@error.last_seen_at)}</div>
            <div>Occurred at: {format_datetime(@error.occurred_at)}</div>
            <div>Resolved at: {format_datetime(@error.resolved_at)}</div>
            <div>Resolved by: {format_user(@error.resolved_by_id)}</div>
            <div>User ID: {format_user(@error.user_id)}</div>
            <div>Project ID: {format_repository(@error.repository_id)}</div>
          </div>
        </section>

        <section class="admin-error-actions">
          <form phx-change="update_note" phx-submit="resolve">
            <label for="resolution_note">Resolution note (optional)</label>
            <textarea
              id="resolution_note"
              name="resolution_note"
              placeholder="Add a note about the resolution"
              rows="3"
            >{@resolution_note}</textarea>
            <div class="admin-error-actions-buttons">
              <button
                type="submit"
                name="scope"
                value="single"
                disabled={not is_nil(@error.resolved_at)}
              >
                Resolve
              </button>
              <button
                type="submit"
                name="scope"
                value="similar"
                disabled={not is_nil(@error.resolved_at)}
              >
                Resolve similar
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-confirm="Delete this error?"
                class="danger"
              >
                Delete
              </button>
            </div>
          </form>
        </section>

        <section class="admin-error-stacktrace">
          <div class="admin-error-section-header">
            <h3>Stacktrace</h3>
            <button
              type="button"
              id="admin-error-copy-stacktrace"
              phx-hook="CopyToClipboard"
              data-copy-target="admin-error-stacktrace"
            >
              Copy stacktrace
            </button>
          </div>
          <pre id="admin-error-stacktrace">{format_stacktrace(@error.stacktrace)}</pre>
        </section>

        <section class="admin-error-metadata">
          <h3>Metadata</h3>
          <pre>{format_map(@error.metadata)}</pre>
        </section>

        <section class="admin-error-context">
          <h3>Context</h3>
          <pre>{format_map(@error.context)}</pre>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp format_label(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_user(nil), do: "n/a"
  defp format_user(value), do: value

  defp format_repository(nil), do: "n/a"
  defp format_repository(value), do: value

  defp format_stacktrace(nil), do: "No stacktrace captured."
  defp format_stacktrace(value) when is_binary(value), do: value
  defp format_stacktrace(value), do: inspect(value)

  defp format_map(value) when value in [nil, %{}], do: "{}"

  defp format_map(value) do
    inspect(value, pretty: true, limit: :infinity, width: 120)
  end

  defp status_label(%Error{resolved_at: nil}), do: "Unresolved"
  defp status_label(%Error{}), do: "Resolved"

  defp current_note(%Error{metadata: %{"resolution_note" => note}}) when is_binary(note), do: note

  defp current_note(_), do: ""
end
