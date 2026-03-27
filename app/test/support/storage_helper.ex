defmodule Micelio.StorageHelper do
  @moduledoc """
  Test helper for creating isolated storage configurations.

  This module enables tests to run in parallel by providing isolated
  storage directories instead of relying on global Application config.

  ## Usage

      setup do
        {:ok, storage} = StorageHelper.create_isolated_storage()
        
        on_exit(fn ->
          StorageHelper.cleanup(storage)
        end)

        {:ok, storage: storage}
      end

      test "something with storage", %{storage: storage} do
        StorageHelper.with_config(storage, fn ->
          # Code that uses Micelio.Storage will use isolated config
          Micelio.Storage.put("key", "value")
        end)
      end
  """

  @doc """
  Creates an isolated storage configuration for testing.

  Returns a map with:
  - `:config` - Keyword list config to pass to Storage functions
  - `:path` - The storage directory path
  - `:base_dir` - The base temp directory (for cleanup)
  """
  def create_isolated_storage(opts \\ []) do
    unique = System.unique_integer([:positive])
    base = Keyword.get(opts, :base_dir, System.tmp_dir!())
    base_dir = Path.join([base, "micelio-test-#{unique}"])
    storage_dir = Path.join(base_dir, "storage")

    File.mkdir_p!(storage_dir)

    config = [backend: :local, local_path: storage_dir]

    {:ok, %{config: config, path: storage_dir, base_dir: base_dir}}
  end

  @doc """
  Cleans up an isolated storage created by `create_isolated_storage/1`.
  """
  def cleanup(%{base_dir: base_dir}) do
    # Use rm_rf (without !) to gracefully handle cases where background
    # processes may still be writing to the directory
    case File.rm_rf(base_dir) do
      {:ok, _} -> :ok
      # File.rm_rf returns {:error, reason, file} on failure
      {:error, _reason, _file} -> :ok
    end
  end

  def cleanup(_), do: :ok

  @doc """
  Provides storage opts for functions that accept `:storage_config`.
  """
  def storage_opts(%{config: config}), do: [storage_config: config]
  def storage_opts(config) when is_list(config), do: [storage_config: config]

  @doc """
  Executes a function with storage opts.

  The function must accept one argument (the storage opts).
  """
  def with_config(%{config: config}, fun) when is_function(fun, 1) do
    fun.(storage_config: config)
  end

  def with_config(config, fun) when is_list(config) and is_function(fun, 1) do
    fun.(storage_config: config)
  end

  @doc """
  Sets up isolated storage and returns the config in test context.
  """
  def setup_isolated_storage(_context \\ %{}) do
    {:ok, storage} = create_isolated_storage()

    ExUnit.Callbacks.on_exit(fn ->
      cleanup(storage)
    end)

    {:ok, storage_config: storage.config, storage_path: storage.path}
  end
end
