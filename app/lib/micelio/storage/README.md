# Micelio Storage

Session file storage abstraction with **local filesystem by default** and **S3 as opt-in**.

## Architecture

The `Micelio.Storage` module provides a unified interface for storing session files and artifacts. Backend selection is configurable, with local filesystem as the default.

### Local Storage (Default)

Files are stored in the local filesystem. Runtime configuration in `config/runtime.exs` reads:

- `STORAGE_BACKEND` — defaults to `local`
- `STORAGE_LOCAL_PATH` — optional override for where files are written

Defaults when `STORAGE_LOCAL_PATH` is unset:

- Production: `/var/micelio/storage`
- Dev/Test: `<tmp>/micelio/storage`

Example override:

```bash
STORAGE_BACKEND=local STORAGE_LOCAL_PATH=/data/micelio/storage mix phx.server
```

**Directory structure:**
```
/var/micelio/storage/
  sessions/
    <session-id>/
      files/
        <file-path>
      metadata.json
```

### S3 Storage (Opt-in)

For scalability and stateless agent workflows, configure S3:

```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio-sessions",
  s3_region: "us-east-1",
  s3_access_key_id: "your-access-key",      # Optional if using IAM roles
  s3_secret_access_key: "your-secret-key"   # Optional if using IAM roles
```

**Environment variables (production):**
```bash
STORAGE_BACKEND=s3
S3_BUCKET=your-bucket-name
S3_REGION=us-east-1

# Option 1: Use IAM roles (recommended for EC2/ECS)
# No additional variables needed

# Option 2: Explicit credentials
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Option 3: S3-compatible services (MinIO, DigitalOcean Spaces, etc.)
S3_ENDPOINT=https://nyc3.digitaloceanspaces.com
```

### Tiered Cache Storage (RAM -> SSD -> CDN -> Origin)

For fast reads with multiple cache tiers, enable the tiered backend. It uses:
- RAM cache via ETS
- Disk cache on local SSD
- Optional CDN for read-through cache
- Origin storage (local filesystem or S3)

Environment configuration:
```bash
STORAGE_BACKEND=tiered
STORAGE_ORIGIN_BACKEND=s3            # or local (defaults based on S3_BUCKET)
STORAGE_LOCAL_PATH=/var/micelio/storage
STORAGE_CACHE_PATH=/var/micelio/cache
STORAGE_CACHE_MEMORY_MAX_BYTES=64000000
STORAGE_CDN_BASE_URL=https://cdn.example.com/micelio
STORAGE_CDN_TIMEOUT_MS=2000
```

Example application config:
```elixir
config :micelio, Micelio.Storage,
  backend: :tiered,
  origin_backend: :s3,
  cache_disk_path: "/var/micelio/cache",
  cache_memory_max_bytes: 64_000_000,
  cdn_base_url: "https://cdn.example.com/micelio",
  s3_bucket: "micelio-sessions",
  s3_region: "us-east-1"
```

## Usage

```elixir
# Store a file
{:ok, key} = Storage.put("sessions/abc123/files/main.ex", content)

# Retrieve a file
{:ok, content} = Storage.get("sessions/abc123/files/main.ex")

# Check existence
true = Storage.exists?("sessions/abc123/files/main.ex")

# List files
{:ok, files} = Storage.list("sessions/abc123/")

# Delete a file
{:ok, _} = Storage.delete("sessions/abc123/files/main.ex")
```

## Implementation

### HTTP Client: Req

The S3 backend uses [Req](https://hexdocs.pm/req/) as the HTTP client, following the project's conventions. Req provides:

- **Clean API** - Simple, composable request building
- **Excellent error handling** - Built-in retries and timeouts
- **Modern design** - Follows Elixir best practices
- **No heavy dependencies** - Lightweight compared to AWS SDK alternatives

### AWS Authentication

S3 operations use **AWS Signature Version 4** authentication, implemented natively in Elixir using:
- `:crypto` module for HMAC-SHA256 signing
- Proper canonical request formatting
- Time-based credentials scoping

**Credential loading order:**
1. Explicit application config (`:s3_access_key_id`, `:s3_secret_access_key`)
2. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
3. IAM instance profiles/roles (future enhancement)

### Content-Addressable Storage

Following the principles in `DESIGN.md`, the S3 backend supports content-addressable storage patterns:

```
S3 Bucket Structure:
├── sessions/
│   └── <session-id>/
│       ├── files/
│       │   └── <file-path>
│       └── metadata.json
├── artifacts/
│   └── sha256:<content-hash>/
│       └── <artifact-files>
└── cache/
    └── builds/sha256:<derivation-hash>/
        └── <build-outputs>
```

**Key principles:**
- **Immutable artifacts** - Content hash = storage key
- **Global deduplication** - Same content = same key across all sessions
- **Stateless agents** - No local state required, S3 is source of truth
- **Efficient caching** - Content-addressable lookups avoid redundant builds

## Performance & Scalability

### S3 Benefits
- **Unlimited storage** - No disk space constraints
- **Global availability** - Access from anywhere
- **Durability** - 99.999999999% (11 nines)
- **Scalability** - Handles millions of requests/second
- **Cost-effective** - Pay only for what you store and transfer

### Best Practices
- **Use S3 for production** - Stateless forge workers, no single point of failure
- **Use local for development** - Faster iteration, no AWS costs
- **Prefix organization** - Group related files for efficient listing
- **Content addressing** - Enable global deduplication and caching

## Testing

Comprehensive tests cover:
- ✅ All CRUD operations (put, get, delete, exists?, list)
- ✅ Error handling (network failures, S3 errors, missing objects)
- ✅ Configuration validation (credentials, bucket settings)
- ✅ AWS Signature V4 authentication
- ✅ Pagination for large list results
- ✅ Special character handling in keys
- ✅ Content-addressable storage patterns

Run tests:
```bash
mix test test/micelio/storage/s3_test.exs
```

## Security Considerations

### Credentials Management
- **Never commit credentials** to version control
- **Use IAM roles** when running on AWS (EC2, ECS, Lambda)
- **Use environment variables** for explicit credentials
- **Rotate keys regularly** following AWS best practices

### Bucket Policies
Recommended S3 bucket policy for production:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:role/micelio-app-role"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name/*",
        "arn:aws:s3:::your-bucket-name"
      ]
    }
  ]
}
```

### Recommended IAM Policies (Minimal Scope)

**AWS S3 (IAM policy scoped to a single bucket):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR_BUCKET_NAME",
        "arn:aws:s3:::YOUR_BUCKET_NAME/*"
      ]
    }
  ]
}
```

