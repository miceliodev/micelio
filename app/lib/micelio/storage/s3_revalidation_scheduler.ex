defmodule Micelio.Storage.S3RevalidationScheduler do
  @moduledoc false

  use GenServer

  alias Micelio.Storage.S3Revalidation

  require Logger

  @default_run_hour 2
  @default_run_minute 0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    config = Application.get_env(:micelio, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, true)
    run_hour = Keyword.get(config, :run_hour, @default_run_hour)
    run_minute = Keyword.get(config, :run_minute, @default_run_minute)

    state = %{enabled: enabled, run_hour: run_hour, run_minute: run_minute}

    if enabled do
      schedule_next(state)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:run, state) do
    _ = run_revalidation()
    schedule_next(state)
    {:noreply, state}
  end

  def run_revalidation do
    if oban_available?() do
      case enqueue_job() do
        {:ok, _job} ->
          :ok

        _ ->
          S3Revalidation.run()
      end
    else
      S3Revalidation.run()
    end
  end

  defp schedule_next(%{run_hour: run_hour, run_minute: run_minute} = state) do
    now = DateTime.utc_now()
    today = Date.utc_today()

    target_date =
      if now.hour < run_hour or (now.hour == run_hour and now.minute < run_minute) do
        today
      else
        Date.add(today, 1)
      end

    {:ok, target_dt} = DateTime.new(target_date, {run_hour, run_minute, 0}, "Etc/UTC")
    delay_ms = DateTime.diff(target_dt, now, :millisecond)

    Logger.debug("storage.s3_revalidation next_run=#{DateTime.to_iso8601(target_dt)}")

    Process.send_after(self(), :run, max(delay_ms, 0))
    state
  end

  defp oban_available? do
    Code.ensure_loaded?(Oban) and
      function_exported?(Oban, :insert, 1) and
      Code.ensure_loaded?(Oban.Job) and
      function_exported?(Oban.Job, :new, 2)
  end

  defp enqueue_job do
    # Oban is not currently a dependency - this is a placeholder for future use
    {:ok, :oban_not_configured}
  end
end
