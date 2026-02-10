defmodule Micelio.Storage.S3RevalidationTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Repo
  alias Micelio.Storage.{S3Config, S3Revalidation}

  defmodule SuccessValidator do
    def validate(_config), do: {:ok, %{ok?: true, errors: []}}
  end

  defmodule FailureValidator do
    def validate(_config), do: {:error, %{ok?: false, errors: ["Access denied."]}}
  end

  test "updates validated_at and clears last_error on success" do
    user = user_fixture()
    config = s3_config_fixture(user, %{validated_at: nil, last_error: "stale"})

    assert config.validated_at == nil
    assert config.last_error == "stale"

    S3Revalidation.run(validator: SuccessValidator)

    updated = Repo.get!(S3Config, config.id)
    assert updated.validated_at != nil
    assert updated.last_error == nil
  end

  test "marks config invalid on validation failure" do
    user = user_fixture()
    config = s3_config_fixture(user, %{validated_at: DateTime.utc_now(), last_error: nil})

    S3Revalidation.run(validator: FailureValidator)

    updated = Repo.get!(S3Config, config.id)
    assert updated.validated_at == nil
    assert updated.last_error =~ "Access denied."
  end

  defp user_fixture do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email())
    user
  end

  defp unique_email do
    "s3-revalidation-#{System.unique_integer([:positive])}@example.com"
  end

  defp s3_config_fixture(user, overrides) do
    attrs =
      %{
        user_id: user.id,
        provider: :aws_s3,
        bucket_name: "revalidation-bucket",
        region: "us-east-1",
        endpoint_url: "https://s3.us-east-1.amazonaws.com",
        access_key_id: "access-key",
        secret_access_key: "secret-key",
        path_prefix: nil,
        validated_at: nil,
        last_error: nil
      }
      |> Map.merge(overrides)

    Repo.insert!(S3Config.changeset(%S3Config{}, attrs))
  end
end
