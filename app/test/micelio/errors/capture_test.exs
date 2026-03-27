defmodule Micelio.Errors.CaptureTest do
  use Micelio.DataCase, async: false

  import ExUnit.CaptureLog

  alias Micelio.Errors.Capture
  alias Micelio.Errors.Error
  alias Micelio.Errors.RateLimiter
  alias Micelio.Repo

  setup do
    errors_config = [
      capture_enabled: true,
      dedupe_window_seconds: 300,
      capture_rate_limit_per_kind_per_minute: 1000,
      capture_rate_limit_total_per_minute: 1000,
      sampling_after_occurrences: 1000,
      sampling_rate: 1.0
    ]

    start_supervised!(RateLimiter)

    RateLimiter.reset!()

    on_exit(fn ->
      RateLimiter.reset!()
    end)

    {:ok, errors_config: errors_config}
  end

  test "capture_message/3 persists a new error with fingerprint", %{
    errors_config: errors_config
  } do
    assert {:ok, %Error{} = error} =
             Capture.capture_message("boom", :error,
               kind: :exception,
               metadata: %{source: "test"},
               async: false,
               errors: errors_config
             )

    assert error.message == "boom"
    assert error.kind == :exception
    assert error.fingerprint != nil
  end

  test "capture_exception/2 stores stacktrace", %{errors_config: errors_config} do
    {:ok, %Error{} = error} =
      try do
        raise "crash"
      rescue
        exception ->
          Capture.capture_exception(exception,
            stacktrace: __STACKTRACE__,
            async: false,
            errors: errors_config
          )
      end

    assert error.stacktrace =~ "capture_exception"
  end

  test "capture_message/3 deduplicates within window", %{errors_config: errors_config} do
    assert {:ok, %Error{} = first} =
             Capture.capture_message("failure 123", :error,
               kind: :exception,
               async: false,
               errors: errors_config
             )

    assert {:ok, %Error{} = _second} =
             Capture.capture_message("failure 456", :error,
               kind: :exception,
               async: false,
               errors: errors_config
             )

    assert Repo.aggregate(Error, :count) == 1
    assert Repo.get(Error, first.id).occurrence_count == 2
  end

  test "capture_exception/2 fingerprints include exception module", %{
    errors_config: errors_config
  } do
    {:ok, %Error{} = runtime_error} =
      try do
        raise RuntimeError, message: "boom"
      rescue
        exception ->
          Capture.capture_exception(exception,
            stacktrace: __STACKTRACE__,
            async: false,
            errors: errors_config
          )
      end

    {:ok, %Error{} = argument_error} =
      try do
        raise ArgumentError, message: "boom"
      rescue
        exception ->
          Capture.capture_exception(exception,
            stacktrace: __STACKTRACE__,
            async: false,
            errors: errors_config
          )
      end

    assert runtime_error.fingerprint != argument_error.fingerprint
    assert Repo.aggregate(Error, :count) == 2
  end

  test "capture_message/3 drops errors that exceed rate limits" do
    errors_config = [
      capture_enabled: true,
      dedupe_window_seconds: 300,
      capture_rate_limit_per_kind_per_minute: 1,
      capture_rate_limit_total_per_minute: 1,
      sampling_after_occurrences: 1000,
      sampling_rate: 1.0
    ]

    RateLimiter.reset!()

    {result, _log} =
      with_log(fn ->
        assert {:ok, %Error{}} =
                 Capture.capture_message("rate-limited", :error,
                   async: false,
                   errors: errors_config
                 )

        Capture.capture_message("rate-limited", :error,
          async: false,
          errors: errors_config
        )
      end)

    assert result == :ok
    assert Repo.aggregate(Error, :count) == 1
  end

  test "capture_message/3 samples after threshold" do
    errors_config = [
      capture_enabled: true,
      dedupe_window_seconds: 300,
      capture_rate_limit_per_kind_per_minute: 1000,
      capture_rate_limit_total_per_minute: 1000,
      sampling_after_occurrences: 1,
      sampling_rate: 0.0
    ]

    RateLimiter.reset!()

    assert {:ok, %Error{}} =
             Capture.capture_message("sampled", :error, async: false, errors: errors_config)

    assert :ok =
             Capture.capture_message("sampled", :error, async: false, errors: errors_config)

    assert Repo.aggregate(Error, :count) == 1
  end
end
