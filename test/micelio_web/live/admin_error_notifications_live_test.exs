defmodule MicelioWeb.AdminErrorNotificationsLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Errors

  test "shows notification settings form for admins", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/admin/errors/settings")

    assert html =~ "Error notifications"
    assert has_element?(view, "#admin-error-notifications-form")
    assert has_element?(view, "#admin-error-retention-form")
  end

  test "updates notification settings", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/errors/settings")

    params = %{
      "email_enabled" => "true",
      "webhook_url" => "https://example.com/hooks",
      "slack_webhook_url" => "",
      "notify_on_new" => "true",
      "notify_on_threshold" => "true",
      "notify_on_critical" => "true",
      "quiet_hours_enabled" => "true",
      "quiet_hours_start" => "22",
      "quiet_hours_end" => "6"
    }

    view
    |> form("#admin-error-notifications-form", settings: params)
    |> render_submit()

    settings = Errors.get_notification_settings()

    assert settings.email_enabled == true
    assert settings.webhook_url == "https://example.com/hooks"
    assert settings.slack_webhook_url == nil
    assert settings.notify_on_new == true
    assert settings.notify_on_threshold == true
    assert settings.notify_on_critical == true
    assert settings.quiet_hours_enabled == true
    assert settings.quiet_hours_start == 22
    assert settings.quiet_hours_end == 6
  end

  test "updates retention settings", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/errors/settings")

    params = %{
      "resolved_retention_days" => "14",
      "unresolved_retention_days" => "60",
      "archive_enabled" => "true"
    }

    view
    |> form("#admin-error-retention-form", retention: params)
    |> render_submit()

    settings = Errors.get_retention_settings()

    assert settings.resolved_retention_days == 14
    assert settings.unresolved_retention_days == 60
    assert settings.archive_enabled == true
  end
end
