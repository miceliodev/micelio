import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# Enable the HTTP server. Set MICELIO_SERVER=true to start serving requests.
if (System.get_env("MICELIO_SERVER") || System.get_env("PHX_SERVER")) == "true" do
  config :micelio, MicelioWeb.Endpoint, server: true
end

external_sentry_enabled =
  (System.get_env("MICELIO_ENABLE_EXTERNAL_SENTRY") || System.get_env("ENABLE_EXTERNAL_SENTRY") ||
     "false") == "true"

retention_days =
  case System.get_env("MICELIO_ERROR_RETENTION_DAYS") || System.get_env("ERROR_RETENTION_DAYS") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:retention_days, 90)

    value ->
      case Integer.parse(value) do
        {days, _} -> days
        :error -> 90
      end
  end

resolved_retention_days =
  case System.get_env("MICELIO_ERROR_RESOLVED_RETENTION_DAYS") ||
         System.get_env("ERROR_RESOLVED_RETENTION_DAYS") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:resolved_retention_days, 30)

    value ->
      case Integer.parse(value) do
        {days, _} -> days
        :error -> 30
      end
  end

unresolved_retention_days =
  case System.get_env("MICELIO_ERROR_UNRESOLVED_RETENTION_DAYS") ||
         System.get_env("ERROR_UNRESOLVED_RETENTION_DAYS") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:unresolved_retention_days, 90)

    value ->
      case Integer.parse(value) do
        {days, _} -> days
        :error -> 90
      end
  end

capture_enabled =
  case System.get_env("MICELIO_ERROR_CAPTURE_ENABLED") || System.get_env("ERROR_CAPTURE_ENABLED") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:capture_enabled, true)

    value ->
      value == "true"
  end

retention_archive_enabled =
  case System.get_env("MICELIO_ERROR_RETENTION_ARCHIVE_ENABLED") ||
         System.get_env("ERROR_RETENTION_ARCHIVE_ENABLED") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:retention_archive_enabled, false)

    value ->
      value == "true"
  end

retention_archive_prefix =
  System.get_env("MICELIO_ERROR_RETENTION_ARCHIVE_PREFIX") ||
    System.get_env("ERROR_RETENTION_ARCHIVE_PREFIX") ||
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_archive_prefix, "errors/archives")

retention_vacuum_enabled =
  case System.get_env("MICELIO_ERROR_RETENTION_VACUUM_ENABLED") ||
         System.get_env("ERROR_RETENTION_VACUUM_ENABLED") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:retention_vacuum_enabled, true)

    value ->
      value == "true"
  end

retention_table_warn_threshold =
  case System.get_env("MICELIO_ERROR_RETENTION_TABLE_WARN_THRESHOLD") ||
         System.get_env("ERROR_RETENTION_TABLE_WARN_THRESHOLD") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:retention_table_warn_threshold, 100_000)

    value ->
      case Integer.parse(value) do
        {count, _} -> count
        :error -> 100_000
      end
  end

dedupe_window_seconds =
  case System.get_env("MICELIO_ERROR_DEDUPE_WINDOW_SECONDS") ||
         System.get_env("ERROR_DEDUPE_WINDOW_SECONDS") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:dedupe_window_seconds, 300)

    value ->
      case Integer.parse(value) do
        {seconds, _} -> seconds
        :error -> 300
      end
  end

rate_limit_per_kind =
  case System.get_env("MICELIO_ERROR_RATE_LIMIT_PER_KIND_PER_MINUTE") ||
         System.get_env("ERROR_RATE_LIMIT_PER_KIND_PER_MINUTE") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:capture_rate_limit_per_kind_per_minute, 100)

    value ->
      case Integer.parse(value) do
        {count, _} -> count
        :error -> 100
      end
  end

rate_limit_total =
  case System.get_env("MICELIO_ERROR_RATE_LIMIT_TOTAL_PER_MINUTE") ||
         System.get_env("ERROR_RATE_LIMIT_TOTAL_PER_MINUTE") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:capture_rate_limit_total_per_minute, 1000)

    value ->
      case Integer.parse(value) do
        {count, _} -> count
        :error -> 1000
      end
  end

