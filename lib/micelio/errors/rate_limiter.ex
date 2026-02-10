defmodule Micelio.Errors.RateLimiter do
  @moduledoc false

  use GenServer

  alias Micelio.Errors.Config

  require Logger

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, state}
  end

  def allow?(kind, opts \\ [])

  def allow?(kind, opts) when is_atom(kind) do
    case :ets.whereis(@table) do
      :undefined ->
        true

      _table ->
        minute = current_minute()
        maybe_cleanup(minute)

        kind_limit = Config.capture_rate_limit_per_kind_per_minute(opts)
        total_limit = Config.capture_rate_limit_total_per_minute(opts)

        kind_count = increment({minute, kind})
        total_count = increment({minute, :total})

        exceeded_kind? = limit_exceeded?(kind_limit, kind_count)
        exceeded_total? = limit_exceeded?(total_limit, total_count)

        if exceeded_kind? or exceeded_total? do
          if Application.get_env(:micelio, :environment) != :test do
            Logger.warning(
              "error capture rate limit exceeded kind=#{kind} kind_count=#{kind_count} total_count=#{total_count}"
            )
          end

          false
        else
          true
        end
    end
  end

  def allow?(_kind, _opts), do: true

  def reset! do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _table -> :ets.delete_all_objects(@table)
    end
  end

  defp increment(key) do
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
  end

  defp limit_exceeded?(limit, count) when is_integer(limit) and limit > 0, do: count > limit
  defp limit_exceeded?(_limit, _count), do: false

  defp current_minute do
    System.system_time(:second) |> div(60)
  end

  defp maybe_cleanup(minute) do
    last_cleanup =
      case :ets.lookup(@table, :last_cleanup) do
        [{:last_cleanup, value}] -> value
        _ -> nil
      end

    if is_nil(last_cleanup) or minute > last_cleanup do
      :ets.insert(@table, {:last_cleanup, minute})
      cleanup_before(minute - 1)
    end
  end

  defp cleanup_before(minute_cutoff) when minute_cutoff >= 0 do
    match_spec = [
      {{{:"$1", :_}, :_}, [{:<, :"$1", minute_cutoff}], [true]}
    ]

    :ets.select_delete(@table, match_spec)
  end

  defp cleanup_before(_minute_cutoff), do: :ok
end
