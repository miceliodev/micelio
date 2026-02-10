defmodule Micelio.Abuse.Blocklist do
  @moduledoc """
  Simple in-memory blocklist with TTL for abuse mitigation.
  """

  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  def blocked?(key) do
    case table_ready?() do
      false ->
        :ok

      true ->
        now = System.monotonic_time(:millisecond)

        case :ets.lookup(@table, key) do
          [{^key, expires_at}] when expires_at > now ->
            {:blocked, expires_at - now}

          [{^key, _expired_at}] ->
            :ets.delete(@table, key)
            :ok

          [] ->
            :ok
        end
    end
  end

  def block(key, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    if table_ready?() do
      expires_at = System.monotonic_time(:millisecond) + ttl_ms
      :ets.insert(@table, {key, expires_at})
    end

    :ok
  end

  defp table_ready? do
    :ets.whereis(@table) != :undefined
  end
end