sampling_after_occurrences =
  case System.get_env("MICELIO_ERROR_SAMPLING_AFTER_OCCURRENCES") ||
         System.get_env("ERROR_SAMPLING_AFTER_OCCURRENCES") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:sampling_after_occurrences, 100)

    value ->
      case Integer.parse(value) do
        {count, _} -> count
        :error -> 100
      end
  end

sampling_rate =
  case System.get_env("MICELIO_ERROR_SAMPLING_RATE") || System.get_env("ERROR_SAMPLING_RATE") do
    nil ->
      Application.get_env(:micelio, :errors, [])
      |> Keyword.get(:sampling_rate, 0.1)

    value ->
      case Float.parse(value) do
        {rate, _} -> rate
        :error -> 0.1
      end
  end

# Storage configuration (local by default, S3 opt-in)
storage_backend =
  case System.get_env("MICELIO_STORAGE_BACKEND") || System.get_env("STORAGE_BACKEND") do
    "tiered" -> :tiered
    "s3" -> :s3
    _ -> :local
  end

local_path_default =
  System.get_env("MICELIO_STORAGE_LOCAL_PATH") ||
    System.get_env("STORAGE_LOCAL_PATH") ||
    case config_env() do
      :prod -> "/var/micelio/storage"
      _ -> Path.join([System.tmp_dir!(), "micelio", "storage"])
    end

cache_path_default =
  System.get_env("MICELIO_STORAGE_DISK_PATH") ||
    System.get_env("STORAGE_CACHE_PATH") ||
    case config_env() do
      :prod -> "/var/micelio/cache"
      _ -> Path.join([System.tmp_dir!(), "micelio", "cache"])
    end

origin_backend =
  case System.get_env("MICELIO_STORAGE_ORIGIN_BACKEND") ||
         System.get_env("STORAGE_ORIGIN_BACKEND") do
    "s3" ->
      :s3

    "local" ->
      :local

    _ ->
      if System.get_env("MICELIO_S3_BUCKET") || System.get_env("S3_BUCKET"), do: :s3, else: :local
  end

cache_memory_max_bytes =
  case System.get_env("MICELIO_STORAGE_MEMORY_MAX_BYTES") ||
         System.get_env("STORAGE_CACHE_MEMORY_MAX_BYTES") do
    nil -> nil
    value -> String.to_integer(value)
  end

cache_timeout_ms =
  case System.get_env("MICELIO_STORAGE_CDN_TIMEOUT") ||
         System.get_env("STORAGE_CDN_TIMEOUT_MS") do
    nil -> nil
    value -> String.to_integer(value)
  end

cdn_base_url =
  System.get_env("MICELIO_STORAGE_CDN_URL") || System.get_env("STORAGE_CDN_BASE_URL")

maybe_put = fn config, key, value ->
  if is_nil(value), do: config, else: Keyword.put(config, key, value)
end

