defmodule Micelio.Errors.NotifierTest do
  use Micelio.DataCase, async: false

  import Mimic
  import Swoosh.TestAssertions

  alias Micelio.Errors
  alias Micelio.Errors.NotificationLog
  alias Micelio.Errors.Notifier
  alias Micelio.Repo

  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    :ok
  end

  defp create_error(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, error} =
      Errors.create_error(
        Map.merge(
          %{
            fingerprint: "notify-#{System.unique_integer()}",
            kind: :exception,
            message: "boom",
            severity: :error,
            occurred_at: now,
            occurrence_count: 1,
            first_seen_at: now,
            last_seen_at: now
          },
          attrs
        )
      )

    error
  end

  test "new error notifies admins via email" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: true,
        notify_on_new: true,
        notify_on_threshold: false,
        notify_on_critical: false
      })

    error = create_error()

    :ok = Notifier.maybe_notify(error, deduped?: false, now: error.occurred_at)

    assert_emails_sent([
      %{to: "admin@example.com", subject: ~r/Micelio/}
    ])
  end

  test "rate limiting blocks repeat notifications" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: true,
        notify_on_new: true,
        notify_on_threshold: false,
        notify_on_critical: false
      })

    error = create_error()

    %NotificationLog{}
    |> NotificationLog.changeset(%{
      error_id: error.id,
      fingerprint: error.fingerprint,
      severity: error.severity,
      reason: :new_error,
      channels: ["email"]
    })
    |> Repo.insert!()

    :ok = Notifier.maybe_notify(error, deduped?: false, now: error.occurred_at)

    refute_email_sent()
  end

  test "threshold notifications fire for high-frequency errors" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: true,
        notify_on_new: false,
        notify_on_threshold: true,
        notify_on_critical: false
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    error =
      create_error(%{
        occurrence_count: 10,
        first_seen_at: DateTime.add(now, -120, :second),
        last_seen_at: now
      })

    :ok = Notifier.maybe_notify(error, deduped?: true, now: now)

    assert_emails_sent([
      %{to: "admin@example.com", subject: ~r/Micelio/}
    ])
  end

  test "quiet hours suppress notifications" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: true,
        notify_on_new: true,
        notify_on_threshold: false,
        notify_on_critical: false,
        quiet_hours_enabled: true,
        quiet_hours_start: 22,
        quiet_hours_end: 6
      })

    error = create_error()
    quiet_time = DateTime.new!(Date.utc_today(), ~T[23:00:00], "Etc/UTC")

    :ok = Notifier.maybe_notify(error, deduped?: false, now: quiet_time)

    refute_email_sent()
  end

  test "critical errors notify even when deduped" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: true,
        notify_on_new: false,
        notify_on_threshold: false,
        notify_on_critical: true
      })

    error = create_error(%{severity: :critical})

    :ok = Notifier.maybe_notify(error, deduped?: true, now: error.occurred_at)

    assert_emails_sent([
      %{to: "admin@example.com", subject: ~r/critical/i}
    ])
  end

  test "webhook notifications send a payload with admin link" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: false,
        webhook_url: "https://hooks.example.com/errors",
        notify_on_new: true,
        notify_on_threshold: false,
        notify_on_critical: false
      })

    error = create_error()

    expect(Req, :request, fn opts ->
      assert opts[:method] == :post
      assert opts[:url] == "https://hooks.example.com/errors"
      assert {"content-type", "application/json"} in opts[:headers]

      payload = Jason.decode!(opts[:body])
      assert payload["message"] == "boom"
      assert payload["kind"] == "exception"
      assert payload["severity"] == "error"
      assert payload["admin_url"] =~ "/admin/errors/"
      assert payload["reason"] == "new_error"

      {:ok, %{status: 200, body: ""}}
    end)

    :ok = Notifier.maybe_notify(error, deduped?: false, now: error.occurred_at)

    assert Repo.aggregate(NotificationLog, :count, :id) == 1
  end

  test "slack notifications include fingerprint and admin link" do
    {:ok, _settings} =
      Errors.update_notification_settings(%{
        email_enabled: false,
        slack_webhook_url: "https://hooks.slack.com/services/test",
        notify_on_new: true,
        notify_on_threshold: false,
        notify_on_critical: false
      })

    error = create_error()

    expect(Req, :request, fn opts ->
      assert opts[:method] == :post
      assert opts[:url] == "https://hooks.slack.com/services/test"
      assert {"content-type", "application/json"} in opts[:headers]

      payload = Jason.decode!(opts[:body])
      assert String.contains?(payload["text"], "error")

      [attachment | _] = payload["attachments"]
      fields = attachment["fields"]
      assert Enum.any?(fields, &(&1["title"] == "Fingerprint"))
      assert Enum.any?(fields, &(&1["title"] == "Admin" and &1["value"] =~ "/admin/errors/"))

      {:ok, %{status: 200, body: ""}}
    end)

    :ok = Notifier.maybe_notify(error, deduped?: false, now: error.occurred_at)

    assert Repo.aggregate(NotificationLog, :count, :id) == 1
  end
end
