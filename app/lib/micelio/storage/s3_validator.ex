defmodule Micelio.Storage.S3Validator do
  @moduledoc """
  Validates user-provided S3 credentials and bucket access.
  """

  alias Micelio.Storage.S3Config

  @cache_table :micelio_s3_validator_cache
  @default_cache_ttl_ms 300_000
  @default_error_cache_ttl_ms 30_000
  @default_timeout_ms 5_000
  @default_retry_attempts 2
  @default_retry_backoff_ms 200
  @validation_payload "micelio-storage-validation"

  def validate(%S3Config{} = config, opts \\ []) do
    ensure_cache_table()

    cache_key = cache_key(config)
    now_ms = System.monotonic_time(:millisecond)

    case cache_fetch(cache_key, now_ms) do
      {:ok, result} ->
        {:ok, result}

      :miss ->
        result = do_validate(config, opts)
        cache_put(cache_key, result, now_ms, opts)

        if result.ok? do
          {:ok, result}
        else
          {:error, result}
        end
    end
  end

  defp do_validate(%S3Config{} = config, opts) do
    result = new_result()

    with {:ok, normalized} <- normalize_config(config),
         {:ok, result} <- step_ok(result, :endpoint, validate_endpoint(normalized.endpoint)),
         {:ok, result} <- step_ok(result, :bucket, head_bucket(normalized, opts)),
         {:ok, result} <- step_ok(result, :write, put_object(normalized, opts)),
         {:ok, result} <- step_ok(result, :read, get_object(normalized, opts)),
         {:ok, result} <- step_ok(result, :delete, delete_object(normalized, opts)) do
      result
      |> maybe_check_public_bucket(normalized, opts)
      |> finalize_result()
    else
      {:error, step, message, result} ->
        result
        |> mark_step(step, {:error, message})
        |> add_error(message)
        |> finalize_result()

      {:error, step, message} ->
        result
        |> mark_step(step, {:error, message})
        |> add_error(message)
        |> finalize_result()
    end
  end

  defp normalize_config(%S3Config{} = config) do
    bucket = config.bucket_name
    access_key = config.access_key_id
    secret_key = config.secret_access_key
    region = config.region || "us-east-1"
    provider = config.provider
    url_style = url_style_for(provider)

    endpoint =
      config.endpoint_url ||
        default_endpoint(provider, region)

    cond do
      is_nil(bucket) or bucket == "" ->
        {:error, :config, "Bucket name is required for validation."}

      not is_binary(access_key) or not is_binary(secret_key) ->
        {:error, :config, "Access key ID and secret access key are required."}

      is_nil(endpoint) or endpoint == "" ->
        {:error, :config, "Endpoint URL is required for this provider."}

      provider == :cloudflare_r2 and config.region in [nil, ""] ->
        {:ok,
         %{
           bucket: bucket,
           region: "auto",
           access_key: access_key,
           secret_key: secret_key,
           endpoint: endpoint,
           url_style: url_style,
           provider: provider,
           path_prefix: config.path_prefix
         }}

      true ->
        {:ok,
         %{
           bucket: bucket,
           region: region,
           access_key: access_key,
           secret_key: secret_key,
           endpoint: endpoint,
           url_style: url_style,
           provider: provider,
           path_prefix: config.path_prefix
         }}
    end
  end

  defp validate_endpoint(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _ ->
        {:error, :endpoint, "Endpoint URL must include http(s) scheme and host."}
    end
  end

  defp step_ok(result, step, action_result) do
    case action_result do
      :ok ->
        {:ok, mark_step(result, step, :ok)}

      {:ok, _} ->
        {:ok, mark_step(result, step, :ok)}

      {:error, step_override, message} ->
        {:error, step_override, message, result}
    end
  end

  defp head_bucket(config, opts) do
    url = build_bucket_url(config)

    case request(config, :head, url, nil, [], opts) do
      {:ok, response} ->
        case response.status do
          200 ->
            {:ok, response}

          301 ->
            {:error, :bucket, "Bucket exists but region/endpoint mismatch (301 redirect)."}

          403 ->
            {:error, :bucket, "Access denied when checking bucket."}

          404 ->
            {:error, :bucket, "Bucket not found."}

          status ->
            {:error, :bucket, "Bucket check failed with status #{status}."}
        end

      {:error, reason} ->
        {:error, :bucket, "Bucket check failed: #{inspect(reason)}"}
    end
  end

  defp put_object(config, opts) do
    key = test_key(config)
    url = build_object_url(config, key)

    case request(config, :put, url, @validation_payload, [], opts) do
      {:ok, response} ->
        case response.status do
          status when status in 200..299 ->
            {:ok, response}

          403 ->
            {:error, :write, "Access denied when writing test object."}

          status ->
            {:error, :write, "Write test failed with status #{status}."}
        end

      {:error, reason} ->
        {:error, :write, "Write test failed: #{inspect(reason)}"}
    end
  end

  defp get_object(config, opts) do
    key = test_key(config)
    url = build_object_url(config, key)

    case request(config, :get, url, nil, [], opts) do
      {:ok, response} ->
        case response.status do
          200 ->
            if response.body == @validation_payload do
              {:ok, response}
            else
              {:error, :read, "Read test returned unexpected content."}
            end

          403 ->
            {:error, :read, "Access denied when reading test object."}

          404 ->
            {:error, :read, "Test object not found when reading."}

          status ->
            {:error, :read, "Read test failed with status #{status}."}
        end

      {:error, reason} ->
        {:error, :read, "Read test failed: #{inspect(reason)}"}
    end
  end

  defp delete_object(config, opts) do
    key = test_key(config)
    url = build_object_url(config, key)

    case request(config, :delete, url, nil, [], opts) do
      {:ok, response} ->
        case response.status do
          status when status in [200, 204] ->
            {:ok, response}

          403 ->
            {:error, :delete, "Access denied when deleting test object."}

          status ->
            {:error, :delete, "Delete test failed with status #{status}."}
        end

      {:error, reason} ->
        {:error, :delete, "Delete test failed: #{inspect(reason)}"}
    end
  end

  defp maybe_check_public_bucket(result, config, opts) do
    if Keyword.get(opts, :check_public, false) do
      case bucket_acl_check(config, opts) do
        :ok ->
          mark_step(result, :public_access, :ok)

        {:warning, message} ->
          result
          |> mark_step(:public_access, :warning)
          |> add_warning(message)
      end
    else
      result
    end
  end

  defp bucket_acl_check(%{provider: provider} = config, opts) do
    if provider in [:minio, :custom] do
      {:warning, "Bucket ACL check skipped for this provider."}
    else
      url = build_bucket_acl_url(config)

      case request(config, :get, url, nil, [], opts) do
        {:ok, response} ->
          case response.status do
            200 ->
              if bucket_acl_public?(response.body) do
                {:warning, "Bucket ACL appears to allow public access."}
              else
                :ok
              end

            403 ->
              {:warning, "Bucket ACL check denied; verify bucket privacy manually."}

            status ->
              {:warning, "Bucket ACL check returned status #{status}."}
          end

        {:error, reason} ->
          {:warning, "Bucket ACL check failed: #{inspect(reason)}"}
      end
    end
  end

  defp bucket_acl_public?(xml_body) when is_binary(xml_body) do
    String.contains?(xml_body, "AllUsers") or String.contains?(xml_body, "AuthenticatedUsers")
  end

  defp request(config, method, url, body, headers, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    retries = Keyword.get(opts, :retry_attempts, @default_retry_attempts)
    backoff_ms = Keyword.get(opts, :retry_backoff_ms, @default_retry_backoff_ms)

    do_request(config, method, url, body, headers, timeout_ms, retries + 1, backoff_ms)
  end

  defp do_request(_config, _method, _url, _body, _headers, _timeout_ms, 0, _backoff_ms),
    do: {:error, :no_more_attempts}

  defp do_request(config, method, url, body, headers, timeout_ms, attempts_left, backoff_ms) do
    extra_headers = build_headers(body) ++ headers

    with {:ok, req} <- build_signed_request(config, method, url, body, extra_headers) do
      req =
        Keyword.merge(req,
          connect_options: [timeout: timeout_ms],
          receive_timeout: timeout_ms
        )

      case Req.request(req) do
        {:ok, response} ->
          if retryable_status?(response.status) and attempts_left > 1 do
            Process.sleep(backoff_ms)

            do_request(
              config,
              method,
              url,
              body,
              headers,
              timeout_ms,
              attempts_left - 1,
              backoff_ms
            )
          else
            {:ok, response}
          end

        {:error, reason} ->
          if attempts_left > 1 do
            Process.sleep(backoff_ms)

            do_request(
              config,
              method,
              url,
              body,
              headers,
              timeout_ms,
              attempts_left - 1,
              backoff_ms
            )
          else
            {:error, reason}
          end
      end
    end
  end

  defp retryable_status?(status) when is_integer(status), do: status in 500..599
  defp retryable_status?(_status), do: false

  defp build_headers(content) when is_binary(content) do
    [{"content-type", "application/octet-stream"}]
  end

  defp build_headers(_content), do: []

  defp build_bucket_url(config) do
    build_url(config, nil)
  end

  defp build_bucket_acl_url(config) do
    bucket_uri = build_url(config, nil) |> URI.parse()
    %{bucket_uri | query: "acl"} |> URI.to_string()
  end

  defp build_object_url(config, key) do
    build_url(config, key)
  end

  defp build_url(config, key) do
    base_uri = config.endpoint |> String.trim_trailing("/") |> URI.parse()
    key_path = if is_binary(key), do: encode_key(key)

    {host, path} =
      case config.url_style do
        :path ->
          path_segments =
            [base_uri.path, config.bucket, key_path]
            |> Enum.reject(&(&1 in [nil, ""]))

          {base_uri.host, join_paths(path_segments)}

        :virtual ->
          path_segments =
            [base_uri.path, key_path]
            |> Enum.reject(&(&1 in [nil, ""]))

          {"#{config.bucket}.#{base_uri.host}", join_paths(path_segments)}
      end

    base_uri
    |> Map.put(:host, host)
    |> Map.put(:path, path)
    |> URI.to_string()
  end

  defp join_paths([]), do: "/"

  defp join_paths(segments) do
    "/" <>
      (segments
       |> Enum.map(&String.trim(&1, "/"))
       |> Enum.reject(&(&1 == ""))
       |> Enum.join("/"))
  end

  defp encode_key(key) when is_binary(key) do
    key
    |> String.split("/", trim: false)
    |> Enum.map_join("/", fn segment ->
      URI.encode(segment, fn ch -> URI.char_unreserved?(ch) end)
    end)
  end

  defp test_key(config) do
    prefix = config.path_prefix

    [prefix, ".micelio-test"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> join_path_segments()
  end

  defp join_path_segments(segments) do
    segments
    |> Enum.map(&String.trim(&1, "/"))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("/")
  end

  defp url_style_for(provider) do
    case provider do
      :minio -> :path
      :custom -> :path
      _ -> :virtual
    end
  end

  defp default_endpoint(:aws_s3, region), do: "https://s3.#{region}.amazonaws.com"
  defp default_endpoint(:backblaze_b2, region), do: "https://s3.#{region}.backblazeb2.com"
  defp default_endpoint(_, _region), do: nil

  defp new_result do
    %{
      ok?: false,
      errors: [],
      warnings: [],
      steps: %{}
    }
  end

  defp mark_step(result, step, status) do
    put_in(result, [:steps, step], status)
  end

  defp add_error(result, message) do
    update_in(result.errors, &[message | &1])
  end

  defp add_warning(result, message) do
    update_in(result.warnings, &[message | &1])
  end

  defp finalize_result(result) do
    errors = Enum.reverse(result.errors)
    warnings = Enum.reverse(result.warnings)

    result
    |> Map.put(:errors, errors)
    |> Map.put(:warnings, warnings)
    |> Map.put(:ok?, errors == [])
  end

  defp cache_key(config) do
    credential_hash =
      :crypto.hash(
        :sha256,
        "#{config.access_key_id}:#{config.secret_access_key}"
      )
      |> Base.encode16(case: :lower)

    {
      config.provider,
      config.bucket_name,
      config.region,
      config.endpoint_url,
      config.path_prefix,
      credential_hash
    }
  end

  defp ensure_cache_table do
    case :ets.info(@cache_table) do
      :undefined ->
        _ =
          :ets.new(@cache_table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true
          ])

        :ok

      _ ->
        :ok
    end
  end

  defp cache_fetch(key, now_ms) do
    case :ets.lookup(@cache_table, key) do
      [{^key, expires_at_ms, result}] when expires_at_ms > now_ms ->
        {:ok, result}

      [{^key, _expires_at_ms, _result}] ->
        :ets.delete(@cache_table, key)
        :miss

      _ ->
        :miss
    end
  end

  defp cache_put(key, result, now_ms, opts) do
    ttl_ms =
      if result.ok? do
        Keyword.get(opts, :cache_ttl_ms, @default_cache_ttl_ms)
      else
        Keyword.get(opts, :error_cache_ttl_ms, @default_error_cache_ttl_ms)
      end

    :ets.insert(@cache_table, {key, now_ms + ttl_ms, result})
    :ok
  end

  defp build_signed_request(config, method, url, body, extra_headers) do
    uri = URI.parse(url)

    headers =
      [
        {"host", uri.host},
        {"x-amz-date", amz_date()},
        {"x-amz-content-sha256", content_sha256(body)}
      ] ++ extra_headers

    auth_header = build_authorization_header(config, method, uri, headers, body)
    headers = [{"authorization", auth_header} | headers]

    req_opts = [
      method: method,
      url: url,
      headers: headers
    ]

    req_opts =
      if body do
        [{:body, body} | req_opts]
      else
        req_opts
      end

    {:ok, req_opts}
  end

  defp amz_date do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp content_sha256(nil), do: sha256("")
  defp content_sha256(body), do: sha256(body)

  defp sha256(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp build_authorization_header(config, method, uri, headers, body) do
    date = DateTime.utc_now()
    date_stamp = Calendar.strftime(date, "%Y%m%d")
    amz_date = Calendar.strftime(date, "%Y%m%dT%H%M%SZ")

    canonical_uri = uri.path || "/"
    canonical_querystring = uri.query || ""
    canonical_headers = build_canonical_headers(headers)
    signed_headers = build_signed_headers(headers)
    payload_hash = content_sha256(body)

    method_str = method |> Atom.to_string() |> String.upcase()

    canonical_request =
      [
        method_str,
        canonical_uri,
        canonical_querystring,
        canonical_headers,
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    credential_scope = "#{date_stamp}/#{config.region}/s3/aws4_request"
    algorithm = "AWS4-HMAC-SHA256"

    string_to_sign =
      [
        algorithm,
        amz_date,
        credential_scope,
        sha256(canonical_request)
      ]
      |> Enum.join("\n")

    signing_key = get_signature_key(config.secret_key, date_stamp, config.region, "s3")
    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    "#{algorithm} Credential=#{config.access_key}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
  end

  defp build_canonical_headers(headers) do
    headers
    |> Enum.map(fn {k, v} ->
      {String.downcase(k), String.trim(v)}
    end)
    |> Enum.sort()
    |> Enum.map_join("\n", fn {k, v} -> "#{k}:#{v}" end)
    |> Kernel.<>("\n")
  end

  defp build_signed_headers(headers) do
    headers
    |> Enum.map(fn {k, _v} -> String.downcase(k) end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  defp get_signature_key(secret_key, date_stamp, region, service) do
    k_date = hmac_sha256("AWS4" <> secret_key, date_stamp)
    k_region = hmac_sha256(k_date, region)
    k_service = hmac_sha256(k_region, service)
    hmac_sha256(k_service, "aws4_request")
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end
end