storage_config =
  case storage_backend do
    :local ->
      if config_env() == :prod do
        IO.warn(
          "MICELIO_STORAGE_BACKEND is set to local in production; S3 is strongly recommended."
        )
      end

      [
        backend: :local,
        local_path: local_path_default
      ]
      |> maybe_put.(:cdn_base_url, cdn_base_url)

    :s3 ->
      [
        backend: :s3,
        s3_bucket:
          System.get_env("MICELIO_S3_BUCKET") || System.get_env("S3_BUCKET") ||
            raise("environment variable MICELIO_S3_BUCKET is missing."),
        s3_region:
          System.get_env("MICELIO_S3_REGION") || System.get_env("S3_REGION") || "us-east-1",
        s3_endpoint: System.get_env("MICELIO_S3_ENDPOINT") || System.get_env("S3_ENDPOINT"),
        s3_access_key_id:
          System.get_env("MICELIO_S3_ACCESS_KEY_ID") || System.get_env("S3_ACCESS_KEY_ID"),
        s3_secret_access_key:
          System.get_env("MICELIO_S3_SECRET_ACCESS_KEY") || System.get_env("S3_SECRET_ACCESS_KEY"),
        s3_url_style:
          System.get_env("MICELIO_S3_URL_STYLE") || System.get_env("S3_URL_STYLE") || "virtual"
      ]
      |> maybe_put.(:cdn_base_url, cdn_base_url)

    :tiered ->
      base_config =
        [
          backend: :tiered,
          origin_backend: origin_backend,
          origin_local_path: local_path_default,
          local_path: local_path_default,
          cache_disk_path: cache_path_default,
          cdn_base_url: cdn_base_url
        ]
        |> maybe_put.(:cache_memory_max_bytes, cache_memory_max_bytes)
        |> maybe_put.(:cdn_timeout_ms, cache_timeout_ms)

      case origin_backend do
        :s3 ->
          base_config ++
            [
              s3_bucket:
                System.get_env("MICELIO_S3_BUCKET") || System.get_env("S3_BUCKET") ||
                  raise("environment variable MICELIO_S3_BUCKET is missing."),
              s3_region:
                System.get_env("MICELIO_S3_REGION") || System.get_env("S3_REGION") || "us-east-1",
              s3_endpoint: System.get_env("MICELIO_S3_ENDPOINT") || System.get_env("S3_ENDPOINT"),
              s3_access_key_id:
                System.get_env("MICELIO_S3_ACCESS_KEY_ID") || System.get_env("S3_ACCESS_KEY_ID"),
              s3_secret_access_key:
                System.get_env("MICELIO_S3_SECRET_ACCESS_KEY") ||
                  System.get_env("S3_SECRET_ACCESS_KEY"),
              s3_url_style:
                System.get_env("MICELIO_S3_URL_STYLE") || System.get_env("S3_URL_STYLE") ||
                  "virtual"
            ]

        :local ->
          base_config
      end
  end

is_seed_run = System.get_env("MIX_TASK") == "run"

grpc_enabled =
  if is_seed_run do
    false
  else
    case System.get_env("MICELIO_GRPC_ENABLED") do
      nil ->
        Application.get_env(:micelio, Micelio.GRPC, [])
        |> Keyword.get(:enabled, false)

      value ->
        value == "true"
    end
  end

grpc_tls_certfile = System.get_env("MICELIO_GRPC_TLS_CERTFILE")
grpc_tls_keyfile = System.get_env("MICELIO_GRPC_TLS_KEYFILE")
grpc_tls_cacertfile = System.get_env("MICELIO_GRPC_TLS_CACERTFILE")

micelio_workspace_path =
  case System.get_env("MICELIO_WORKSPACE_PATH") do
    nil ->
      nil

    value ->
      trimmed = String.trim(value)
      if trimmed != "", do: trimmed
  end

grpc_tls_mode =
  case System.get_env("MICELIO_GRPC_TLS_MODE") do
    "proxy" -> :proxy
    "insecure" -> :insecure
    nil -> if config_env() == :dev, do: :proxy, else: :required
    _ -> :required
  end

{grpc_tls_certfile, grpc_tls_keyfile} =
  case {grpc_tls_certfile, grpc_tls_keyfile} do
    {nil, nil} ->
      cert_pem = System.get_env("MICELIO_TLS_CERT_PEM") || System.get_env("TLS_CERT_PEM")
      key_pem = System.get_env("MICELIO_TLS_KEY_PEM") || System.get_env("TLS_KEY_PEM")

      if grpc_tls_mode != :proxy and is_binary(cert_pem) and is_binary(key_pem) do
        tls_dir = Path.join([System.tmp_dir!(), "micelio", "grpc-tls"])
        File.mkdir_p!(tls_dir)

        certfile = Path.join(tls_dir, "cert.pem")
        keyfile = Path.join(tls_dir, "key.pem")

        File.write!(certfile, String.replace(cert_pem, "\\n", "\n"))
        File.write!(keyfile, String.replace(key_pem, "\\n", "\n"))
        File.chmod!(certfile, 0o600)
        File.chmod!(keyfile, 0o600)

        {certfile, keyfile}
      else
        {nil, nil}
      end

    {certfile, keyfile} ->
      {certfile, keyfile}
  end

grpc_tls =
  case {grpc_tls_certfile, grpc_tls_keyfile} do
    {nil, nil} ->
      []

    {certfile, keyfile} ->
      tls_base = [certfile: certfile, keyfile: keyfile]

      case grpc_tls_cacertfile do
        nil -> tls_base
        cacertfile -> tls_base ++ [cacertfile: cacertfile]
      end
  end

