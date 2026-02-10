# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure Boruta schemas to use custom table names
config :boruta, Boruta.Ecto.Token, source: "oauth_tokens"

config :boruta, Boruta.Oauth,
  repo: Micelio.Repo,
  contexts: [
    resource_owners: Micelio.OAuth.ResourceOwners,
    clients: Micelio.OAuth.Clients,
    access_tokens: Micelio.OAuth.AccessTokens
  ],
  token_generator: Micelio.OAuth.TokenGenerator

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  micelio: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Hammer rate limiting configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :micelio, Micelio.AgentInfra.Billing,
  limits: %{
    cpu_core_seconds: 120_000,
    memory_mb_seconds: 61_440_000,
    disk_gb_seconds: 1_800_000,
    billable_units: 200_000
  },
  unit_weights: %{
    cpu_core_second: 1,
    memory_mb_second: 1,
    disk_gb_second: 5
  },
  unit_price_cents: 1,
  default_ttl_seconds: 3600

config :micelio, Micelio.Errors.RetentionScheduler,
  enabled: true,
  run_hour: 3,
  run_minute: 0

config :micelio, Micelio.GRPC,
  enabled: false,
  port: 50_051,
  require_auth_token: false

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :micelio, Micelio.Mailer, adapter: Swoosh.Adapters.Local

# Configure the endpoint
config :micelio, MicelioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MicelioWeb.ErrorHTML, json: MicelioWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Micelio.PubSub,
  live_view: [signing_salt: "uBaIW6yU"]

# Gettext configuration
config :micelio, MicelioWeb.Gettext,
  default_locale: "en",
  locales: ~w(en ko zh_CN zh_TW ja)

config :micelio, :admin_emails, []

config :micelio, :api_rate_limit,
  limit: 100,
  window_ms: 60_000,
  authenticated_limit: 500,
  authenticated_window_ms: 60_000

config :micelio, :environment, config_env()

config :micelio, :errors,
  retention_days: 90,
  resolved_retention_days: 30,
  unresolved_retention_days: 90,
  retention_archive_enabled: false,
  retention_archive_prefix: "errors/archives",
  retention_vacuum_enabled: true,
  retention_table_warn_threshold: 100_000,
  retention_oban_enabled: false,
  dedupe_window_seconds: 300,
  capture_enabled: true,
  capture_rate_limit_per_kind_per_minute: 100,
  capture_rate_limit_total_per_minute: 1000,
  sampling_after_occurrences: 100,
  sampling_rate: 0.1,
  notification_threshold_count: 10,
  notification_threshold_window_seconds: 300,
  notification_fingerprint_rate_limit_seconds: 3600,
  notification_total_rate_limit_seconds: 3600,
  notification_total_rate_limit_max: 10

config :micelio, :github_oauth, []
config :micelio, :gitlab_oauth, []
config :micelio, :project_llm_default, "gpt-4.1-mini"
config :micelio, :project_llm_models, ["gpt-4.1-mini", "gpt-4.1"]
config :micelio, :remote_execution, allowed_commands: []
config :micelio, :repository_limits, max_projects_per_tenant: 25

config :micelio, :s3_validation_rate_limit,
  limit: 10,
  window_ms: 60_000

config :micelio, :validation_environments, min_quality_score: 80

config :micelio,
  ecto_repos: [Micelio.Repo],
  # Import environment specific config. This must remain at the bottom
  generators: [timestamp_type: :utc_datetime]

config :mime, :types, %{
  "application/activity+json" => ["activity+json"],
  "application/jrd+json" => ["jrd+json"]
}

# Use Jason for JSON parsing in Phoenix
# of this file so it overrides the configuration defined above.
config :phoenix, :json_library, JSON

import_config "#{config_env()}.exs"
