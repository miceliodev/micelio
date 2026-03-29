%{
  title: "Environment Variables",
  description: "All configuration options for running a Micelio server, organized by domain."
}

---

All Micelio configuration is done through environment variables at runtime. This page documents every option available, organized by domain.

## Core

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_SERVER` | Yes (prod) | — | Set to `true` to start the HTTP server |
| `SECRET_KEY_BASE` | Yes (prod) | — | Secret for signing cookies and tokens. Generate with `mix phx.gen.secret` |
| `MICELIO_HOST` | No | `example.com` | Public hostname for URL generation |
| `PORT` | No | `4000` | HTTP port the server listens on |
| `MICELIO_ENCRYPTION_KEY` | Yes | — | 32-byte base64 key for field encryption. Generate with `openssl rand -base64 32` |
| `MICELIO_ENCRYPTION_PREVIOUS_KEYS` | No | — | Comma-separated `tag:base64` entries for key rotation |
| `DNS_CLUSTER_QUERY` | No | — | DNS query for clustering nodes |

## Database

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes (prod) | — | PostgreSQL connection URL, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `POOL_SIZE` | No | `10` | Database connection pool size |
| `ECTO_IPV6` | No | `false` | Set to `true` to enable IPv6 for database connections |

## Storage

Micelio supports local filesystem, S3, or tiered (RAM + disk cache + CDN + origin) storage backends.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_STORAGE_BACKEND` | No | `local` | Storage backend: `local`, `s3`, or `tiered` |
| `MICELIO_STORAGE_LOCAL_PATH` | No | `/var/micelio/storage` (prod) | Local filesystem path for storage |
| `MICELIO_S3_BUCKET` | Yes (if s3) | — | S3 bucket name |
| `MICELIO_S3_REGION` | No | `us-east-1` | S3 region |
| `MICELIO_S3_ENDPOINT` | No | — | Custom S3 endpoint for S3-compatible services (MinIO, R2, etc.) |
| `MICELIO_S3_ACCESS_KEY_ID` | No | — | S3 access key (optional if using IAM roles) |
| `MICELIO_S3_SECRET_ACCESS_KEY` | No | — | S3 secret key (optional if using IAM roles) |
| `MICELIO_S3_URL_STYLE` | No | `virtual` | S3 URL style: `virtual` or `path` |

### Tiered storage

When `MICELIO_STORAGE_BACKEND=tiered`, Micelio uses a multi-tier cache: RAM, SSD disk, CDN, then origin (local or S3).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_STORAGE_ORIGIN_BACKEND` | No | auto | Origin backend: `local` or `s3`. Defaults to `s3` if `MICELIO_S3_BUCKET` is set |
| `MICELIO_STORAGE_CACHE_PATH` | No | `/var/micelio/cache` (prod) | Disk cache path |
| `MICELIO_STORAGE_CACHE_MEMORY_MAX_BYTES` | No | — | Max bytes for in-memory cache |
| `MICELIO_STORAGE_CDN_BASE_URL` | No | — | CDN base URL for cache invalidation |
| `MICELIO_STORAGE_CDN_TIMEOUT_MS` | No | — | Timeout for CDN requests |

## Open Graph Images

Browser-based OG image generation using Carta and headless Chromium.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_OG_ENABLED` | No | `true` (dev), `false` (prod) | Enable OG image generation |
| `MICELIO_OG_POOL_SIZE` | No | `1` (dev), `2` (prod) | Number of Chromium instances in the browser pool |
| `MICELIO_OG_CHROME_PATH` | No | auto-detect | Path to Chromium binary |

## Rate Limiting

Global rate limiting with per-domain overrides.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_RATE_LIMIT_DEFAULT` | No | `200` | Default requests per window per IP |
| `MICELIO_RATE_LIMIT_WINDOW_MS` | No | `60000` | Rate limit window in milliseconds |
| `MICELIO_RATE_LIMIT_OG` | No | `30` | Rate limit override for the `/og` endpoint |

## OG Cache Busters

Per-platform cache busters appended to OG image URLs. Useful for forcing social platforms to refetch images after changes.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_OG_CACHE_BUSTER_DEFAULT` | No | — | Default cache buster string |
| `MICELIO_OG_CACHE_BUSTER_TWITTER` | No | — | Cache buster for Twitter/X |
| `MICELIO_OG_CACHE_BUSTER_LINKEDIN` | No | — | Cache buster for LinkedIn |
| `MICELIO_OG_CACHE_BUSTER_FACEBOOK` | No | — | Cache buster for Facebook |
| `MICELIO_OG_CACHE_BUSTER_SLACK` | No | — | Cache buster for Slack |
| `MICELIO_OG_CACHE_BUSTER_DISCORD` | No | — | Cache buster for Discord |
| `MICELIO_OG_CACHE_BUSTER_TELEGRAM` | No | — | Cache buster for Telegram |
| `MICELIO_OG_CACHE_BUSTER_PINTEREST` | No | — | Cache buster for Pinterest |

