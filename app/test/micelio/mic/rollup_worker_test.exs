defmodule Micelio.Mic.RollupWorkerTest do
  # async: false because this test spawns background workers that need storage config
  # and spawned processes don't inherit process dictionary
  use ExUnit.Case, async: false

  alias Micelio.Mic.{Binary, ConflictIndex, RollupWorker}
  alias Micelio.Sessions.Conflict
  alias Micelio.Storage
  alias Micelio.StorageHelper

  setup do
    {:ok, storage} = StorageHelper.create_isolated_storage()

    on_exit(fn ->
      StorageHelper.cleanup(storage)
    end)

    {:ok, %{storage_config: storage.config}}
  end

  test "enqueue builds rollup filters in the background", %{storage_config: storage_config} do
    opts = [storage_config: storage_config]
    repository_id = "proj-#{System.unique_integer([:positive])}"
    position = 1

    filter = Conflict.build_filter(["lib/a.ex"], size: 64, hash_count: 3)

    landing =
      Binary.encode_landing(%{
        position: position,
        landed_at_ms: System.system_time(:millisecond),
        tree_hash: Binary.zero_hash(),
        session_id: "sess-1",
        change_filter: filter
      })

    assert {:ok, _} = Storage.put(landing_key(repository_id, position), landing, opts)
    assert :ok = RollupWorker.enqueue(repository_id, position, filter, opts)

    rollup_key = rollup_key(repository_id, 1, position)
    assert :ok = wait_until(fn -> Storage.exists?(rollup_key, opts) end)

    assert {:ok, content} = Storage.get(rollup_key, opts)
    assert {:ok, rollup_filter} = Binary.decode_filter_index(content)
    assert Conflict.might_conflict?(rollup_filter, "lib/a.ex")

    checkpoint_key = checkpoint_key(repository_id, 1)
    assert :ok = wait_until(fn -> Storage.exists?(checkpoint_key, opts) end)
    assert {:ok, checkpoint} = Storage.get(checkpoint_key, opts)
    assert {:ok, checkpoint_position} = Binary.decode_rollup_checkpoint(checkpoint)
    assert checkpoint_position == ConflictIndex.rollup_size(1)
  end

  defp landing_key(repository_id, position) do
    "repositories/#{repository_id}/landing/#{pad_position(position)}.bin"
  end

  defp rollup_key(repository_id, level, start_position) do
    "repositories/#{repository_id}/landing/bloom/level-#{level}/#{pad_position(start_position)}.bin"
  end

  defp checkpoint_key(repository_id, level) do
    "repositories/#{repository_id}/landing/bloom/checkpoint/level-#{level}.bin"
  end

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp wait_until(fun, attempts \\ 30, delay_ms \\ 25) when is_function(fun, 0) do
    Enum.reduce_while(1..attempts, {:error, :timeout}, fn _, _acc ->
      if fun.() do
        {:halt, :ok}
      else
        Process.sleep(delay_ms)
        {:cont, {:error, :timeout}}
      end
    end)
  end
end
