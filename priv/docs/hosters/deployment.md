%{
  title: "Deployment",
  description: "Minimal production setup for Micelio with gRPC enabled."
}
---

This guide covers the minimal production setup for Micelio with gRPC enabled.

## Required Services

- SQLite (local file)
- Object storage (local path or S3-compatible)

## Environment Variables

### Core

- `SECRET_KEY_BASE`
- `PHX_HOST`
- `PORT` (default: `4000`)

### Storage

- `STORAGE_BACKEND` (`local` or `s3`)
- `STORAGE_LOCAL_PATH` (defaults to `/var/micelio/storage` in prod)
- `S3_BUCKET` (required for `s3`)
- `S3_REGION` (default: `us-east-1`)
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`

**Production:** `STORAGE_BACKEND` must be `s3`.

### gRPC (TLS required)

- `MICELIO_GRPC_ENABLED` (`true` to enable)
- `MICELIO_GRPC_PORT` (default: `50051`)
- `MICELIO_GRPC_TLS_CERTFILE`
- `MICELIO_GRPC_TLS_KEYFILE`
- `MICELIO_GRPC_TLS_CACERTFILE` (optional, for mTLS)

### Database

- `DATABASE_PATH` (default: `/var/micelio/micelio.sqlite3`)
- `POOL_SIZE` (default: `10`)

## Notes

- gRPC refuses to start without TLS configured.
- SQLite is used for auth and metadata; object storage holds sessions and blobs.
- In production, gRPC calls require a valid OAuth access token via `authorization: Bearer <token>`.
