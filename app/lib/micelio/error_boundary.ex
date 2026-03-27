defmodule Micelio.ErrorBoundary do
  @moduledoc """
  LiveView error boundary component for rendering safe fallbacks.

  Use this component to wrap sections that may fail during rendering:

      <.error_boundary
        id="agent-progress-boundary"
        context=%{route: ~p"/org/repo/agents", params: @params}
        retry_path={~p"/org/repo/agents"}
        user_id={@current_user && @current_user.id}
        repository_id={@repository.id}
      >
        ...live content...
      </.error_boundary>
  """

  use Phoenix.Component

  alias Micelio.Errors.Capture

  attr :id, :string, required: true
  attr :context, :map, default: %{}
  attr :user_id, :any, default: nil
  attr :repository_id, :any, default: nil
  attr :retry_path, :string, default: nil
  attr :report_href, :string, default: nil
  attr :title, :string, default: "Something went wrong"
  attr :message, :string, default: "We hit a snag rendering this section. Please try again."
  attr :capture_async, :boolean, default: true
  attr :errors, :list, default: nil

  slot :inner_block, required: true

  def error_boundary(assigns) do
    {content, error} = safe_render(assigns)

    assigns =
      assigns
      |> assign(:content, content)
      |> assign(:error, error)

    if error do
      capture_error(assigns, error)
    end

    ~H"""
    <%= if @error do %>
      <section class="error-boundary" id={@id} role="alert">
        <div class="error-boundary-card">
          <h2 class="error-boundary-title">{@title}</h2>
          <p class="error-boundary-message">{@message}</p>
          <div class="error-boundary-actions">
            <.link :if={@retry_path} navigate={@retry_path} class="btn btn-soft">
              Retry
            </.link>
            <.link :if={@report_href} href={@report_href} class="btn btn-primary">
              Report
            </.link>
          </div>
        </div>
      </section>
    <% else %>
      {@content}
    <% end %>
    """
  end

  defp safe_render(assigns) do
    changed = Map.get(assigns, :__changed__, %{})
    {Phoenix.Component.__render_slot__(changed, assigns.inner_block, nil), nil}
  rescue
    exception ->
      {nil, {:exception, exception, __STACKTRACE__}}
  catch
    :exit, reason ->
      {nil, {:exit, reason, __STACKTRACE__}}
  end

  defp capture_error(assigns, {:exception, exception, stacktrace}) do
    Capture.capture_exception(exception,
      kind: :liveview_crash,
      severity: :error,
      error_kind: :error,
      stacktrace: stacktrace,
      context: build_context(assigns),
      metadata: %{
        boundary_id: assigns.id,
        boundary: "error_boundary",
        error_type: "exception"
      },
      user_id: assigns.user_id,
      repository_id: assigns.repository_id,
      source: "liveview_error_boundary",
      async: assigns.capture_async,
      errors: assigns.errors
    )
  end

  defp capture_error(assigns, {:exit, reason, stacktrace}) do
    exception = %RuntimeError{message: "LiveView exited: #{inspect(reason)}"}

    Capture.capture_exception(exception,
      kind: :liveview_crash,
      severity: :error,
      error_kind: :exit,
      stacktrace: stacktrace,
      context: build_context(assigns),
      metadata: %{
        boundary_id: assigns.id,
        boundary: "error_boundary",
        error_type: "exit",
        exit_reason: inspect(reason)
      },
      user_id: assigns.user_id,
      repository_id: assigns.repository_id,
      source: "liveview_error_boundary",
      async: assigns.capture_async,
      errors: assigns.errors
    )
  end

  defp build_context(assigns) do
    assigns.context
    |> Map.put(:assigns, sanitize_assigns(assigns))
  end

  defp sanitize_assigns(assigns) do
    assigns
    |> Map.drop([:socket, :__changed__, :flash, :inner_block, :myself, :content, :error])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case sanitize_value(value) do
        :skip -> acc
        sanitized -> Map.put(acc, key, sanitized)
      end
    end)
  end

  defp sanitize_value(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_atom(value) or
              is_nil(value) do
    value
  end

  defp sanitize_value(value) when is_list(value) do
    value
    |> Enum.take(20)
    |> Enum.map(&sanitize_value/1)
    |> Enum.reject(&(&1 == :skip))
  end

  defp sanitize_value(%_{} = struct) do
    %{__struct__: inspect(struct.__struct__)}
  end

  defp sanitize_value(value) when is_map(value) do
    value
    |> Enum.take(20)
    |> Enum.reduce(%{}, fn {key, nested}, acc ->
      case sanitize_value(nested) do
        :skip -> acc
        sanitized -> Map.put(acc, key, sanitized)
      end
    end)
  end

  defp sanitize_value(_value), do: :skip
end
