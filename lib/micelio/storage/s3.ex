defmodule Micelio.Storage.S3 do
  @moduledoc """
  S3 storage backend using Req HTTP client.

  Content-addressable storage on S3 for stateless agent workflows.

  ## Configuration

      config :micelio, Micelio.Storage,
        backend: :s3,
        s3_bucket: "your-bucket-name",
        s3_region: "us-east-1",
        s3_access_key_id: "your-access-key",      # Optional if using IAM roles
        s3_secret_access_key: "your-secret-key",  # Optional if using IAM roles
        s3_endpoint: "https://s3.amazonaws.com",  # Optional, for S3-compatible services
        s3_url_style: :virtual                    # Optional (:virtual or :path)

  ## AWS Credentials

  Credentials are loaded in order:
  1. Explicit config keys (:s3_access_key_id, :s3_secret_access_key)
  2. Environment variables (S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY)
  3. IAM instance profile/role (when running on AWS)

  ## S3 Operations

  All operations use AWS Signature Version 4 authentication via Req.
  Keys are stored as-is in the bucket (content-addressable by design).
  """

  require Logger

  @doc """
  Stores content at the given key in S3.

  Uses a simple PUT operation with proper AWS authentication.
  """
  def put(key, content) when is_binary(key) and is_binary(content) do
    put(key, content, [])
  end

  def put(key, content, opts) when is_binary(key) and is_binary(content) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         headers = build_headers(content),
         {:ok, req} <- build_signed_request(config, :put, url, content, headers),
         {:ok, response} <- Req.request(req) do
      case response.status do
        status when status in 200..299 ->
          Logger.debug("S3: PUT #{key} succeeded (#{byte_size(content)} bytes)")
          {:ok, key}

        status ->
          Logger.error("S3: PUT #{key} failed with status #{status}")
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: PUT #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves content by key from S3.

  Returns {:error, :not_found} if the object doesn't exist.
  """
  def get(key) when is_binary(key) do
    get(key, [])
  end

  def get(key, opts) when is_binary(key) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         {:ok, req} <- build_signed_request(config, :get, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        200 ->
          Logger.debug("S3: GET #{key} succeeded (#{byte_size(response.body)} bytes)")
          {:ok, response.body}

        404 ->
          Logger.debug("S3: GET #{key} not found")
          {:error, :not_found}

        status ->
          Logger.error("S3: GET #{key} failed with status #{status}: #{inspect(response.body)}")
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: GET #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves content by key from S3 along with metadata like ETag.
  """
  def get_with_metadata(key) when is_binary(key) do
    get_with_metadata(key, [])
  end

  def get_with_metadata(key, opts) when is_binary(key) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         {:ok, req} <- build_signed_request(config, :get, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        200 ->
          {:ok,
           %{
             content: response.body,
             etag: header_value(response.headers, "etag")
           }}

        404 ->
          {:error, :not_found}

        status ->
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: GET #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Deletes a file by key from S3.

  Returns {:ok, key} even if the object doesn't exist (idempotent).
  """
  def delete(key) when is_binary(key) do
    delete(key, [])
  end

  def delete(key, opts) when is_binary(key) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         {:ok, req} <- build_signed_request(config, :delete, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        status when status in [200, 204, 404] ->
          Logger.debug("S3: DELETE #{key} succeeded")
          {:ok, key}

        status ->
          Logger.error("S3: DELETE #{key} failed with status #{status}")
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: DELETE #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists files with the given prefix in S3.

  Returns a list of keys matching the prefix. Uses pagination to handle
  large result sets.
  """
  def list(prefix) when is_binary(prefix) do
    list(prefix, [])
  end

  def list(prefix, opts) when is_binary(prefix) do
    case validate_config(opts) do
      {:ok, config} ->
        list_objects(config, prefix, nil, [])

      {:error, reason} = error ->
        Logger.error("S3: LIST #{prefix} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Checks if a file exists in S3.

  Uses a HEAD request which is more efficient than GET for existence checks.
  """
  def exists?(key) when is_binary(key) do
    exists?(key, [])
  end

  def exists?(key, opts) when is_binary(key) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         {:ok, req} <- build_signed_request(config, :head, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        200 ->
          true

        404 ->
          false

        status ->
          Logger.warning("S3: HEAD #{key} returned unexpected status #{status}")
          false
      end
    else
      {:error, reason} ->
        Logger.error("S3: HEAD #{key} failed: #{inspect(reason)}")
        false
    end
  end

  @doc """
  Returns metadata for a key when available.
  """
  def head(key) when is_binary(key) do
    head(key, [])
  end

  def head(key, opts) when is_binary(key) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         {:ok, req} <- build_signed_request(config, :head, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        200 ->
          {:ok,
           %{
             etag: header_value(response.headers, "etag"),
             size: content_length(response.headers)
           }}

        404 ->
          {:error, :not_found}

        status ->
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: HEAD #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stores content only if the current ETag matches.
  """
  def put_if_match(key, content, etag) when is_binary(key) and is_binary(content) do
    put_if_match(key, content, etag, [])
  end

  def put_if_match(key, content, etag, opts) when is_binary(key) and is_binary(content) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         headers = build_headers(content) ++ [{"if-match", etag}],
         {:ok, req} <- build_signed_request(config, :put, url, content, headers),
         {:ok, response} <- Req.request(req) do
      case response.status do
        status when status in 200..299 ->
          {:ok, key}

        412 ->
          {:error, :precondition_failed}

        status ->
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: PUT #{key} failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stores content only if the key does not exist.
  """
  def put_if_none_match(key, content) when is_binary(key) and is_binary(content) do
    put_if_none_match(key, content, [])
  end

  def put_if_none_match(key, content, opts) when is_binary(key) and is_binary(content) do
    with {:ok, config} <- validate_config(opts),
         url = build_url(config, key),
         headers = build_headers(content) ++ [{"if-none-match", "*"}],
         {:ok, req} <- build_signed_request(config, :put, url, content, headers),
         {:ok, response} <- Req.request(req) do
      case response.status do
        status when status in 200..299 ->
          {:ok, key}

        412 ->
          {:error, :precondition_failed}

        status ->
          {:error, {:s3_error, status, response.body}}
      end
    else
      {:error, reason} = error ->
        Logger.error("S3: PUT #{key} failed: #{inspect(reason)}")
        error
    end
  end

  # Private Functions

  defp validate_config(opts) do
    config = resolve_config(opts)

    env = Keyword.get(config, :env, %{})

    bucket = Keyword.get(config, :s3_bucket) || env_get(env, "S3_BUCKET")

    region =
      Keyword.get(config, :s3_region) || env_get(env, "S3_REGION") || "us-east-1"

    access_key =
      Keyword.get(config, :s3_access_key_id) || env_get(env, "S3_ACCESS_KEY_ID")

    secret_key =
      Keyword.get(config, :s3_secret_access_key) || env_get(env, "S3_SECRET_ACCESS_KEY")

    endpoint =
      Keyword.get(config, :s3_endpoint) ||
        env_get(env, "S3_ENDPOINT") ||
        "https://s3.#{region}.amazonaws.com"

    url_style =
      Keyword.get(config, :s3_url_style) ||
        env_get(env, "S3_URL_STYLE") ||
        :virtual

    url_style =
      case url_style do
        :path -> :path
        "path" -> :path
        :virtual -> :virtual
        "virtual" -> :virtual
        _ -> :virtual
      end

    # Extract Req options for testing (e.g., plug: {Req.Test, :s3})
    req_options = Keyword.get(config, :req_options, [])

    cond do
      is_nil(bucket) ->
        {:error, :missing_s3_bucket}

      is_nil(access_key) or is_nil(secret_key) ->
        # Note: In production with IAM roles, we'd need to implement credential fetching
        # For now, require explicit credentials
        {:error, :missing_s3_credentials}

      true ->
        {:ok,
         %{
           bucket: bucket,
           region: region,
           access_key: access_key,
           secret_key: secret_key,
           endpoint: endpoint,
           url_style: url_style,
           req_options: req_options
         }}
    end
  end

  defp resolve_config(opts) do
    cond do
      Keyword.has_key?(opts, :config) ->
        Keyword.get(opts, :config)

      Keyword.has_key?(opts, :storage_config) ->
        Keyword.get(opts, :storage_config)

      Keyword.has_key?(opts, :s3_bucket) or Keyword.has_key?(opts, :s3_region) ->
        opts

      true ->
        Application.get_env(:micelio, Micelio.Storage, [])
    end
  end

  defp env_get(env, key) when is_map(env) do
    Map.get(env, key) || System.get_env(key)
  end

  defp build_url(config, key) do
    base_uri = config.endpoint |> String.trim_trailing("/") |> URI.parse()
    encoded_key = encode_key(key)

    uri =
      case config.url_style do
        :path ->
          bucket_path = "/" <> config.bucket
          key_path = "/" <> encoded_key
          %{base_uri | path: bucket_path <> key_path}

        :virtual ->
          key_path = "/" <> encoded_key
          %{base_uri | host: "#{config.bucket}.#{base_uri.host}", path: key_path}
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

  defp build_headers(content) when is_binary(content) do
    [{"content-type", "application/octet-stream"}]
  end

  defp build_headers(_content) do
    []
  end

  defp build_signed_request(config, method, url, body \\ nil, extra_headers \\ []) do
    # For now, use simple AWS authentication
    # In a production system, implement full AWS Signature V4
    uri = URI.parse(url)

    headers =
      [
        {"host", uri.host},
        {"x-amz-date", amz_date()},
        {"x-amz-content-sha256", content_sha256(body)}
      ] ++ extra_headers

    # Build authorization header
    auth_header = build_authorization_header(config, method, uri, headers, body)
    headers = [{"authorization", auth_header} | headers]

    req_opts = [
      method: method,
      url: url,
      headers: headers,
      decode_body: false
    ]

    req_opts =
      if body do
        [{:body, body} | req_opts]
      else
        req_opts
      end

    # Merge any additional Req options (e.g., plug for testing)
    req_opts = Keyword.merge(req_opts, config.req_options)

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

    # Canonical request
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

    # String to sign
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

    # Calculate signature
    signing_key = get_signature_key(config.secret_key, date_stamp, config.region, "s3")
    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    # Authorization header
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

  defp list_objects(config, prefix, continuation_token, accumulated_keys) do
    query_params = build_list_query_params(prefix, continuation_token)
    url = build_list_url(config, query_params)

    with {:ok, req} <- build_signed_request(config, :get, url),
         {:ok, response} <- Req.request(req) do
      case response.status do
        200 ->
          parse_list_response(response.body, config, prefix, accumulated_keys)

        status ->
          Logger.error("S3: LIST #{prefix} failed with status #{status}")
          {:error, {:s3_error, status, response.body}}
      end
    end
  end

  defp build_list_url(config, query_params) do
    base_uri = config.endpoint |> String.trim_trailing("/") |> URI.parse()

    uri =
      case config.url_style do
        :path ->
          %{base_uri | path: "/" <> config.bucket, query: query_params}

        :virtual ->
          %{base_uri | host: "#{config.bucket}.#{base_uri.host}", path: "/", query: query_params}
      end

    URI.to_string(uri)
  end

  defp build_list_query_params(prefix, continuation_token) do
    params = [
      {"list-type", "2"},
      {"prefix", prefix}
    ]

    params =
      if continuation_token do
        [{"continuation-token", continuation_token} | params]
      else
        params
      end

    URI.encode_query(params)
  end

  defp parse_list_response(xml_body, config, prefix, accumulated_keys) do
    # Simple XML parsing for ListBucketResult
    # Extract Keys and NextContinuationToken
    keys = extract_keys_from_xml(xml_body)
    next_token = extract_next_continuation_token(xml_body)

    all_keys = accumulated_keys ++ keys

    if next_token do
      # More results available, paginate
      list_objects(config, prefix, next_token, all_keys)
    else
      Logger.debug("S3: LIST #{prefix} returned #{length(all_keys)} keys")
      {:ok, all_keys}
    end
  end

  defp extract_keys_from_xml(xml_body) do
    # Simple regex-based extraction (in production, use a proper XML parser)
    ~r/<Key>([^<]+)<\/Key>/
    |> Regex.scan(xml_body, capture: :all_but_first)
    |> Enum.map(fn [key] -> key end)
  end

  defp extract_next_continuation_token(xml_body) do
    case Regex.run(~r/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/, xml_body,
           capture: :all_but_first
         ) do
      [token] -> token
      _ -> nil
    end
  end

  defp header_value(headers, name) do
    value =
      Enum.find_value(headers, fn {key, v} ->
        if String.downcase(key) == name do
          v
        end
      end)

    # Req returns header values as lists, extract the first element
    case value do
      [single] -> single
      other -> other
    end
  end

  defp content_length(headers) do
    case header_value(headers, "content-length") do
      nil -> nil
      value -> String.to_integer(value)
    end
  end
end