**Cloudflare R2 (API token permissions):**
- Object Read
- Object Write

**MinIO (bucket-scoped policy JSON):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR_BUCKET_NAME",
        "arn:aws:s3:::YOUR_BUCKET_NAME/*"
      ]
    }
  ]
}
```

### Encryption
- **Enable server-side encryption** (SSE-S3 or SSE-KMS)
- **Use HTTPS** for all requests (enforced by default)
- **Consider bucket versioning** for audit trails
- **S3 credentials are encrypted at rest** in the Micelio database using Cloak

### Security Checklist
- Use dedicated credentials (avoid root/admin keys)
- Enable bucket versioning for data recovery
- Configure bucket lifecycle policies for cost control
- Disable public access on the bucket
- Rotate access keys regularly and revoke unused credentials

### Operational Safeguards
- Storage validation requests are rate limited to prevent credential stuffing.
- S3 configuration changes are audit logged for traceability.

## Migration from Local to S3

To migrate existing local storage to S3:

```elixir
# 1. List all local files
{:ok, local_files} = Micelio.Storage.Local.list("")

# 2. For each file, copy to S3
Enum.each(local_files, fn key ->
  {:ok, content} = Micelio.Storage.Local.get(key)
  {:ok, _} = Micelio.Storage.S3.put(key, content)
end)

# 3. Update configuration to use S3
# config :micelio, Micelio.Storage, backend: :s3

# 4. Verify migration
{:ok, s3_files} = Micelio.Storage.S3.list("")
^local_files = s3_files
```

## S3-Compatible Services

The implementation works with S3-compatible services by setting `s3_endpoint`:

### MinIO (Self-hosted)
```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio",
  s3_region: "us-east-1",
  s3_endpoint: "http://localhost:9000"
```

### DigitalOcean Spaces
```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio-spaces",
  s3_region: "nyc3",
  s3_endpoint: "https://nyc3.digitaloceanspaces.com"
```

### Backblaze B2
```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio-b2",
  s3_region: "us-west-002",
  s3_endpoint: "https://s3.us-west-002.backblazeb2.com"
```

### Cloudflare R2
```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio-r2",
  s3_region: "auto",
  s3_endpoint: "https://ACCOUNT_ID.r2.cloudflarestorage.com"
```

## Troubleshooting

### "Missing S3 credentials" error
**Cause:** Neither config nor environment variables provide AWS credentials.

**Solution:**
```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret

# Or configure in application config
config :micelio, Micelio.Storage,
  s3_access_key_id: "your-key",
  s3_secret_access_key: "your-secret"
```

### "Missing S3 bucket" error
**Cause:** No bucket name configured.

**Solution:**
```bash
export S3_BUCKET=your-bucket-name
```

### 403 Forbidden errors
**Cause:** IAM permissions insufficient or incorrect credentials.

**Solution:** Verify IAM policy includes required S3 actions:
```json
{
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ]
}
```

### Slow list operations
**Cause:** Large number of objects in prefix.

**Solution:** 
- Use more specific prefixes to reduce result sets
- Consider indexing strategy for frequently listed paths
- Leverage pagination (automatically handled by implementation)

## Implementation Status

- ✅ **Local storage** - Fully implemented
- ✅ **S3 storage** - Fully implemented with Req
- ✅ **AWS Signature V4** - Native Elixir implementation
- ✅ **Comprehensive tests** - All operations covered
- ✅ **Error handling** - Graceful degradation and clear error messages
- ✅ **Pagination** - Automatic handling of large list results
- ✅ **S3-compatible services** - MinIO, Spaces, R2, B2 support

## Design Principles

Following `DESIGN.md`:

- **Stateless agents** - S3 as source of truth, no local coordinator needed
- **Content-addressable** - Artifacts stored by content hash for global deduplication
- **Self-hostable** - Works with any S3-compatible service
- **Scalable** - O(1) lookups, unlimited storage capacity
- **Simple** - Unified API regardless of backend

## Future Enhancements

Potential improvements (not currently prioritized):

- [ ] IAM role credential fetching for EC2/ECS
- [ ] Multipart upload for large files (>5GB)
- [ ] Presigned URLs for direct browser uploads
- [ ] CloudFront integration for CDN distribution
- [ ] Metrics and monitoring integration
- [ ] Automatic retry with exponential backoff
- [ ] Connection pooling optimization
