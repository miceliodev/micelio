defmodule Micelio.Docs.StorageSecurityDocTest do
  use ExUnit.Case, async: true

  test "storage security documentation includes IAM guidance and checklist" do
    path = Path.expand("../../docs/users/storage-security.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(contents, "# Storage Security and IAM Policies")
    assert String.contains?(contents, "AWS S3 (minimal policy)")
    assert String.contains?(contents, "Cloudflare R2")
    assert String.contains?(contents, "MinIO (bucket policy)")
    assert String.contains?(contents, "Encryption requirements")
    assert String.contains?(contents, "Security checklist")
    assert String.contains?(contents, "rate limits validation attempts")
    assert String.contains?(contents, "storage.s3_config.created")
    assert String.contains?(contents, "storage.s3_config.updated")
    assert String.contains?(contents, "storage.s3_config.deleted")
  end
end
