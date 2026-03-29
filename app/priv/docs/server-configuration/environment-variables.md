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
| `MICELIO_SECRET_KEY_BASE` | Yes (prod) | — | Secret for signing cookies and tokens. Generate with `mix phx.gen.secret` |
| `MICELIO_HOST` | No | `example.com` | Public hostname for URL generation |
| `MICELIO_PORT` | No | `4000` | HTTP port the server listens on |
| `MICELIO_ENCRYPTION_KEY` | Yes | — | 32-byte base64 key for field encryption. Generate with `openssl rand -base64 32` |
| `MICELIO_ENCRYPTION_PREVIOUS_KEYS` | No | — | Comma-separated `tag:base64` entries for key rotation |
| `MICELIO_DNS_CLUSTER_QUERY` | No | — | DNS query for clustering nodes |

## Database

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_DATABASE_URL` | Yes (prod) | — | PostgreSQL connection URL, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `MICELIO_POOL_SIZE` | No | `10` | Database connection pool size |
| `MICELIO_ECTO_IPV6` | No | `false` | Set to `true` to enable IPv6 for database connections |

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
| `MICELIO_STORAGE_DISK_PATH` | No | `/var/micelio/cache` (prod) | Disk cache path |
| `MICELIO_STORAGE_MEMORY_MAX_BYTES` | No | — | Max bytes for in-memory cache |
| `MICELIO_STORAGE_CDN_URL` | No | — | CDN base URL |
| `MICELIO_STORAGE_CDN_TIMEOUT` | No | — | Timeout for CDN requests (ms) |

## Open Graph Images

When links to Micelio are shared on platforms like Slack, Discord, or X, those platforms unfurl the link and show a preview card. Micelio generates rich Open Graph images for every page using [Carta](https://github.com/pepicrft/carta), which renders HTML templates into JPEG images via a pool of headless Chromium instances.

Images are lazily generated on first request and cached in storage (local filesystem or S3). We recommend enabling this feature to make shared links more visually informative.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_OPEN_GRAPH_ENABLED` | No | `true` (dev), `false` (prod) | Enable Open Graph image generation |
| `MICELIO_OPEN_GRAPH_POOL_SIZE` | No | `1` (dev), `2` (prod) | Number of Chromium instances in the browser pool |
| `MICELIO_OPEN_GRAPH_CHROME_PATH` | No | auto-detect | Path to Chromium binary |

## Rate Limiting

Micelio uses per-IP token bucket rate limiting. Each IP address gets a fixed number of requests per time window. When the limit is exceeded, the server responds with `429 Too Many Requests` and includes `retry-after` and `x-ratelimit-*` headers.

Specific endpoints can have their own limits via domain overrides (e.g. the Open Graph image endpoint has a lower limit since rendering is expensive). If the same IP repeatedly exceeds the rate limit (10 violations within 5 minutes), it is blocked for 1 hour.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_RATE_LIMIT_DEFAULT` | No | `200` | Default requests per window per IP |
| `MICELIO_RATE_LIMIT_WINDOW_MS` | No | `60000` | Rate limit window in milliseconds |
| `MICELIO_RATE_LIMIT_OPEN_GRAPH` | No | `30` | Rate limit override for the `/og` endpoint |

## gRPC

The `hif` CLI communicates with Micelio via gRPC for operations like authentication, repository management, session handling, and content access. The gRPC server is optional and disabled by default.

> [!NOTE]
> We chose gRPC over REST for CLI-to-forge communication because it uses binary serialization (protobuf), which is significantly more efficient for transferring file content and tree structures. It also gives us strongly typed contracts shared between the Rust CLI and the Elixir server, and HTTP/2 multiplexing for concurrent operations over a single connection.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_GRPC_ENABLED` | No | `false` | Enable the gRPC server |
| `MICELIO_GRPC_PORT` | No | `50051` | gRPC server port |
| `MICELIO_GRPC_TLS_MODE` | No | `required` (prod), `proxy` (dev) | TLS mode: `required`, `proxy`, or `insecure` |
| `MICELIO_GRPC_TLS_CERTFILE` | No | — | Path to TLS certificate file |
| `MICELIO_GRPC_TLS_KEYFILE` | No | — | Path to TLS private key file |
| `MICELIO_GRPC_TLS_CACERTFILE` | No | — | Path to CA certificate file |
| `MICELIO_GRPC_TLS_CERT_PEM` | No | — | Inline TLS certificate PEM content, used when cert files cannot be mounted (e.g. Kamal secrets) |
| `MICELIO_GRPC_TLS_KEY_PEM` | No | — | Inline TLS private key PEM content, used when key files cannot be mounted |

