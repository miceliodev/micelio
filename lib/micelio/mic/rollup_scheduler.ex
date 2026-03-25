defmodule Micelio.Mic.RollupScheduler do
  @moduledoc """
  Periodic rollup rebuild scheduler.

  NOTE: This GenServer runs independently on every node. When scaling to
  multiple nodes, every instance will redundantly rebuild rollups for all
  repositories. Consider migrating to Oban (which uses Postgres advisory
  locks for single-execution guarantees) or a distributed singleton
  (e.g. `:global`, Horde) to avoid redundant work.
  """

  use GenServer

  alias Micelio.Mic.RollupRebuilder
  alias Micelio.Repositories

  require Logger

  @default_interval_ms 300_000
  @default_lookback 1_000_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    config = Application.get_env(:micelio, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, true)
    interval_ms = Keyword.get(config, :interval_ms, @default_interval_ms)
    lookback = Keyword.get(config, :lookback_positions, @default_lookback)

    if enabled do
      send(self(), :run)
      {:ok, %{interval_ms: interval_ms, lookback: lookback}}
    else
      {:ok, %{interval_ms: interval_ms, lookback: lookback, disabled: true}}
    end
  end

  @impl true
  def handle_info(:run, %{interval_ms: interval_ms} = state) do
    Logger.debug("mic.rollup_scheduler tick")
    rebuild_recent_rollups(state)
    Process.send_after(self(), :run, interval_ms)
    {:noreply, state}
  end

  defp rebuild_recent_rollups(%{lookback: lookback}) do
    Repositories.list_repositories()
    |> Enum.each(fn repository ->
      storage_opts = [repository: repository]

      case RollupRebuilder.head_position(repository.id, storage_opts) do
        {:ok, position} ->
          from_position = max(1, position - lookback + 1)
          _ = RollupRebuilder.rebuild(repository.id, from_position, position, storage_opts)

        {:error, reason} ->
          Logger.debug("mic.rollup_scheduler error=#{inspect(reason)} project=#{repository.id}")
      end
    end)
  end
end