github_oauth =
  [
    client_id:
      if config_env() == :dev do
        System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_ID_DEV") ||
          System.get_env("GITHUB_OAUTH_CLIENT_ID_DEV") ||
          System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_ID") ||
          System.get_env("GITHUB_OAUTH_CLIENT_ID")
      else
        System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_ID") ||
          System.get_env("GITHUB_OAUTH_CLIENT_ID")
      end,
    client_secret:
      if config_env() == :dev do
        System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_SECRET_DEV") ||
          System.get_env("GITHUB_OAUTH_CLIENT_SECRET_DEV") ||
          System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_SECRET") ||
          System.get_env("GITHUB_OAUTH_CLIENT_SECRET")
      else
        System.get_env("MICELIO_GITHUB_OAUTH_CLIENT_SECRET") ||
          System.get_env("GITHUB_OAUTH_CLIENT_SECRET")
      end,
    redirect_uri:
      if config_env() == :dev do
        System.get_env("MICELIO_GITHUB_OAUTH_REDIRECT_URI_DEV") ||
          System.get_env("GITHUB_OAUTH_REDIRECT_URI_DEV") ||
          System.get_env("MICELIO_GITHUB_OAUTH_REDIRECT_URI") ||
          System.get_env("GITHUB_OAUTH_REDIRECT_URI")
      else
        System.get_env("MICELIO_GITHUB_OAUTH_REDIRECT_URI") ||
          System.get_env("GITHUB_OAUTH_REDIRECT_URI")
      end
  ]
  |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

config :micelio, :errors,
  external_sentry_enabled: external_sentry_enabled,
  retention_days: retention_days,
  resolved_retention_days: resolved_retention_days,
  unresolved_retention_days: unresolved_retention_days,
  retention_archive_enabled: retention_archive_enabled,
  retention_archive_prefix: retention_archive_prefix,
  retention_vacuum_enabled: retention_vacuum_enabled,
  retention_table_warn_threshold: retention_table_warn_threshold,
  capture_enabled: capture_enabled,
  dedupe_window_seconds: dedupe_window_seconds,
  capture_rate_limit_per_kind_per_minute: rate_limit_per_kind,
  capture_rate_limit_total_per_minute: rate_limit_total,
  sampling_after_occurrences: sampling_after_occurrences,
  sampling_rate: sampling_rate

if config_env() != :test do
  encryption_key =
    System.get_env("MICELIO_ENCRYPTION_KEY") ||
      System.get_env("ENCRYPTION_KEY") ||
      raise """
      environment variable MICELIO_ENCRYPTION_KEY is missing.
      Generate a 32-byte key and set it as base64, for example:
      `openssl rand -base64 32`
      """

  previous_keys =
    (System.get_env("MICELIO_ENCRYPTION_PREVIOUS_KEYS") ||
       System.get_env("ENCRYPTION_PREVIOUS_KEYS") || "")
    |> String.split(",", trim: true)
    |> Enum.map(fn entry ->
      case String.split(entry, ":", parts: 2) do
        [tag, key] -> {String.trim(tag), String.trim(key)}
        _ -> raise "ENCRYPTION_PREVIOUS_KEYS must be \"tag:base64\" comma-separated entries"
      end
    end)

  previous_ciphers =
    previous_keys
    |> Enum.with_index(1)
    |> Enum.map(fn {{tag, key}, index} ->
      {
        String.to_atom("previous_#{index}"),
        {Cloak.Ciphers.AES.GCM, [tag: tag, key: Base.decode64!(key)]}
      }
    end)

  ciphers =
    [
      default: {
        Cloak.Ciphers.AES.GCM,
        [tag: "AES.GCM.V1", key: Base.decode64!(encryption_key)]
      }
    ] ++ previous_ciphers

  config :micelio, Micelio.Cloak, json_library: Jason, ciphers: ciphers
end

config :micelio, Micelio.Storage, storage_config
config :micelio, :micelio_workspace_path, micelio_workspace_path

if github_oauth != [] do
  config :micelio, :github_oauth, github_oauth
end

