defmodule Micelio.Storage.S3ConfigTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Repo
  alias Micelio.Storage.S3Config

  test "changeset requires core fields" do
    changeset = S3Config.changeset(%S3Config{}, %{})
    errors = errors_on(changeset)

    assert "can't be blank" in errors.user_id
    assert "can't be blank" in errors.provider
    assert "can't be blank" in errors.bucket_name
    assert "can't be blank" in errors.access_key_id
    assert "can't be blank" in errors.secret_access_key
  end

  test "region is required for AWS-style providers" do
    user = user_fixture()

    attrs =
      valid_attrs(user.id, %{
        provider: :aws_s3,
        region: nil
      })

    changeset = S3Config.changeset(%S3Config{}, attrs)

    assert "can't be blank" in errors_on(changeset).region
  end

  test "endpoint_url is required for non-AWS providers" do
    user = user_fixture()

    attrs =
      valid_attrs(user.id, %{
        provider: :cloudflare_r2,
        region: nil,
        endpoint_url: nil
      })

    changeset = S3Config.changeset(%S3Config{}, attrs)

    assert "can't be blank" in errors_on(changeset).endpoint_url
  end

  test "unique constraint prevents multiple configs per user" do
    user = user_fixture()
    attrs = valid_attrs(user.id)

    assert {:ok, _config} = Repo.insert(S3Config.changeset(%S3Config{}, attrs))
    assert {:error, changeset} = Repo.insert(S3Config.changeset(%S3Config{}, attrs))
    assert "has already been taken" in errors_on(changeset).user_id
  end

  test "credentials are encrypted at rest and redacted" do
    user = user_fixture()
    attrs = valid_attrs(user.id)

    assert {:ok, config} = Repo.insert(S3Config.changeset(%S3Config{}, attrs))
    assert config.access_key_id == "access-key"
    assert config.secret_access_key == "secret-key"

    {:ok, uuid_binary} = Ecto.UUID.dump(config.id)

    %{rows: [[stored_access_key_id, stored_secret_access_key]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT access_key_id, secret_access_key FROM s3_configs WHERE id = $1",
        [uuid_binary]
      )

    refute stored_access_key_id == "access-key"
    refute stored_secret_access_key == "secret-key"
    refute inspect(config) =~ "access-key"
    refute inspect(config) =~ "secret-key"
  end

  defp user_fixture do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email())
    user
  end

  defp unique_email do
    "s3-config-#{System.unique_integer([:positive])}@example.com"
  end

  defp valid_attrs(user_id, overrides \\ %{}) do
    base = %{
      user_id: user_id,
      provider: :aws_s3,
      bucket_name: "micelio-bucket",
      region: "us-east-1",
      endpoint_url: nil,
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      path_prefix: "agents/"
    }

    Map.merge(base, overrides)
  end
end
