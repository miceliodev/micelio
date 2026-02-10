defmodule Micelio.Errors.ConfigTest do
  use ExUnit.Case, async: true

  alias Micelio.Errors.Config

  test "external_sentry_enabled? defaults to false when unset" do
    assert Config.external_sentry_enabled?(errors: []) == false
  end

  test "external_sentry_enabled? reads the configured value" do
    assert Config.external_sentry_enabled?(errors: [external_sentry_enabled: true]) == true
  end

  test "retention_days defaults to 90 when unset" do
    assert Config.retention_days(errors: []) == 90
  end

  test "resolved_retention_days defaults to 30 when unset" do
    assert Config.resolved_retention_days(errors: []) == 30
  end

  test "unresolved_retention_days defaults to 90 when unset" do
    assert Config.unresolved_retention_days(errors: []) == 90
  end

  test "retention_days reads configured value" do
    assert Config.retention_days(errors: [retention_days: 30]) == 30
  end

  test "capture_enabled? defaults to true when unset" do
    assert Config.capture_enabled?(errors: []) == true
  end

  test "capture_enabled? reads configured value" do
    assert Config.capture_enabled?(errors: [capture_enabled: false]) == false
  end

  test "dedupe_window_seconds defaults to 300 when unset" do
    assert Config.dedupe_window_seconds(errors: []) == 300
  end

  test "capture rate limit defaults are applied when unset" do
    assert Config.capture_rate_limit_per_kind_per_minute(errors: []) == 100
    assert Config.capture_rate_limit_total_per_minute(errors: []) == 1000
  end

  test "sampling defaults are applied when unset" do
    assert Config.sampling_after_occurrences(errors: []) == 100
    assert Config.sampling_rate(errors: []) == 0.1
  end

  test "dedupe_window_seconds reads configured value" do
    assert Config.dedupe_window_seconds(errors: [dedupe_window_seconds: 120]) == 120
  end

  test "notification defaults are applied when unset" do
    assert Config.notification_threshold_count(errors: []) == 10
    assert Config.notification_threshold_window_seconds(errors: []) == 300
    assert Config.notification_fingerprint_rate_limit_seconds(errors: []) == 3600
    assert Config.notification_total_rate_limit_seconds(errors: []) == 3600
    assert Config.notification_total_rate_limit_max(errors: []) == 10
  end

  test "notification config reads configured values" do
    errors = [
      notification_threshold_count: 5,
      notification_threshold_window_seconds: 120,
      notification_fingerprint_rate_limit_seconds: 1800,
      notification_total_rate_limit_seconds: 600,
      notification_total_rate_limit_max: 2
    ]

    assert Config.notification_threshold_count(errors: errors) == 5
    assert Config.notification_threshold_window_seconds(errors: errors) == 120
    assert Config.notification_fingerprint_rate_limit_seconds(errors: errors) == 1800
    assert Config.notification_total_rate_limit_seconds(errors: errors) == 600
    assert Config.notification_total_rate_limit_max(errors: errors) == 2
  end
end
