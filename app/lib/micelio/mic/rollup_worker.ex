defmodule Micelio.Mic.RollupWorker do
  @moduledoc """
  Asynchronous rollup builder for conflict filters.
  """

  alias Micelio.Mic.ConflictIndex

  require Logger

  @supervisor Micelio.Mic.RollupSupervisor

  def enqueue(repository_id, position, change_filter) do
    enqueue(repository_id, position, change_filter, [])
  end

  def enqueue(repository_id, position, change_filter, opts) do
    case Process.whereis(@supervisor) do
      nil ->
        Logger.debug("mic.rollup inline position=#{position} project=#{repository_id}")
        ConflictIndex.maybe_update_rollups(repository_id, position, change_filter, opts)

      _pid ->
        Task.Supervisor.start_child(@supervisor, fn ->
          Logger.debug("mic.rollup async position=#{position} project=#{repository_id}")
          start = System.monotonic_time()

          result =
            ConflictIndex.maybe_update_rollups(repository_id, position, change_filter, opts)

          elapsed = System.monotonic_time() - start

          :telemetry.execute(
            [:micelio, :mic, :rollup_build],
            %{duration: elapsed, position: position},
            %{repository_id: repository_id}
          )

          result
        end)

        :ok
    end
  end
end
