defmodule Micelio.Forges.ForgeAboutCache do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @ttl_ms :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_or_fetch(host, owner, repo, opts \\ []) do
    key = {host, owner, repo}

    case lookup(key) do
      {:ok, data} ->
        {:ok, data}

      :miss ->
        case Micelio.Forges.ForgeAbout.fetch(host, owner, repo, opts) do
          {:ok, data} = result ->
            put(key, data)
            result

          error ->
            error
        end
    end
  end

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, data, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, data}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp put(key, data) do
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {key, data, expires_at})
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
