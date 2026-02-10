defmodule Micelio.Storage.FakeOrigin do
  @moduledoc false

  @table :micelio_storage_fake_origin

  def put(key, content) when is_binary(key) and is_binary(content) do
    ensure_table()
    etag = "etag-" <> Integer.to_string(:erlang.phash2({key, content}))
    :ets.insert(@table, {key, content, etag})
    {:ok, key}
  end

  def get(key) when is_binary(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, content, _etag}] -> {:ok, content}
      [] -> {:error, :not_found}
    end
  end

  def get_with_metadata(key) when is_binary(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, content, etag}] -> {:ok, %{content: content, etag: etag}}
      [] -> {:error, :not_found}
    end
  end

  def delete(key) when is_binary(key) do
    ensure_table()
    :ets.delete(@table, key)
    {:ok, key}
  end

  def list(prefix) when is_binary(prefix) do
    ensure_table()

    keys =
      :ets.tab2list(@table)
      |> Enum.map(fn {key, _content, _etag} -> key end)
      |> Enum.filter(&String.starts_with?(&1, prefix))

    {:ok, keys}
  end

  def exists?(key) when is_binary(key) do
    ensure_table()
    :ets.member(@table, key)
  end

  def head(key) when is_binary(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, content, etag}] -> {:ok, %{etag: etag, size: byte_size(content)}}
      [] -> {:error, :not_found}
    end
  end

  def put_if_match(key, content, etag)
      when is_binary(key) and is_binary(content) and is_binary(etag) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, _content, ^etag}] -> put(key, content)
      [{^key, _content, _etag}] -> {:error, :precondition_failed}
      [] -> {:error, :precondition_failed}
    end
  end

  def put_if_none_match(key, content) when is_binary(key) and is_binary(content) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [] -> put(key, content)
      _ -> {:error, :precondition_failed}
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :set, :public])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end
end
