defmodule Micelio.ErrorsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Errors
  alias Micelio.Errors.Error
  alias Micelio.Repo

  test "create_error/1 persists required fields with defaults" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      fingerprint: "fingerprint-1",
      kind: :exception,
      message: "boom",
      severity: :error,
      occurred_at: now,
      occurrence_count: 1,
      first_seen_at: now,
      last_seen_at: now
    }

    assert {:ok, %Error{} = error} = Errors.create_error(attrs)
    assert error.fingerprint == "fingerprint-1"
    assert error.metadata == %{}
    assert error.context == %{}
  end

  test "delete_expired_errors/1 removes errors beyond retention cutoff" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old = DateTime.add(now, -40 * 86_400, :second)
    recent = DateTime.add(now, -10 * 86_400, :second)

    {:ok, old_error} =
      Errors.create_error(%{
        fingerprint: "old-fp",
        kind: :exception,
        message: "old",
        severity: :error,
        occurred_at: old,
        occurrence_count: 1,
        first_seen_at: old,
        last_seen_at: old
      })

    {:ok, recent_error} =
      Errors.create_error(%{
        fingerprint: "recent-fp",
        kind: :exception,
        message: "recent",
        severity: :error,
        occurred_at: recent,
        occurrence_count: 1,
        first_seen_at: recent,
        last_seen_at: recent
      })

    assert {1, nil} = Errors.delete_expired_errors(retention_days: 30)

    assert Repo.get(Error, old_error.id) == nil
    assert Repo.get(Error, recent_error.id) != nil
  end

  test "list_errors/1 filters by status and severity" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, unresolved_error} =
      Errors.create_error(%{
        fingerprint: "list-fp-1",
        kind: :exception,
        message: "unresolved",
        severity: :error,
        occurred_at: now,
        occurrence_count: 1,
        first_seen_at: now,
        last_seen_at: now
      })

    {:ok, _resolved_error} =
      Errors.create_error(%{
        fingerprint: "list-fp-2",
        kind: :exception,
        message: "resolved",
        severity: :warning,
        occurred_at: now,
        resolved_at: now,
        occurrence_count: 1,
        first_seen_at: now,
        last_seen_at: now
      })

    result = Errors.list_errors(filters: %{"status" => "unresolved"})

    assert Enum.any?(result.errors, &(&1.id == unresolved_error.id))
    refute Enum.any?(result.errors, &(&1.message == "resolved"))

    result = Errors.list_errors(filters: %{"severity" => "warning"})

    assert Enum.any?(result.errors, &(&1.message == "resolved"))
    refute Enum.any?(result.errors, &(&1.message == "unresolved"))
  end

  test "resolve_error/3 stores resolution note metadata" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, user} = Accounts.get_or_create_user_by_email("error-admin@example.com")

    {:ok, error} =
      Errors.create_error(%{
        fingerprint: "resolve-fp-1",
        kind: :exception,
        message: "needs resolution",
        severity: :error,
        occurred_at: now,
        occurrence_count: 1,
        first_seen_at: now,
        last_seen_at: now
      })

    {:ok, updated} = Errors.resolve_error(error, user.id, "Investigated and fixed.")

    assert updated.resolved_by_id == user.id
    assert updated.metadata["resolution_note"] == "Investigated and fixed."
    assert updated.resolved_at != nil
  end

  test "resolve_similar_errors/3 resolves matching fingerprints" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, user} = Accounts.get_or_create_user_by_email("bulk-admin@example.com")

    {:ok, error_one} =
      Errors.create_error(%{
        fingerprint: "bulk-fp",
        kind: :exception,
        message: "bulk one",
        severity: :error,
        occurred_at: now,
        occurrence_count: 1,
        first_seen_at: now,
        last_seen_at: now
      })

    {:ok, error_two} =
      Errors.create_error(%{
        fingerprint: "bulk-fp",
        kind: :exception,
        message: "bulk two",
        severity: :error,
        occurred_at: now,
        occurrence_count: 1,
        first_seen_at: now,
        last_seen_at: now
      })

    assert {:ok, {2, _}} = Errors.resolve_similar_errors(error_one, user.id, "bulk resolved")

    assert Repo.get!(Error, error_one.id).resolved_at != nil
    assert Repo.get!(Error, error_two.id).resolved_at != nil
  end

  test "update_notification_settings/1 persists settings" do
    assert Errors.get_notification_settings().id == nil

    assert {:ok, settings} =
             Errors.update_notification_settings(%{
               email_enabled: false,
               webhook_url: "https://example.com/webhook",
               notify_on_new: false,
               quiet_hours_enabled: true,
               quiet_hours_start: 22,
               quiet_hours_end: 6
             })

    stored = Errors.get_notification_settings()

    assert stored.id == settings.id
    assert stored.email_enabled == false
    assert stored.webhook_url == "https://example.com/webhook"
    assert stored.notify_on_new == false
    assert stored.quiet_hours_enabled == true
  end

  test "retention_policy/0 uses stored retention settings" do
    assert Errors.get_retention_settings().id == nil

    assert {:ok, settings} =
             Errors.update_retention_settings(%{
               resolved_retention_days: 14,
               unresolved_retention_days: 60,
               archive_enabled: true
             })

    policy = Errors.retention_policy()

    assert policy.resolved_retention_days == settings.resolved_retention_days
    assert policy.unresolved_retention_days == settings.unresolved_retention_days
    assert policy.archive_enabled == true
    assert is_binary(policy.archive_prefix)
  end
end