## gRPC

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_GRPC_ENABLED` | No | `false` | Enable the gRPC server |
| `MICELIO_GRPC_PORT` | No | `50051` | gRPC server port |
| `MICELIO_GRPC_TLS_MODE` | No | `required` (prod), `proxy` (dev) | TLS mode: `required`, `proxy`, or `insecure` |
| `MICELIO_GRPC_TLS_CERTFILE` | No | — | Path to TLS certificate file |
| `MICELIO_GRPC_TLS_KEYFILE` | No | — | Path to TLS private key file |
| `MICELIO_GRPC_TLS_CACERTFILE` | No | — | Path to CA certificate file |
| `TLS_CERT_PEM` | No | — | Inline TLS certificate PEM (alternative to file path) |
| `TLS_KEY_PEM` | No | — | Inline TLS private key PEM (alternative to file path) |
| `MICELIO_WORKSPACE_PATH` | No | — | Path to local workspace directory |

## OAuth Providers

### GitHub

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITHUB_OAUTH_CLIENT_ID` | No | — | GitHub OAuth app client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | No | — | GitHub OAuth app client secret |
| `GITHUB_OAUTH_REDIRECT_URI` | No | — | OAuth callback URL |

### GitLab

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITLAB_OAUTH_CLIENT_ID` | No | — | GitLab OAuth app client ID |
| `GITLAB_OAUTH_CLIENT_SECRET` | No | — | GitLab OAuth app client secret |
| `GITLAB_OAUTH_REDIRECT_URI` | No | — | OAuth callback URL |
| `GITLAB_OAUTH_SCOPE` | No | — | Requested OAuth scopes |

> [!NOTE]
> In development, `_DEV` suffixed variants (e.g. `GITHUB_OAUTH_CLIENT_ID_DEV`) take priority over the base variable name.

## Email (SMTP)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SMTP_HOST` | Yes (prod) | — | SMTP server hostname |
| `SMTP_USERNAME` | Yes (prod) | — | SMTP username |
| `SMTP_PASSWORD` | Yes (prod) | — | SMTP password |
| `SMTP_PORT` | No | `587` | SMTP port |
| `SMTP_SSL` | No | `false` | Enable SSL for SMTP |
| `SMTP_TLS` | No | `if_available` | TLS mode: `true`/`always`, `if_available`, `false`/`never` |
| `SMTP_FROM_EMAIL` | No | `noreply@micelio.dev` | Sender email address |
| `SMTP_FROM_NAME` | No | `Micelio` | Sender display name |
| `SMTP_TLS_VERIFY` | No | `true` | Enable TLS certificate verification |
| `SMTP_TLS_CA_CERTS_PATH` | No | system | Path to CA certificates file |
| `SMTP_TLS_SERVER_NAME` | No | `SMTP_HOST` | TLS server name for SNI |

## Observability

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | `http://micelio-alloy:4317` | OpenTelemetry collector endpoint |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | No | `grpc` | Protocol: `grpc` or `http_protobuf` |
| `OTEL_SERVICE_NAME` | No | `micelio-web` | Service name in traces |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | No | `production` | Deployment environment label |
| `MICELIO_METRICS_BEARER_TOKEN` | Yes (prod) | — | Bearer token for the metrics endpoint |

## Error Tracking

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_ENABLE_EXTERNAL_SENTRY` | No | `false` | Forward errors to external Sentry |
| `MICELIO_ERROR_CAPTURE_ENABLED` | No | `true` | Enable error capture |
| `MICELIO_ERROR_RETENTION_DAYS` | No | `90` | Days to retain errors |
| `MICELIO_ERROR_RESOLVED_RETENTION_DAYS` | No | `30` | Days to retain resolved errors |
| `MICELIO_ERROR_UNRESOLVED_RETENTION_DAYS` | No | `90` | Days to retain unresolved errors |
| `MICELIO_ERROR_RETENTION_ARCHIVE_ENABLED` | No | `false` | Archive errors before deletion |
| `MICELIO_ERROR_RETENTION_ARCHIVE_PREFIX` | No | `errors/archives` | Storage prefix for archived errors |
| `MICELIO_ERROR_RETENTION_VACUUM_ENABLED` | No | `true` | Vacuum tables after cleanup |
| `MICELIO_ERROR_RETENTION_TABLE_WARN_THRESHOLD` | No | `100000` | Log warning when error count exceeds this |
| `MICELIO_ERROR_DEDUPE_WINDOW_SECONDS` | No | `300` | Window for deduplicating identical errors |
| `MICELIO_ERROR_RATE_LIMIT_PER_KIND_PER_MINUTE` | No | `100` | Max errors per kind per minute |
| `MICELIO_ERROR_RATE_LIMIT_TOTAL_PER_MINUTE` | No | `1000` | Max total errors per minute |
| `MICELIO_ERROR_SAMPLING_AFTER_OCCURRENCES` | No | `100` | Start sampling after this many occurrences |
| `MICELIO_ERROR_SAMPLING_RATE` | No | `0.1` | Sampling rate (0.0 to 1.0) after threshold |

## Analytics

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_CLICKHOUSE_URL` | No | — | ClickHouse server URL |
| `MICELIO_CLICKHOUSE_USER` | No | — | ClickHouse username |
| `MICELIO_CLICKHOUSE_PASSWORD` | No | — | ClickHouse password |
| `MICELIO_CLICKHOUSE_DATABASE` | No | `micelio` | ClickHouse database name |
