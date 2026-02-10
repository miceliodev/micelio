%{
  title: "Storage Security and IAM Policies",
  description: "Configure personal S3-compatible storage for Micelio."
}
---

Use this guide when configuring personal S3-compatible storage for Micelio.

## Recommended IAM policies

### AWS S3 (minimal policy)

Replace `<bucket-name>` and `<optional-prefix>` as needed.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::<bucket-name>"
    },
    {
      "Sid": "BucketObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<bucket-name>/<optional-prefix>*"
    }
  ]
}
```

If you do not use a prefix, remove `<optional-prefix>` and keep the trailing `*`.

### Cloudflare R2

- Create an API token with `Object Read` and `Object Write` permissions.
- If you need deletion, include `Object Delete` as well.
- Scope the token to the bucket used by Micelio.

### MinIO (bucket policy)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::<bucket-name>"]
    },
    {
      "Sid": "BucketObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::<bucket-name>/<optional-prefix>*"]
    }
  ]
}
```

MinIO policies use the same action names as AWS S3.

## Encryption requirements

- Micelio stores S3 credentials encrypted at rest using Cloak.
- Use HTTPS endpoints to keep credentials encrypted in transit.
- Enable server-side encryption on your bucket (SSE-S3 or SSE-KMS) for stored data.

## Security checklist

- Use dedicated credentials (avoid root/admin keys).
- Enable bucket versioning for data recovery.
- Configure lifecycle policies to control costs.
- Disable public access on the bucket.
- Rotate access keys on a regular schedule.
- Limit access to a single bucket and optional prefix.

## Validation and audit logging

- Micelio rate limits validation attempts to reduce credential stuffing risk (default: 10 per minute per user, configurable via `s3_validation_rate_limit`).
- S3 configuration changes are recorded in audit logs for traceability (actions: `storage.s3_config.created`, `storage.s3_config.updated`, `storage.s3_config.deleted`).
