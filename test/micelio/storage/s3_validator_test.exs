defmodule Micelio.Storage.S3ValidatorTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Micelio.Storage.{S3Config, S3Validator}

  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    :ok
  end

  setup do
    if :ets.info(:micelio_s3_validator_cache) != :undefined do
      :ets.delete(:micelio_s3_validator_cache)
    end

    :ok
  end

  test "validates credentials and permissions" do
    config = base_config()

    expect(Req, :request, 4, fn opts ->
      case opts[:method] do
        :head ->
          {:ok, %{status: 200, body: ""}}

        :put ->
          assert opts[:body] == "micelio-storage-validation"
          {:ok, %{status: 200, body: ""}}

        :get ->
          {:ok, %{status: 200, body: "micelio-storage-validation"}}

        :delete ->
          {:ok, %{status: 204, body: ""}}
      end
    end)

    assert {:ok, result} =
             S3Validator.validate(config,
               retry_backoff_ms: 0,
               cache_ttl_ms: 60_000
             )

    assert result.ok?
    assert result.errors == []
  end

  test "returns endpoint error without issuing requests" do
    config = %{base_config() | endpoint_url: "not-a-url"}

    assert {:error, result} = S3Validator.validate(config)
    assert result.ok? == false
    assert "Endpoint URL must include http(s) scheme and host." in result.errors
  end

  test "uses cached validation results" do
    config = base_config()

    expect(Req, :request, 4, fn opts ->
      case opts[:method] do
        :head -> {:ok, %{status: 200, body: ""}}
        :put -> {:ok, %{status: 200, body: ""}}
        :get -> {:ok, %{status: 200, body: "micelio-storage-validation"}}
        :delete -> {:ok, %{status: 204, body: ""}}
      end
    end)

    assert {:ok, result} =
             S3Validator.validate(config,
               retry_backoff_ms: 0,
               cache_ttl_ms: 60_000
             )

    assert result.ok?

    assert {:ok, cached} =
             S3Validator.validate(config,
               retry_backoff_ms: 0,
               cache_ttl_ms: 60_000
             )

    assert cached == result
  end

  test "records successful steps before a failure" do
    config = base_config()

    expect(Req, :request, 1, fn opts ->
      assert opts[:method] == :head
      {:ok, %{status: 404, body: ""}}
    end)

    assert {:error, result} =
             S3Validator.validate(config,
               retry_backoff_ms: 0,
               cache_ttl_ms: 60_000
             )

    assert result.steps[:endpoint] == :ok
    assert {:error, "Bucket not found."} = result.steps[:bucket]
    refute Map.has_key?(result.steps, :write)
  end

  defp base_config do
    %S3Config{
      provider: :aws_s3,
      bucket_name: "test-bucket",
      region: "us-east-1",
      endpoint_url: "https://s3.us-east-1.amazonaws.com",
      access_key_id: "test-access-key",
      secret_access_key: "test-secret-key",
      path_prefix: nil
    }
  end
end
