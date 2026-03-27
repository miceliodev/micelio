defmodule Micelio.Errors.Config do
  @moduledoc false

  def external_sentry_enabled?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:external_sentry_enabled, false)
  end

  def retention_days(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_days, 90)
  end

  def resolved_retention_days(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:resolved_retention_days, 30)
  end

  def unresolved_retention_days(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:unresolved_retention_days, 90)
  end

  def retention_archive_enabled?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_archive_enabled, false)
  end

  def retention_archive_prefix(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_archive_prefix, "errors/archives")
  end

  def retention_vacuum_enabled?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_vacuum_enabled, true)
  end

  def retention_table_warn_threshold(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_table_warn_threshold, 100_000)
  end

  def retention_oban_enabled?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:retention_oban_enabled, false)
  end

  def capture_enabled?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:capture_enabled, true)
  end

  def capture_async?(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:capture_async, true)
  end

  def dedupe_window_seconds(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:dedupe_window_seconds, 300)
  end

  def capture_rate_limit_per_kind_per_minute(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:capture_rate_limit_per_kind_per_minute, 100)
  end

  def capture_rate_limit_total_per_minute(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:capture_rate_limit_total_per_minute, 1000)
  end

  def sampling_after_occurrences(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:sampling_after_occurrences, 100)
  end

  def sampling_rate(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:sampling_rate, 0.1)
  end

  def notification_threshold_count(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:notification_threshold_count, 10)
  end

  def notification_threshold_window_seconds(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:notification_threshold_window_seconds, 300)
  end

  def notification_fingerprint_rate_limit_seconds(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:notification_fingerprint_rate_limit_seconds, 3600)
  end

  def notification_total_rate_limit_seconds(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:notification_total_rate_limit_seconds, 3600)
  end

  def notification_total_rate_limit_max(opts \\ []) do
    errors_config(opts)
    |> Keyword.get(:notification_total_rate_limit_max, 10)
  end

  defp errors_config(opts) do
    opts
    |> Keyword.get(:errors, Application.get_env(:micelio, :errors, []))
    |> normalize_errors_config()
  end

  defp normalize_errors_config(nil), do: []
  defp normalize_errors_config(errors) when is_list(errors), do: errors
  defp normalize_errors_config(errors) when is_map(errors), do: Enum.to_list(errors)
  defp normalize_errors_config(_errors), do: []
end
