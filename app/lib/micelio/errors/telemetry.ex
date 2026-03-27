defmodule Micelio.Errors.Telemetry do
  @moduledoc false

  use GenServer

  alias Micelio.Errors.AgentReporter
  alias Micelio.Errors.Capture
  alias Micelio.Errors.Config
  alias Micelio.Errors.ObanReporter

  @live_view_handler_id "micelio-errors-liveview"
  @live_view_events [
    [:phoenix, :live_view, :mount, :exception],
    [:phoenix, :live_view, :handle_event, :exception],
    [:phoenix, :live_view, :handle_params, :exception],
    [:phoenix, :live_view, :handle_info, :exception]
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    if Config.capture_enabled?() do
      attach_live_view()
      ObanReporter.attach()
      AgentReporter.attach()
    end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    detach_live_view()
    ObanReporter.detach()
    AgentReporter.detach()
    :ok
  end

  def handle_live_view_exception(_event, _measurements, metadata, config) do
    reason = Map.get(metadata, :reason)
    stacktrace = Map.get(metadata, :stacktrace, [])
    kind = Map.get(metadata, :kind, :error)

    Capture.capture_exception(reason,
      kind: :liveview_crash,
      error_kind: kind,
      stacktrace: stacktrace,
      metadata: live_view_metadata(metadata),
      source: :liveview,
      errors: errors_config(config)
    )
  end

  defp attach_live_view do
    if Code.ensure_loaded?(Phoenix.LiveView) do
      :telemetry.attach_many(
        @live_view_handler_id,
        @live_view_events,
        &__MODULE__.handle_live_view_exception/4,
        nil
      )
    else
      :ok
    end
  end

  defp detach_live_view do
    if Code.ensure_loaded?(Phoenix.LiveView) do
      :telemetry.detach(@live_view_handler_id)
    else
      :ok
    end
  end

  defp live_view_metadata(metadata) do
    %{
      view: Map.get(metadata, :view),
      live_action: Map.get(metadata, :live_action),
      params: Map.get(metadata, :params),
      event: Map.get(metadata, :event)
    }
  end

  defp errors_config(nil), do: nil

  defp errors_config(config) when is_list(config) do
    Keyword.get(config, :errors)
  end

  defp errors_config(config) when is_map(config) do
    Map.get(config, :errors)
  end
end