gitlab_oauth =
  [
    client_id:
      if config_env() == :dev do
        System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_ID_DEV") ||
          System.get_env("GITLAB_OAUTH_CLIENT_ID_DEV") ||
          System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_ID") ||
          System.get_env("GITLAB_OAUTH_CLIENT_ID")
      else
        System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_ID") ||
          System.get_env("GITLAB_OAUTH_CLIENT_ID")
      end,
    client_secret:
      if config_env() == :dev do
        System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_SECRET_DEV") ||
          System.get_env("GITLAB_OAUTH_CLIENT_SECRET_DEV") ||
          System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_SECRET") ||
          System.get_env("GITLAB_OAUTH_CLIENT_SECRET")
      else
        System.get_env("MICELIO_GITLAB_OAUTH_CLIENT_SECRET") ||
          System.get_env("GITLAB_OAUTH_CLIENT_SECRET")
      end,
    redirect_uri:
      if config_env() == :dev do
        System.get_env("MICELIO_GITLAB_OAUTH_REDIRECT_URI_DEV") ||
          System.get_env("GITLAB_OAUTH_REDIRECT_URI_DEV") ||
          System.get_env("MICELIO_GITLAB_OAUTH_REDIRECT_URI") ||
          System.get_env("GITLAB_OAUTH_REDIRECT_URI")
      else
        System.get_env("MICELIO_GITLAB_OAUTH_REDIRECT_URI") ||
          System.get_env("GITLAB_OAUTH_REDIRECT_URI")
      end,
    scope:
      if config_env() == :dev do
        System.get_env("MICELIO_GITLAB_OAUTH_SCOPE_DEV") ||
          System.get_env("GITLAB_OAUTH_SCOPE_DEV") ||
          System.get_env("MICELIO_GITLAB_OAUTH_SCOPE") ||
          System.get_env("GITLAB_OAUTH_SCOPE")
      else
        System.get_env("MICELIO_GITLAB_OAUTH_SCOPE") ||
          System.get_env("GITLAB_OAUTH_SCOPE")
      end
  ]
  |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

if gitlab_oauth != [] do
  config :micelio, :gitlab_oauth, gitlab_oauth
end

# Open Graph image generation via Carta (opt-in in prod, enabled by default in dev)
# Set MICELIO_OPEN_GRAPH_ENABLED=true/false to override. Requires Chromium on the system.
og_enabled =
  case System.get_env("MICELIO_OPEN_GRAPH_ENABLED") do
    nil -> config_env() == :dev
    value -> value == "true"
  end

og_pool_size =
  case System.get_env("MICELIO_OPEN_GRAPH_POOL_SIZE") do
    nil -> if(config_env() == :dev, do: 1, else: 2)
    value -> String.to_integer(value)
  end

og_chrome_path = System.get_env("MICELIO_OPEN_GRAPH_CHROME_PATH")

og_config =
  [enabled: og_enabled, pool_size: og_pool_size]
  |> then(fn config ->
    if og_chrome_path, do: Keyword.put(config, :chrome_path, og_chrome_path), else: config
  end)

# Global rate limiting with per-domain overrides
# MICELIO_RATE_LIMIT_DEFAULT: requests per window (default: 200)
# MICELIO_RATE_LIMIT_WINDOW_MS: window duration in ms (default: 60000)
# MICELIO_RATE_LIMIT_OPEN_GRAPH: override for OG image endpoint (default: 30)
rate_limit_default =
  case System.get_env("MICELIO_RATE_LIMIT_DEFAULT") do
    nil -> 200
    value -> String.to_integer(value)
  end

rate_limit_window_ms =
  case System.get_env("MICELIO_RATE_LIMIT_WINDOW_MS") do
    nil -> 60_000
    value -> String.to_integer(value)
  end

rate_limit_overrides =
  [{"open_graph", "MICELIO_RATE_LIMIT_OPEN_GRAPH", 30}]
  |> Enum.reduce(%{}, fn {domain, env_var, default}, acc ->
    value =
      case System.get_env(env_var) do
        nil -> default
        v -> String.to_integer(v)
      end

    Map.put(acc, domain, value)
  end)

