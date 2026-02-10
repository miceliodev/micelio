defmodule Micelio.Storage.Local do
  @moduledoc """
  Local filesystem storage backend.

  Stores files in a local directory structure.
  Uses the configured `:local_path` under `:micelio, Micelio.Storage`
  (set in runtime via `STORAGE_LOCAL_PATH`), falling back to a temporary
  directory when unset.
  """

  @doc """
  Stores content at the given key.
  """
  def put(key, content, opts \\ []) do
    path = build_path(key, opts)

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, content) do
      {:ok, key}
    end
  end

  @doc """
  Retrieves content by key.
  """
  def get(key, opts \\ []) do
    path = build_path(key, opts)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Retrieves content by key along with a synthetic ETag.
  """
  def get_with_metadata(key, opts \\ []) do
    with {:ok, content} <- get(key, opts) do
      {:ok, %{content: content, etag: etag_for(content)}}
    end
  end

  @doc """
  Deletes a file by key.
  """
  def delete(key, opts \\ []) do
    path = build_path(key, opts)

    case File.rm(path) do
      :ok -> {:ok, key}
      {:error, :enoent} -> {:ok, key}
      error -> error
    end
  end

  @doc """
  Lists files with the given prefix.
  """
  def list(prefix, opts \\ []) do
    base_path = base_path(opts)
    pattern = Path.join([base_path, prefix, "**", "*"])

    files =
      pattern
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        String.replace_prefix(path, base_path <> "/", "")
      end)

    {:ok, files}
  end

  @doc """
  Checks if a file exists.
  """
  def exists?(key, opts \\ []) do
    path = build_path(key, opts)
    File.exists?(path)
  end

  @doc """
  Returns metadata for a key when available.
  """
  def head(key, opts \\ []) do
    path = build_path(key, opts)

    case File.read(path) do
      {:ok, content} ->
        {:ok, %{etag: etag_for(content), size: byte_size(content)}}

      {:error, :enoent} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Stores content only if the current ETag matches.
  """
  def put_if_match(key, content, etag, opts \\ []) do
    with_lock(key, opts, fn ->
      case File.read(build_path(key, opts)) do
        {:ok, existing} ->
          if etag_for(existing) == etag do
            put(key, content, opts)
          else
            {:error, :precondition_failed}
          end

        {:error, :enoent} ->
          {:error, :precondition_failed}

        error ->
          error
      end
    end)
  end

  @doc """
  Stores content only if the key does not exist.
  """
  def put_if_none_match(key, content, opts \\ []) do
    with_lock(key, opts, fn ->
      if exists?(key, opts) do
        {:error, :precondition_failed}
      else
        put(key, content, opts)
      end
    end)
  end

  defp build_path(key, opts) do
    Path.join(base_path(opts), key)
  end

  defp base_path(opts) do
    case Keyword.get(opts, :base_path) do
      path when is_binary(path) -> path
      _ -> config_base_path()
    end
  end

  defp config_base_path do
    config = Application.get_env(:micelio, Micelio.Storage, [])
    Keyword.get(config, :local_path, default_path())
  end

  defp default_path do
    Path.join([System.tmp_dir!(), "micelio", "storage"])
  end

  defp ensure_directory(file_path) do
    file_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp etag_for(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp with_lock(key, opts, fun) do
    case node() do
      :nonode@nohost -> fun.()
      _ -> :global.trans({:storage_local_lock, base_path(opts), key}, fun)
    end
  end
end
