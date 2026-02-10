defmodule Micelio.Storage.S3ValidationRateLimitTest do
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.Storage

  defmodule Validator do
    def validate(_config, _opts \\ []) do
      {:ok, %{ok?: true, errors: [], steps: %{}}}
    end
  end

  test "rate limits repeated validation attempts" do
    unique = Ecto.UUID.generate()
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-rate-#{unique}@example.com")

    params = s3_params("micelio-rate-bucket")

    assert {:ok, %{ok?: true}} =
             Storage.validate_user_s3_config(user, params,
               validator: Validator,
               rate_limit: [limit: 1, window_ms: 60_000]
             )

    assert {:error, %{errors: [message]}} =
             Storage.validate_user_s3_config(user, params,
               validator: Validator,
               rate_limit: [limit: 1, window_ms: 60_000]
             )

    assert message == "Validation rate limit exceeded. Please try again later."
  end

  test "rate limits validation during S3 config upsert" do
    unique = Ecto.UUID.generate()

    {:ok, user} =
      Accounts.get_or_create_user_by_email("storage-upsert-rate-#{unique}@example.com")

    params = s3_params("micelio-upsert-bucket")

    assert {:ok, _config, {:ok, %{ok?: true}}} =
             Storage.upsert_user_s3_config(user, params,
               validator: Validator,
               rate_limit: [limit: 1, window_ms: 60_000]
             )

    assert {:ok, config, {:error, %{errors: [message]}}} =
             Storage.upsert_user_s3_config(user, params,
               validator: Validator,
               rate_limit: [limit: 1, window_ms: 60_000]
             )

    assert message == "Validation rate limit exceeded. Please try again later."
    assert config.last_error == message
    assert is_nil(config.validated_at)
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
