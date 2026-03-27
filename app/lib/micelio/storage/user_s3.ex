defmodule Micelio.Storage.UserS3 do
  @moduledoc """
  User-scoped S3 storage with fallback to instance storage.
  """

  @behaviour Micelio.Storage

  alias Micelio.Repo
  alias Micelio.Storage.S3Config

  require Logger

  @config_table :micelio_storage_user_s3_config_cache
  @failure_table :micelio_storage_user_s3_failure_cache
  @default_cache_ttl_ms 60_000
  @default_failure_ttl_ms 300_000
  @default_failure_threshold 3

  def put(user, key, content) when is_binary(key) do
    operate(user, :put, [key, content], [])
  end

  def put(user, key, content, opts) when is_binary(key) and is_list(opts) do
    operate(user, :put, [key, content], opts)
  end

  def get(user, key) when is_binary(key) do
    operate(user, :get, [key], [])
  end

  def get(user, key, opts) when is_binary(key) and is_list(opts) do
    operate(user, :get, [key], opts)
  end

  def delete(user, key) when is_binary(key) do
    operate(user, :delete, [key], [])
  end

  def delete(user, key, opts) when is_binary(key) and is_list(opts) do
    operate(user, :delete, [key], opts)
  end

  def url(user, key) when is_binary(key) do
    case resolve_backend(user) do
      {:user_s3, config} ->
        build_url(config, apply_path_prefix(config, key))

      {:instance, _reason} ->
        Micelio.Storage.cdn_url(key)
    end
  end

  defp operate(user, operation, args, opts) do
    {key, _} = split_args(args)

    case resolve_backend(user) do
      {:user_s3, %S3Config{} = config} ->
        prefixed_args = replace_key(args, apply_path_prefix(config, key))

        {result, duration_ms} =
          timed(fn ->
            run_user_backend(operation, prefixed_args, config)
          end)

        emit_telemetry(operation, :user_s3, result, duration_ms, user, fallback: false)
        Logger.debug(log_message(operation, :user_s3, user))

        case result do
          {:ok, _} ->
            clear_failures(user)
            result

          {:error, reason} ->
            if should_record_failure?(operation, reason) do
              record_failure(user, config, reason, opts)
            end

            if should_fallback?(operation, result) do
              fallback(operation, args, user, reason, opts)
            else
              result
            end
        end

      {:instance, reason} ->
        fallback(operation, args, user, reason, opts)
    end
  end

  defp fallback(operation, args, user, reason, opts) do
    {result, duration_ms} = timed(fn -> run_instance_backend(operation, args, opts) end)

    emit_telemetry(operation, :instance, result, duration_ms, user, fallback: true)
    log_fallback(operation, user, reason)

    result
  end

  defp run_user_backend(:put, [key, content], %S3Config{} = config) do
    Micelio.Storage.S3.put(key, content, config: s3_runtime_config(config))
  end

  defp run_user_backend(:get, [key], %S3Config{} = config) do
    Micelio.Storage.S3.get(key, config: s3_runtime_config(config))
  end

  defp run_user_backend(:delete, [key], %S3Config{} = config) do
    Micelio.Storage.S3.delete(key, config: s3_runtime_config(config))
  end

  defp run_instance_backend(:put, [key, content], opts) do
    Micelio.Storage.put(key, content, opts)
  end

  defp run_instance_backend(:get, [key], opts) do
    Micelio.Storage.get(key, opts)
  end

  defp run_instance_backend(:delete, [key], opts) do
    Micelio.Storage.delete(key, opts)
  end

  defp resolve_backend(user) do
    case normalize_user_id(user) do
      {:ok, user_id} ->
        case fetch_user_config(user_id) do
          nil ->
            {:instance, :no_config}

          %S3Config{} = config ->
            if config_valid?(config) do
              {:user_s3, config}
            else
              {:instance, :invalid_config}
            end
        end

      :error ->
        {:instance, :no_user}
    end
  end

  defp normalize_user_id(%{id: id}) when is_binary(id), do: {:ok, id}
  defp normalize_user_id(id) when is_binary(id), do: {:ok, id}
  defp normalize_user_id(_), do: :error

  defp fetch_user_config(user_id) when is_binary(user_id) do
    ensure_tables()
    now_ms = System.monotonic_time(:millisecond)

    case cache_fetch(user_id, now_ms) do
      {:ok, config} ->
        config

      :miss ->
        config = Repo.get_by(S3Config, user_id: user_id)
        cache_put(user_id, config, now_ms)
        config
    end
  end

  defp config_valid?(%S3Config{validated_at: %DateTime{}}), do: true
  defp config_valid?(_), do: false

  defp s3_runtime_config(%S3Config{} = config) do
    [
      backend: :s3,
      s3_bucket: config.bucket_name,
      s3_region: config.region || "us-east-1",
      s3_access_key_id: config.access_key_id,
      s3_secret_access_key: config.secret_access_key,
      s3_endpoint: config.endpoint_url,
      s3_url_style: url_style_for(config)
    ]
  end

  defp url_style_for(%S3Config{provider: provider}) when provider in [:aws_s3, :cloudflare_r2],
    do: :virtual

  defp url_style_for(_), do: :path

  defp apply_path_prefix(%S3Config{path_prefix: prefix}, key) when is_binary(key) do
    prefix = prefix || ""
    trimmed = String.trim(prefix, "/")

    if trimmed == "" do
      key
    else
      trimmed <> "/" <> key
    end
  end

  defp build_url(%S3Config{} = config, key) do
    endpoint = config.endpoint_url || "https://s3.#{config.region || "us-east-1"}.amazonaws.com"
    bucket = config.bucket_name
    url_style = url_style_for(config)
    encoded_key = encode_key(key)

    base_uri = endpoint |> String.trim_trailing("/") |> URI.parse()

    uri =
      case url_style do
        :path ->
          bucket_path = "/" <> bucket
          key_path = "/" <> encoded_key
          %{base_uri | path: bucket_path <> key_path}

        :virtual ->
          key_path = "/" <> encoded_key
          %{base_uri | host: "#{bucket}.#{base_uri.host}", path: key_path}
      end

    URI.to_string(uri)
  end

  defp encode_key(key) when is_binary(key) do
    key
    |> String.split("/", trim: false)
    |> Enum.map_join("/", fn segment ->
      URI.encode(segment, fn ch -> URI.char_unreserved?(ch) end)
    end)
  end

  defp should_fallback?(_operation, {:error, _reason}), do: true
  defp should_fallback?(_operation, _), do: false

  defp should_record_failure?(:get, :not_found), do: false
  defp should_record_failure?(_operation, _), do: true

  defp record_failure(user, %S3Config{} = config, reason, opts) do
    user_id = normalize_user_id_value(user)
    message = error_message(reason)

    Logger.warning(
      "storage.user_s3 error=#{message} user_id=#{user_id || "unknown"} provider=#{config.provider}"
    )

    update_last_error(config, message)

    if should_count_failure?(reason) do
      failure_count = bump_failure_count(user_id)
      threshold = failure_threshold(opts)

      if failure_count >= threshold do
        invalidate_config(config, message)
        clear_failures(user_id)
      end
    end
  end

  defp update_last_error(%S3Config{} = config, message) when is_binary(message) do
    changeset = Ecto.Changeset.change(config, %{last_error: message})

    case Repo.update(changeset) do
      {:ok, updated} ->
        refresh_cache(updated)
        :ok

      {:error, _changeset} ->
        :error
    end
  end

  defp invalidate_config(%S3Config{} = config, message) do
    changeset =
      Ecto.Changeset.change(config, %{
        validated_at: nil,
        last_error: message
      })

    case Repo.update(changeset) do
      {:ok, updated} ->
        refresh_cache(updated)
        :ok

      {:error, _changeset} ->
        :error
    end
  end

  defp should_count_failure?({:s3_error, _status, _body}), do: true
  defp should_count_failure?(:missing_s3_bucket), do: true
  defp should_count_failure?(:missing_s3_credentials), do: true
  defp should_count_failure?({:error, _}), do: true
  defp should_count_failure?(:not_found), do: false
  defp should_count_failure?(_), do: true

  defp error_message({:s3_error, status, body}) do
    "S3 error #{status}: #{truncate_reason(body)}"
  end

  defp error_message(:missing_s3_bucket), do: "Missing S3 bucket."
  defp error_message(:missing_s3_credentials), do: "Missing S3 credentials."
  defp error_message(reason), do: truncate_reason(inspect(reason))

  defp truncate_reason(reason) when is_binary(reason) do
    String.slice(reason, 0, 500)
  end

  defp normalize_user_id_value(%{id: id}) when is_binary(id), do: id
  defp normalize_user_id_value(id) when is_binary(id), do: id
  defp normalize_user_id_value(_), do: nil

  defp split_args([key, content]), do: {key, content}
  defp split_args([key]), do: {key, nil}

  defp replace_key([_key, content], new_key), do: [new_key, content]
  defp replace_key([_key], new_key), do: [new_key]

  defp timed(fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    {result, duration_ms}
  end

  defp emit_telemetry(operation, backend, result, duration_ms, user, opts) do
    status =
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :error
        _ -> :ok
      end

    metadata =
      %{
        operation: operation,
        backend: backend,
        status: status,
        user_id: normalize_user_id_value(user),
        fallback: Keyword.get(opts, :fallback, false)
      }

    :telemetry.execute([:micelio, :storage, :operation], %{duration_ms: duration_ms}, metadata)
  end

  defp log_message(operation, backend, user) do
    "storage.user_s3 operation=#{operation} backend=#{backend} user_id=#{normalize_user_id_value(user) || "unknown"}"
  end

  defp log_fallback(operation, user, reason) do
    message = log_fallback_message(operation, user, reason)

    case reason do
      :no_config -> Logger.debug(message)
      :no_user -> Logger.debug(message)
      _ -> Logger.warning(message)
    end
  end

  defp log_fallback_message(operation, user, reason) do
    "storage.user_s3 fallback operation=#{operation} user_id=#{normalize_user_id_value(user) || "unknown"} reason=#{inspect(reason)}"
  end

  defp ensure_tables do
    _ = ensure_table(@config_table)
    _ = ensure_table(@failure_table)
    :ok
  end

  defp ensure_table(name) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp cache_fetch(user_id, now_ms) do
    case :ets.lookup(@config_table, user_id) do
      [{^user_id, expires_at_ms, config}] when expires_at_ms > now_ms ->
        {:ok, config}

      [{^user_id, _expires_at_ms, _config}] ->
        :ets.delete(@config_table, user_id)
        :miss

      _ ->
        :miss
    end
  end

  defp cache_put(user_id, config, now_ms) do
    ttl_ms = cache_ttl_ms([])
    :ets.insert(@config_table, {user_id, now_ms + ttl_ms, config})
    :ok
  end

  defp refresh_cache(%S3Config{} = config) do
    user_id = config.user_id
    now_ms = System.monotonic_time(:millisecond)
    cache_put(user_id, config, now_ms)
  end

  defp bump_failure_count(nil), do: 0

  defp bump_failure_count(user_id) when is_binary(user_id) do
    ensure_tables()
    now_ms = System.monotonic_time(:millisecond)
    ttl_ms = failure_ttl_ms([])

    count =
      case :ets.lookup(@failure_table, user_id) do
        [{^user_id, expires_at_ms, count}] when expires_at_ms > now_ms ->
          count + 1

        _ ->
          1
      end

    :ets.insert(@failure_table, {user_id, now_ms + ttl_ms, count})
    count
  end

  defp clear_failures(nil), do: :ok

  defp clear_failures(user) do
    user_id = normalize_user_id_value(user)

    if is_binary(user_id) do
      :ets.delete(@failure_table, user_id)
    end

    :ok
  end

  defp cache_ttl_ms(opts) do
    opts
    |> Keyword.get(:cache_ttl_ms, default_cache_ttl_ms())
  end

  defp failure_ttl_ms(opts) do
    opts
    |> Keyword.get(:failure_ttl_ms, default_failure_ttl_ms())
  end

  defp failure_threshold(opts) do
    opts
    |> Keyword.get(:failure_threshold, default_failure_threshold())
  end

  defp default_cache_ttl_ms do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:cache_ttl_ms, @default_cache_ttl_ms)
  end

  defp default_failure_ttl_ms do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:failure_ttl_ms, @default_failure_ttl_ms)
  end

  defp default_failure_threshold do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:failure_threshold, @default_failure_threshold)
  end
end
