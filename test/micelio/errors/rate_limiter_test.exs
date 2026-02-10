defmodule Micelio.Errors.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Micelio.Errors.RateLimiter

  setup do
    errors_config = [
      capture_rate_limit_per_kind_per_minute: 2,
      capture_rate_limit_total_per_minute: 3
    ]

    start_supervised!(RateLimiter)

    RateLimiter.reset!()

    on_exit(fn ->
      RateLimiter.reset!()
    end)

    {:ok, errors_config: errors_config}
  end

  test "enforces per-kind limits", %{errors_config: errors_config} do
    assert RateLimiter.allow?(:exception, errors: errors_config)
    assert RateLimiter.allow?(:exception, errors: errors_config)
    refute RateLimiter.allow?(:exception, errors: errors_config)
  end

  test "enforces total limits across kinds", %{errors_config: errors_config} do
    assert RateLimiter.allow?(:exception, errors: errors_config)
    assert RateLimiter.allow?(:plug_error, errors: errors_config)
    assert RateLimiter.allow?(:exception, errors: errors_config)
    refute RateLimiter.allow?(:liveview_crash, errors: errors_config)
  end
end