daytona_base_url =
  System.get_env("MICELIO_DAYTONA_API_BASE_URL") || System.get_env("DAYTONA_API_BASE_URL") ||
    "https://app.daytona.io/api"

daytona_api_key = System.get_env("MICELIO_DAYTONA_API_KEY") || System.get_env("DAYTONA_API_KEY")

daytona_organization_id =
  System.get_env("MICELIO_DAYTONA_ORGANIZATION_ID") || System.get_env("DAYTONA_ORGANIZATION_ID")

daytona_preview_port =
  String.to_integer(
    System.get_env("MICELIO_DAYTONA_PREVIEW_PORT") || System.get_env("DAYTONA_PREVIEW_PORT") ||
      "3000"
  )

daytona_auto_stop_interval =
  String.to_integer(
    System.get_env("MICELIO_DAYTONA_AUTO_STOP_MINUTES") ||
      System.get_env("DAYTONA_AUTO_STOP_MINUTES") || "15"
  )

daytona_auto_archive_interval =
  String.to_integer(
    System.get_env("MICELIO_DAYTONA_AUTO_ARCHIVE_MINUTES") ||
      System.get_env("DAYTONA_AUTO_ARCHIVE_MINUTES") || "30"
  )

daytona_checkout_root =
  System.get_env("MICELIO_DAYTONA_LOCAL_CHECKOUT_ROOT") ||
    System.get_env("DAYTONA_LOCAL_CHECKOUT_ROOT")

sandbox_provider =
  System.get_env("MICELIO_SANDBOX_PROVIDER") || System.get_env("SANDBOX_PROVIDER") || "daytona"

sandbox_module_server_url =
  System.get_env("MICELIO_SANDBOX_MODULE_SERVER_URL") ||
    System.get_env("SANDBOX_MODULE_SERVER_URL")

config :micelio, Micelio.Sandboxes,
  default_provider: sandbox_provider,
  module_server_url: sandbox_module_server_url

config :micelio, Micelio.Sandboxes.DaytonaProvider,
  base_url: daytona_base_url,
  api_key: daytona_api_key,
  organization_id: daytona_organization_id,
  preview_port: daytona_preview_port,
  auto_stop_interval_minutes: daytona_auto_stop_interval,
  auto_archive_interval_minutes: daytona_auto_archive_interval,
  local_checkout_root: daytona_checkout_root

config :micelio, :clickhouse,
  url: System.get_env("MICELIO_CLICKHOUSE_URL") || System.get_env("CLICKHOUSE_URL"),
  user: System.get_env("MICELIO_CLICKHOUSE_USER") || System.get_env("CLICKHOUSE_USER"),
  password:
    System.get_env("MICELIO_CLICKHOUSE_PASSWORD") || System.get_env("CLICKHOUSE_PASSWORD"),
  database:
    System.get_env("MICELIO_CLICKHOUSE_DATABASE") || System.get_env("CLICKHOUSE_DATABASE") ||
      "micelio"

config :micelio, :open_graph, og_config

config :micelio, :rate_limits,
  default: rate_limit_default,
  window_ms: rate_limit_window_ms,
  overrides: rate_limit_overrides

if grpc_enabled do
  config :micelio, Micelio.GRPC,
    enabled: true,
    port: String.to_integer(System.get_env("MICELIO_GRPC_PORT", "50051")),
    tls_mode: grpc_tls_mode,
    tls: grpc_tls
else
  if is_seed_run do
    config :micelio, Micelio.GRPC, enabled: false
  end
end

# Dev instance env vars are set by mise/utilities/dev_instance_env.sh (sourced via mise.toml).
# They scope ports and databases per clone so multiple clones can run simultaneously.
dev_port = System.get_env("MICELIO_DEV_PORT")
dev_grpc_port = System.get_env("MICELIO_DEV_GRPC_PORT")
dev_postgres_db = System.get_env("MICELIO_DEV_POSTGRES_DB")
test_postgres_db = System.get_env("MICELIO_TEST_POSTGRES_DB")

default_port =
  case {config_env(), dev_port} do
    {:test, _} -> System.get_env("MICELIO_TEST_PORT") || "4002"
    {_, nil} -> "4000"
    {_, port} -> port
  end