## OAuth Providers

### GitHub

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_GITHUB_OAUTH_CLIENT_ID` | No | — | GitHub OAuth app client ID |
| `MICELIO_GITHUB_OAUTH_CLIENT_SECRET` | No | — | GitHub OAuth app client secret |
| `MICELIO_GITHUB_OAUTH_REDIRECT_URI` | No | — | OAuth callback URL |

### GitLab

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_GITLAB_OAUTH_CLIENT_ID` | No | — | GitLab OAuth app client ID |
| `MICELIO_GITLAB_OAUTH_CLIENT_SECRET` | No | — | GitLab OAuth app client secret |
| `MICELIO_GITLAB_OAUTH_REDIRECT_URI` | No | — | OAuth callback URL |
| `MICELIO_GITLAB_OAUTH_SCOPE` | No | — | Requested OAuth scopes |

> [!NOTE]
> In development, `_DEV` suffixed variants (e.g. `MICELIO_GITHUB_OAUTH_CLIENT_ID_DEV`) take priority over the base variable name.

## Email (SMTP)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_SMTP_HOST` | Yes (prod) | — | SMTP server hostname |
| `MICELIO_SMTP_USERNAME` | Yes (prod) | — | SMTP username |
| `MICELIO_SMTP_PASSWORD` | Yes (prod) | — | SMTP password |
| `MICELIO_SMTP_PORT` | No | `587` | SMTP port |
| `MICELIO_SMTP_SSL` | No | `false` | Enable SSL for SMTP |
| `MICELIO_SMTP_TLS` | No | `if_available` | TLS mode: `true`/`always`, `if_available`, `false`/`never` |
| `MICELIO_SMTP_FROM_EMAIL` | No | `noreply@micelio.dev` | Sender email address |
| `MICELIO_SMTP_FROM_NAME` | No | `Micelio` | Sender display name |
| `MICELIO_SMTP_TLS_VERIFY` | No | `true` | Enable TLS certificate verification |
| `MICELIO_SMTP_TLS_CA_CERTS_PATH` | No | system | Path to CA certificates file |
| `MICELIO_SMTP_TLS_SERVER_NAME` | No | `MICELIO_SMTP_HOST` | TLS server name for SNI |

## Observability

Micelio integrates with the [Grafana](https://grafana.com/) observability ecosystem. Traces are exported via [OpenTelemetry](https://opentelemetry.io/) to [Tempo](https://grafana.com/oss/tempo/), metrics are exposed as a [Prometheus](https://prometheus.io/)-compatible endpoint, and logs are pushed directly to [Loki](https://grafana.com/oss/loki/) via its HTTP API. [Grafana Alloy](https://grafana.com/oss/alloy/) acts as the collector that receives OTLP trace data and forwards it to Tempo.

### Traces

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_OTEL_EXPORTER_OTLP_ENDPOINT` | No | `http://micelio-alloy:4317` | OTLP collector endpoint |
| `MICELIO_OTEL_EXPORTER_OTLP_PROTOCOL` | No | `grpc` | Protocol: `grpc` or `http_protobuf` |
| `MICELIO_OTEL_SERVICE_NAME` | No | `micelio-web` | Service name in traces |
| `MICELIO_OTEL_DEPLOYMENT_ENVIRONMENT` | No | `production` | Deployment environment label |

### Metrics

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_METRICS_BEARER_TOKEN` | Yes (prod) | — | Bearer token for the `/metrics` endpoint |

### Logs

Micelio pushes logs directly to Loki via its HTTP API. Set `MICELIO_LOKI_HOST` to enable.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MICELIO_LOKI_HOST` | No | — | Loki endpoint (e.g. `http://micelio-loki:3100`). Enables log shipping |
| `MICELIO_LOKI_LABELS` | No | `app=micelio,environment=prod` | Comma-separated `key=value` stream labels |
| `MICELIO_LOKI_BATCH_SIZE` | No | `100` | Entries buffered before pushing |

## Error Tracking

Micelio has a built-in error tracking system that captures exceptions, agent crashes, and LiveView errors into PostgreSQL. Errors are deduplicated by fingerprint within a configurable time window so repeated failures don't flood the database. The admin dashboard at `/admin/errors` lets you browse, filter, resolve, and get notified about errors via email or webhooks. Retention policies automatically clean up old errors.

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
