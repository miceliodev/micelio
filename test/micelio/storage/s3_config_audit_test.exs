defmodule Micelio.Storage.S3ConfigAuditTest do
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.AuditLog
  alias Micelio.Repo
  alias Micelio.Storage

  defmodule Validator do
    def validate(_config, _opts \\ []) do
      {:ok, %{ok?: true, errors: [], steps: %{}}}
    end
  end

  test "logs audit entries for S3 config changes" do
    unique = Ecto.UUID.generate()
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-audit-#{unique}@example.com")

    params = s3_params("micelio-audit-bucket")

    assert {:ok, config, {:ok, _result}} =
             Storage.upsert_user_s3_config(user, params, validator: Validator, rate_limit: false)

    log = Repo.get_by(AuditLog, action: "storage.s3_config.created", user_id: user.id)
    assert log
    assert log.metadata["bucket_name"] == config.bucket_name
    assert log.metadata["provider"] == "aws_s3"
    assert log.metadata["region"] == "us-east-1"
    assert log.metadata["endpoint_url"] == "https://s3.us-east-1.amazonaws.com"
    assert log.metadata["path_prefix"] in [nil, ""]
    refute Map.has_key?(log.metadata, "access_key_id")

    updated_params = s3_params("micelio-audit-updated")

    assert {:ok, _updated, {:ok, _result}} =
             Storage.upsert_user_s3_config(user, updated_params,
               validator: Validator,
               rate_limit: false
             )

    log = Repo.get_by(AuditLog, action: "storage.s3_config.updated", user_id: user.id)
    assert log
    assert log.metadata["bucket_name"] == "micelio-audit-updated"
    assert log.metadata["provider"] == "aws_s3"

    assert {:ok, _deleted} = Storage.delete_user_s3_config(user)

    log = Repo.get_by(AuditLog, action: "storage.s3_config.deleted", user_id: user.id)
    assert log
    assert log.metadata["bucket_name"] == "micelio-audit-updated"
  end

  defp s3_params(bucket_name) do
    %{
      "provider" => "aws_s3",
      "bucket_name" => bucket_name,
      "region" => "us-east-1",
      "endpoint_url" => "https://s3.us-east-1.amazonaws.com",
      "access_key_id" => "test-access",
      "secret_access_key" => "test-secret",
      "path_prefix" => ""
    }
  end
end