config :micelio, MicelioWeb.Endpoint,
  http: [
    port:
      String.to_integer(System.get_env("MICELIO_PORT") || System.get_env("PORT") || default_port)
  ]

if config_env() in [:dev, :test] do
  db_name =
    case config_env() do
      :dev -> dev_postgres_db
      :test -> test_postgres_db
    end

  if db_name do
    config :micelio, Micelio.Repo, database: db_name
  end

  if dev_grpc_port do
    config :micelio, Micelio.GRPC, port: String.to_integer(dev_grpc_port)
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("MICELIO_DATABASE_URL") ||
      System.get_env("DATABASE_URL") ||
      raise """
      environment variable MICELIO_DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 =
    if (System.get_env("MICELIO_ECTO_IPV6") || System.get_env("ECTO_IPV6")) in ~w(true 1),
      do: [:inet6],
      else: []

  otel_protocol =
    case System.get_env("MICELIO_OTEL_EXPORTER_OTLP_PROTOCOL") ||
           System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL") || "grpc" do
      "grpc" -> :grpc
      "http_protobuf" -> :http_protobuf
      protocol -> raise "unsupported OTEL_EXPORTER_OTLP_PROTOCOL=#{inspect(protocol)}"
    end

  metrics_bearer_token =
    System.get_env("MICELIO_METRICS_BEARER_TOKEN") ||
      System.get_env("METRICS_BEARER_TOKEN") ||
      raise """
      environment variable MICELIO_METRICS_BEARER_TOKEN is missing.
      Generate one with: mix phx.gen.secret 32
      """

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("MICELIO_SECRET_KEY_BASE") ||
      System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable MICELIO_SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("MICELIO_HOST") || System.get_env("PHX_HOST") || "example.com"

  otel_service_name =
    System.get_env("MICELIO_OTEL_SERVICE_NAME") || System.get_env("OTEL_SERVICE_NAME") ||
      "micelio-web"

  otel_deployment_environment =
    System.get_env("MICELIO_OTEL_DEPLOYMENT_ENVIRONMENT") ||
      System.get_env("OTEL_DEPLOYMENT_ENVIRONMENT") || "production"

  # Configure SMTP mailer
  smtp_host = System.get_env("MICELIO_SMTP_HOST") || System.get_env("SMTP_HOST")
  smtp_username = System.get_env("MICELIO_SMTP_USERNAME") || System.get_env("SMTP_USERNAME")
  smtp_password = System.get_env("MICELIO_SMTP_PASSWORD") || System.get_env("SMTP_PASSWORD")

  required_smtp_vars = [
    {"MICELIO_SMTP_HOST", smtp_host},
    {"MICELIO_SMTP_USERNAME", smtp_username},
    {"MICELIO_SMTP_PASSWORD", smtp_password}
  ]

  missing_smtp_vars =
    required_smtp_vars
    |> Enum.filter(fn {_, val} -> is_nil(val) end)
    |> Enum.map(fn {name, _} -> name end)

  config :micelio, Micelio.GRPC, require_auth_token: true

  config :micelio, Micelio.Repo,
    url: database_url,
    pool_size:
      String.to_integer(
        System.get_env("MICELIO_POOL_SIZE") || System.get_env("POOL_SIZE") || "10"
      ),
    socket_options: maybe_ipv6

  config :micelio, MicelioWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :micelio, MicelioWeb.Plugs.Metrics, bearer_token: metrics_bearer_token

  config :micelio,
         :dns_cluster_query,
         System.get_env("MICELIO_DNS_CLUSTER_QUERY") || System.get_env("DNS_CLUSTER_QUERY")

  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp,
    resource: [
      service: %{
        name: otel_service_name,
        version: to_string(Application.spec(:micelio, :vsn))
      },
      deployment: %{
        environment: otel_deployment_environment
      }
    ]

  config :opentelemetry_exporter,
    otlp_protocol: otel_protocol,
    otlp_endpoint:
      System.get_env("MICELIO_OTEL_EXPORTER_OTLP_ENDPOINT") ||
        System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://micelio-alloy:4317"

  if Enum.any?(missing_smtp_vars) do
    raise """
    Missing required SMTP configuration. The following environment variables are not set:

    #{Enum.map(missing_smtp_vars, &"  - #{&1}") |> Enum.join("\n")}

    Please configure SMTP using fnox:
      fnox set SMTP_HOST smtp.example.com
      fnox set SMTP_USERNAME your-username
      fnox set SMTP_PASSWORD your-password
      fnox set SMTP_PORT 587
      fnox set SMTP_FROM_EMAIL noreply@yourapp.com
      fnox set SMTP_FROM_NAME "Your App"

    Optional variables (have defaults):
      - SMTP_PORT (default: "587")
      - SMTP_SSL (default: "false")
      - SMTP_TLS (default: "if_available")
      - SMTP_FROM_EMAIL (default: "noreply@micelio.dev")
      - SMTP_FROM_NAME (default: "Micelio")
      - SMTP_TLS_VERIFY (default: "true")
      - SMTP_TLS_CA_CERTS_PATH (default: system CA certs)
      - SMTP_TLS_SERVER_NAME (default: SMTP_HOST)
    """
  end

  smtp_port = System.get_env("MICELIO_SMTP_PORT") || System.get_env("SMTP_PORT") || "587"

  smtp_from_email =
    System.get_env("MICELIO_SMTP_FROM_EMAIL") || System.get_env("SMTP_FROM_EMAIL") ||
      "noreply@micelio.dev"

  smtp_from_name =
    System.get_env("MICELIO_SMTP_FROM_NAME") || System.get_env("SMTP_FROM_NAME") || "Micelio"

  # Parse SSL/TLS settings from environment variables
  smtp_ssl =
    (System.get_env("MICELIO_SMTP_SSL") || System.get_env("SMTP_SSL") || "false") == "true"

  smtp_tls =
    case System.get_env("MICELIO_SMTP_TLS") || System.get_env("SMTP_TLS") || "if_available" do
      "true" -> :always
      "always" -> :always
      "if_available" -> :if_available
      "false" -> :never
      "never" -> :never
      _ -> :if_available
    end

  # Configure TLS options for SMTP.
  # Default to peer verification and allow optional CA overrides.
  smtp_tls_verify =
    (System.get_env("MICELIO_SMTP_TLS_VERIFY") || System.get_env("SMTP_TLS_VERIFY") || "true") !=
      "false"

  smtp_tls_ca_cert_path =
    System.get_env("MICELIO_SMTP_TLS_CA_CERTS_PATH") || System.get_env("SMTP_TLS_CA_CERTS_PATH")

  smtp_default_cacerts =
    case :public_key.cacerts_get() do
      :undefined -> nil
      cacerts when is_list(cacerts) -> cacerts
    end

  smtp_system_ca_path = "/etc/ssl/certs/ca-certificates.crt"

  smtp_tls_server_name =
    System.get_env("MICELIO_SMTP_TLS_SERVER_NAME") || System.get_env("SMTP_TLS_SERVER_NAME") ||
      smtp_host

  smtp_tls_options =
    cond do
      (smtp_ssl or smtp_tls in [:always, :if_available]) and smtp_tls_verify ->
        ca_options =
          cond do
            smtp_tls_ca_cert_path ->
              [cacertfile: smtp_tls_ca_cert_path]

            is_list(smtp_default_cacerts) ->
              [cacerts: smtp_default_cacerts]

            File.exists?(smtp_system_ca_path) ->
              [cacertfile: smtp_system_ca_path]

            true ->
              []
          end

        [
          verify: :verify_peer,
          depth: 99,
          server_name_indication: String.to_charlist(smtp_tls_server_name)
        ] ++ ca_options

      smtp_ssl or smtp_tls in [:always, :if_available] ->
        [verify: :verify_none]

      true ->
        []
    end

  smtp_sockopts =
    if smtp_ssl do
      smtp_tls_options
    else
      []
    end

  config :micelio, Micelio.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(smtp_port),
    username: smtp_username,
    password: smtp_password,
    tls: smtp_tls,
    ssl: smtp_ssl,
    tls_options: smtp_tls_options,
    sockopts: smtp_sockopts,
    auth: :always,
    from: {smtp_from_name, smtp_from_email}

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :micelio, MicelioWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :micelio, MicelioWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :micelio, Micelio.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
