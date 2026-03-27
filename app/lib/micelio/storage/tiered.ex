defmodule Micelio.Storage.Tiered do
  @moduledoc """
  Tiered caching storage backend: RAM -> SSD -> CDN -> origin.
  """

  @entries_table :micelio_storage_tiered_entries
  @order_table :micelio_storage_tiered_order
  @meta_table :micelio_storage_tiered_meta

  @default_memory_max_bytes 64_000_000
  @default_cache_disk_path Path.join([System.tmp_dir!(), "micelio", "cache"])
  @default_cdn_timeout_ms 2_000

  def put(key, content), do: put(key, content, config())

  def put(key, content, config) do
    with {:ok, _} <- origin_put(config, key, content) do
      _ = cache_put(config, key, content)
      {:ok, key}
    end
  end

  def get(key), do: get(key, config())

  def get(key, config) do
    case memory_get(config, key) do
      {:ok, content} ->
        {:ok, content}

      :miss ->
        case disk_get(config, key) do
          {:ok, content} ->
            _ = memory_put(config, key, content)
            {:ok, content}

          :miss ->
            case cdn_get(config, key) do
              {:ok, content, metadata} ->
                _ = cache_put(config, key, content, metadata)
                {:ok, content}

              {:ok, content} ->
                _ = cache_put(config, key, content)
                {:ok, content}

              :miss ->
                case origin_get_with_metadata(config, key) do
                  {:ok, %{content: content} = metadata} ->
                    _ = cache_put(config, key, content, metadata_without_content(metadata))
                    {:ok, content}

                  {:ok, content} ->
                    _ = cache_put(config, key, content)
                    {:ok, content}

                  error ->
                    error
                end
            end
        end
    end
  end

  def get_with_metadata(key), do: get_with_metadata(key, config())

  def get_with_metadata(key, config) do
    case memory_get_with_metadata(config, key) do
      {:ok, _} = hit ->
        hit

      :miss ->
        case disk_get_with_metadata(config, key) do
          {:ok, _} = hit ->
            hit

          :miss ->
            case cdn_get_with_metadata(config, key) do
              {:ok, %{content: content} = metadata} ->
                _ = cache_put(config, key, content, metadata_without_content(metadata))
                {:ok, metadata}

              :miss ->
                case origin_get_with_metadata(config, key) do
                  {:ok, %{content: content} = metadata} ->
                    _ = cache_put(config, key, content, metadata_without_content(metadata))
                    {:ok, metadata}

                  error ->
                    error
                end
            end
        end
    end
  end

  def delete(key), do: delete(key, config())

  def delete(key, config) do
    with {:ok, _} <- origin_delete(config, key) do
      _ = disk_delete(config, key)
      _ = memory_delete(config, key)
      {:ok, key}
    end
  end

  def list(prefix), do: list(prefix, config())

  def list(prefix, config) do
    origin_list(config, prefix)
  end

  def exists?(key), do: exists?(key, config())

  def exists?(key, config) do
    memory_exists?(config, key) || disk_exists?(config, key) || cdn_exists?(config, key) ||
      origin_exists?(config, key)
  end

  def head(key), do: head(key, config())

  def head(key, config) do
    case memory_head(config, key) do
      {:ok, _} = hit ->
        hit

      :miss ->
        case disk_head(config, key) do
          {:ok, _} = hit ->
            hit

          :miss ->
            case cdn_head(config, key) do
              {:ok, _} = hit ->
                hit

              :miss ->
                origin_head(config, key)
            end
        end
    end
  end

  def put_if_match(key, content, etag), do: put_if_match(key, content, etag, config())

  def put_if_match(key, content, etag, config) do
    with {:ok, _} <- origin_put_if_match(config, key, content, etag) do
      _ = cache_put(config, key, content)
      {:ok, key}
    end
  end

  def put_if_none_match(key, content), do: put_if_none_match(key, content, config())

  def put_if_none_match(key, content, config) do
    with {:ok, _} <- origin_put_if_none_match(config, key, content) do
      _ = cache_put(config, key, content)
      {:ok, key}
    end
  end

  defp config do
    Application.get_env(:micelio, Micelio.Storage, [])
  end

  # Get additional Req options (e.g., plug for testing)
  defp req_options(config) do
    Keyword.get(config, :req_options, [])
  end

  defp cache_put(config, key, content, metadata \\ nil) do
    _ = disk_put(config, key, content, metadata)
    _ = memory_put(config, key, content, metadata)
    :ok
  end

  defp origin_backend(config) do
    case Keyword.get(config, :origin_backend) do
      nil ->
        if Keyword.has_key?(config, :s3_bucket), do: :s3, else: :local

      backend ->
        backend
    end
  end

  defp origin_backend_module(config) do
    case origin_backend(config) do
      :local -> Micelio.Storage.Local
      :s3 -> Micelio.Storage.S3
      module -> module
    end
  end

  defp origin_local_opts(config) do
    case Keyword.get(config, :origin_local_path) do
      path when is_binary(path) -> [base_path: path]
      _ -> []
    end
  end

  defp origin_get_with_metadata(config, key) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.get_with_metadata(key, opts)
    else
      backend.get_with_metadata(key)
    end
  end

  defp origin_put(config, key, content) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.put(key, content, opts)
    else
      backend.put(key, content)
    end
  end

  defp origin_delete(config, key) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.delete(key, opts)
    else
      backend.delete(key)
    end
  end

  defp origin_list(config, prefix) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.list(prefix, opts)
    else
      backend.list(prefix)
    end
  end

  defp origin_exists?(config, key) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.exists?(key, opts)
    else
      backend.exists?(key)
    end
  end

  defp origin_head(config, key) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.head(key, opts)
    else
      backend.head(key)
    end
  end

  defp origin_put_if_match(config, key, content, etag) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.put_if_match(key, content, etag, opts)
    else
      backend.put_if_match(key, content, etag)
    end
  end

  defp origin_put_if_none_match(config, key, content) do
    backend = origin_backend_module(config)
    opts = origin_local_opts(config)

    if backend == Micelio.Storage.Local and opts != [] do
      Micelio.Storage.Local.put_if_none_match(key, content, opts)
    else
      backend.put_if_none_match(key, content)
    end
  end

  defp cache_namespace(config) do
    Keyword.get(config, :cache_namespace, "default")
  end

  defp memory_max_bytes(config) do
    Keyword.get(config, :cache_memory_max_bytes, @default_memory_max_bytes)
  end

  defp memory_enabled?(config) do
    max_bytes = memory_max_bytes(config)
    is_integer(max_bytes) and max_bytes > 0
  end

  defp memory_get(config, key) do
    if memory_enabled?(config) do
      ensure_tables()
      namespace = cache_namespace(config)
      entry_key = {namespace, key}

      case :ets.lookup(@entries_table, entry_key) do
        [{^entry_key, content, size, seq, metadata}] ->
          _ = touch_entry(namespace, key, content, size, seq, metadata)
          {:ok, content}

        [{^entry_key, content, size, seq}] ->
          _ = touch_entry(namespace, key, content, size, seq, nil)
          {:ok, content}

        [] ->
          :miss
      end
    else
      :miss
    end
  end

  defp memory_get_with_metadata(config, key) do
    if memory_enabled?(config) do
      ensure_tables()
      namespace = cache_namespace(config)
      entry_key = {namespace, key}

      case :ets.lookup(@entries_table, entry_key) do
        [{^entry_key, content, size, seq, metadata}] ->
          if metadata_present?(metadata) do
            _ = touch_entry(namespace, key, content, size, seq, metadata)
            {:ok, Map.put(metadata, :content, content)}
          else
            :miss
          end

        [_] ->
          :miss

        [] ->
          :miss
      end
    else
      :miss
    end
  end

  defp memory_head(config, key) do
    case memory_get_with_metadata(config, key) do
      {:ok, metadata} -> {:ok, metadata_without_content(metadata)}
      :miss -> :miss
    end
  end

  defp memory_exists?(config, key) do
    if memory_enabled?(config) do
      ensure_tables()
      :ets.member(@entries_table, {cache_namespace(config), key})
    else
      false
    end
  end

  defp memory_put(config, key, content, metadata \\ nil) do
    if memory_enabled?(config) do
      ensure_tables()
      namespace = cache_namespace(config)
      entry_key = {namespace, key}
      size = byte_size(content)

      existing_size =
        case :ets.lookup(@entries_table, entry_key) do
          [{^entry_key, _content, existing_size, existing_seq, _metadata}] ->
            _ = :ets.delete(@order_table, {namespace, existing_seq})
            existing_size

          [{^entry_key, _content, existing_size, existing_seq}] ->
            _ = :ets.delete(@order_table, {namespace, existing_seq})
            existing_size

          [] ->
            0
        end

      seq = next_seq(namespace)

      :ets.insert(
        @entries_table,
        {entry_key, content, size, seq, normalize_metadata(content, metadata)}
      )

      :ets.insert(@order_table, {{namespace, seq}, key, size})

      _ = update_total_bytes(namespace, size - existing_size)
      evict_if_needed(namespace, memory_max_bytes(config))
    end

    :ok
  end

  defp memory_delete(config, key) do
    if memory_enabled?(config) do
      ensure_tables()
      namespace = cache_namespace(config)
      entry_key = {namespace, key}

      case :ets.lookup(@entries_table, entry_key) do
        [{^entry_key, _content, size, seq, _metadata}] ->
          :ets.delete(@entries_table, entry_key)
          :ets.delete(@order_table, {namespace, seq})
          _ = update_total_bytes(namespace, -size)
          :ok

        [{^entry_key, _content, size, seq}] ->
          :ets.delete(@entries_table, entry_key)
          :ets.delete(@order_table, {namespace, seq})
          _ = update_total_bytes(namespace, -size)
          :ok

        [] ->
          :ok
      end
    else
      :ok
    end
  end

  defp touch_entry(namespace, key, content, size, seq, metadata) do
    new_seq = next_seq(namespace)
    :ets.insert(@entries_table, {{namespace, key}, content, size, new_seq, metadata})
    :ets.delete(@order_table, {namespace, seq})
    :ets.insert(@order_table, {{namespace, new_seq}, key, size})
    :ok
  rescue
    ArgumentError ->
      :ok
  end

  defp total_bytes(namespace) do
    case :ets.lookup(@meta_table, {namespace, :total_bytes}) do
      [{{^namespace, :total_bytes}, total}] -> total
      [] -> 0
    end
  end

  defp update_total_bytes(namespace, delta) do
    :ets.update_counter(
      @meta_table,
      {namespace, :total_bytes},
      {2, delta},
      {{namespace, :total_bytes}, 0}
    )
  end

  defp next_seq(namespace) do
    :ets.update_counter(@meta_table, {namespace, :seq}, {2, 1}, {{namespace, :seq}, 0})
  end

  defp evict_if_needed(_namespace, max_bytes) when not is_integer(max_bytes) or max_bytes <= 0,
    do: :ok

  defp evict_if_needed(namespace, max_bytes) do
    if total_bytes(namespace) > max_bytes do
      case oldest_order_key(namespace) do
        nil ->
          :ok

        {^namespace, seq} ->
          case :ets.lookup(@order_table, {namespace, seq}) do
            [{{^namespace, ^seq}, key, size}] ->
              :ets.delete(@order_table, {namespace, seq})
              :ets.delete(@entries_table, {namespace, key})
              _ = update_total_bytes(namespace, -size)
              evict_if_needed(namespace, max_bytes)

            [] ->
              :ok
          end
      end
    else
      :ok
    end
  end

  defp oldest_order_key(namespace) do
    case :ets.next(@order_table, {namespace, -1}) do
      :"$end_of_table" -> nil
      {^namespace, _seq} = key -> key
      _ -> nil
    end
  end

  defp disk_path(config) do
    case Keyword.get(config, :cache_disk_path, @default_cache_disk_path) do
      path when is_binary(path) -> path
      _ -> nil
    end
  end

  defp disk_enabled?(config) do
    is_binary(disk_path(config))
  end

  defp disk_get(config, key) do
    if disk_enabled?(config) do
      path = Path.join(disk_path(config), key)

      case File.read(path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> :miss
        _ -> :miss
      end
    else
      :miss
    end
  end

  defp disk_get_with_metadata(config, key) do
    if disk_enabled?(config) do
      path = Path.join(disk_path(config), key)
      meta_path = disk_metadata_path(config, key)

      with {:ok, content} <- File.read(path),
           {:ok, meta_binary} <- File.read(meta_path),
           {:ok, metadata} <- decode_metadata(meta_binary),
           true <- metadata_present?(metadata) do
        {:ok, Map.put(metadata, :content, content)}
      else
        _ -> :miss
      end
    else
      :miss
    end
  end

  defp disk_head(config, key) do
    if disk_enabled?(config) do
      meta_path = disk_metadata_path(config, key)

      with {:ok, meta_binary} <- File.read(meta_path),
           {:ok, metadata} <- decode_metadata(meta_binary),
           true <- metadata_present?(metadata) do
        {:ok, metadata_without_content(metadata)}
      else
        _ -> :miss
      end
    else
      :miss
    end
  end

  defp disk_put(config, key, content, metadata) do
    if disk_enabled?(config) do
      path = Path.join(disk_path(config), key)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, content),
           :ok <- maybe_write_metadata(config, key, content, metadata) do
        :ok
      else
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp disk_exists?(config, key) do
    if disk_enabled?(config) do
      path = Path.join(disk_path(config), key)
      File.exists?(path)
    else
      false
    end
  end

  defp disk_delete(config, key) do
    if disk_enabled?(config) do
      path = Path.join(disk_path(config), key)

      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        _ -> :ok
      end

      _ = File.rm(disk_metadata_path(config, key))
    else
      :ok
    end
  end

  defp cdn_head(config, key) do
    case cdn_get_with_metadata(config, key) do
      {:ok, %{content: content} = metadata} ->
        _ = cache_put(config, key, content, metadata_without_content(metadata))
        {:ok, metadata_without_content(metadata)}

      :miss ->
        :miss
    end
  end

  defp cdn_get(config, key) do
    case Keyword.get(config, :cdn_base_url) do
      base_url when is_binary(base_url) ->
        url = String.trim_trailing(base_url, "/") <> "/" <> key

        opts =
          [
            receive_timeout: Keyword.get(config, :cdn_timeout_ms, @default_cdn_timeout_ms),
            decode_body: false
          ]
          |> Keyword.merge(req_options(config))

        case Req.get(url, opts) do
          {:ok, %{status: 200, body: body, headers: headers}} ->
            case header_value(headers, "etag") do
              nil -> {:ok, body}
              etag -> {:ok, body, %{etag: etag}}
            end

          {:ok, %{status: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status: 404}} ->
            :miss

          {:ok, _} ->
            :miss

          {:error, _} ->
            :miss
        end

      _ ->
        :miss
    end
  end

  defp cdn_get_with_metadata(config, key) do
    case Keyword.get(config, :cdn_base_url) do
      base_url when is_binary(base_url) ->
        url = String.trim_trailing(base_url, "/") <> "/" <> key

        opts =
          [
            receive_timeout: Keyword.get(config, :cdn_timeout_ms, @default_cdn_timeout_ms),
            decode_body: false
          ]
          |> Keyword.merge(req_options(config))

        case Req.get(url, opts) do
          {:ok, %{status: 200, body: body, headers: headers}} ->
            case header_value(headers, "etag") do
              nil -> :miss
              etag -> {:ok, %{content: body, etag: etag, size: byte_size(body)}}
            end

          {:ok, %{status: 404}} ->
            :miss

          {:ok, _} ->
            :miss

          {:error, _} ->
            :miss
        end

      _ ->
        :miss
    end
  end

  defp cdn_exists?(config, key) do
    case Keyword.get(config, :cdn_base_url) do
      base_url when is_binary(base_url) ->
        url = String.trim_trailing(base_url, "/") <> "/" <> key

        opts =
          [receive_timeout: Keyword.get(config, :cdn_timeout_ms, @default_cdn_timeout_ms)]
          |> Keyword.merge(req_options(config))

        case Req.head(url, opts) do
          {:ok, %{status: 200}} -> true
          {:ok, %{status: 404}} -> false
          {:ok, _} -> false
          {:error, _} -> false
        end

      _ ->
        false
    end
  end

  defp ensure_tables do
    create_table(@entries_table, :set)
    create_table(@order_table, :ordered_set)
    create_table(@meta_table, :set)
  end

  defp normalize_metadata(content, metadata) do
    metadata_map =
      case metadata do
        %{} = meta -> meta
        _ -> %{}
      end

    Map.put_new(metadata_map, :size, byte_size(content))
  end

  defp metadata_present?(metadata) do
    is_map(metadata) and is_binary(Map.get(metadata, :etag))
  end

  defp metadata_without_content(metadata) do
    case metadata do
      %{} = meta -> Map.delete(meta, :content)
      _ -> %{}
    end
  end

  defp disk_metadata_path(config, key) do
    Path.join(disk_path(config), "#{key}.meta")
  end

  defp maybe_write_metadata(config, key, content, metadata) do
    normalized = normalize_metadata(content, metadata)

    if metadata_present?(normalized) do
      meta_path = disk_metadata_path(config, key)

      with :ok <- File.mkdir_p(Path.dirname(meta_path)),
           :ok <- File.write(meta_path, :erlang.term_to_binary(normalized)) do
        :ok
      else
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp decode_metadata(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %{} = metadata -> {:ok, metadata}
      _ -> {:error, :invalid_metadata}
    end
  rescue
    ArgumentError -> {:error, :invalid_metadata}
  end

  defp header_value(headers, name) do
    target = String.downcase(name)

    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == target, do: normalize_header_value(value)

      _ ->
        nil
    end)
  end

  # Handle header values that may come as lists (from Plug) or strings (from Req)
  defp normalize_header_value([value | _]) when is_binary(value), do: value
  defp normalize_header_value(value) when is_binary(value), do: value
  defp normalize_header_value(_), do: nil

  defp create_table(name, type) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, [
            :named_table,
            :public,
            type,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end
end
