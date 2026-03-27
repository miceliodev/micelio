defmodule Micelio.Mic.Telemetry do
  @moduledoc """
  Telemetry handlers for mic conflict checks and rollup builds.
  """

  use GenServer

  require Logger

  @handler_id "micelio-mic-telemetry"
  @events [
    [:micelio, :mic, :conflict_check],
    [:micelio, :mic, :rollup_build]
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, %{})
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(@handler_id)
    {:ok, state}
  end

  def handle_event([:micelio, :mic, :conflict_check], measurements, metadata, _config) do
    Logger.debug(
      "mic.conflict_check scan_ranges=#{measurements.scan_ranges} paths=#{measurements.paths} project=#{metadata.repository_id}"
    )
  end

  def handle_event([:micelio, :mic, :rollup_build], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug(
      "mic.rollup_build position=#{measurements.position} duration_ms=#{duration_ms} project=#{metadata.repository_id}"
    )
  end
end
