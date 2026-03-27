defmodule Micelio.Errors.Notifier do
  @moduledoc """
  Deliver error notifications with rate limiting and quiet hours.
  """

  import Ecto.Query, warn: false

  alias Micelio.Admin
  alias Micelio.Errors
  alias Micelio.Errors.Config
  alias Micelio.Errors.Error
  alias Micelio.Errors.NotificationEmail
  alias Micelio.Errors.NotificationLog
  alias Micelio.Errors.NotificationSettings
  alias Micelio.Mailer
  alias Micelio.Repo

  require Logger

  @default_timeout 5_000

  def maybe_notify(%Error{} = error, opts \\ []) do
    settings = Errors.get_notification_settings()
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:second)
    deduped? = Keyword.get(opts, :deduped?, false)

    reason = notification_reason(error, settings, deduped?, now)

    if reason == nil or quiet_hours?(settings, now) do
      :ok
    else
      send_notifications(error, settings, reason, now)
    end
  end

  defp notification_reason(%Error{} = error, %NotificationSettings{} = settings, deduped?, now) do
    cond do
      settings.notify_on_critical and error.severity == :critical ->
        :critical

      settings.notify_on_threshold and threshold_exceeded?(error, deduped?, now) ->
        :threshold

      settings.notify_on_new and not deduped? and severity_at_least?(error.severity, :error) ->
        :new_error

      true ->
        nil
    end
  end

  defp threshold_exceeded?(%Error{} = error, deduped?, now) do
    window_seconds = Config.notification_threshold_window_seconds()
    threshold_count = Config.notification_threshold_count()

    if deduped? and is_integer(threshold_count) and threshold_count > 0 do
      window_ok? = DateTime.diff(now, error.first_seen_at, :second) <= window_seconds
      window_ok? and error.occurrence_count >= threshold_count
    else
      false
    end
  end

  defp send_notifications(%Error{} = error, %NotificationSettings{} = settings, reason, now) do
    if rate_limited?(error.fingerprint, now) do
      :ok
    else
      channels = []
      channels = maybe_send_email(error, settings, reason, channels)
      channels = maybe_send_webhook(error, settings, reason, channels)
      channels = maybe_send_slack(error, settings, reason, channels)

      if channels == [] do
        :ok
      else
        log_notification(error, reason, channels)
        :ok
      end
    end
  end

  defp maybe_send_email(error, settings, reason, channels) do
    if settings.email_enabled do
      recipients = Admin.admin_emails()

      emails =
        Enum.map(recipients, fn email ->
          NotificationEmail.error_email(email, error, reason)
        end)

      case emails do
        [] ->
          channels

        _ ->
          case Mailer.deliver_many(emails) do
            {:ok, _} ->
              ["email" | channels]

            {:error, reason} ->
              Logger.warning("error notification email failed: #{inspect(reason)}")
              channels
          end
      end
    else
      channels
    end
  end

  defp maybe_send_webhook(error, settings, reason, channels) do
    url = settings.webhook_url

    if is_binary(url) and url != "" do
      payload = webhook_payload(error, reason)

      case Req.request(
             method: :post,
             url: url,
             headers: [{"content-type", "application/json"}, {"user-agent", "Micelio-Errors/1.0"}],
             body: Jason.encode!(payload),
             receive_timeout: @default_timeout,
             retry: false
           ) do
        {:ok, %{status: status}} when status >= 200 and status < 300 ->
          ["webhook" | channels]

        {:ok, %{status: status, body: body}} ->
          Logger.warning("error notification webhook failed: #{status} #{inspect(body)}")
          channels

        {:error, reason} ->
          Logger.warning("error notification webhook failed: #{inspect(reason)}")
          channels
      end
    else
      channels
    end
  end

  defp maybe_send_slack(error, settings, reason, channels) do
    url = settings.slack_webhook_url

    if is_binary(url) and url != "" do
      payload = slack_payload(error, reason)

      case Req.request(
             method: :post,
             url: url,
             headers: [{"content-type", "application/json"}],
             body: Jason.encode!(payload),
             receive_timeout: @default_timeout,
             retry: false
           ) do
        {:ok, %{status: status}} when status >= 200 and status < 300 ->
          ["slack" | channels]

        {:ok, %{status: status, body: body}} ->
          Logger.warning("error notification slack failed: #{status} #{inspect(body)}")
          channels

        {:error, reason} ->
          Logger.warning("error notification slack failed: #{inspect(reason)}")
          channels
      end
    else
      channels
    end
  end

  defp log_notification(%Error{} = error, reason, channels) do
    %NotificationLog{}
    |> NotificationLog.changeset(%{
      error_id: error.id,
      fingerprint: error.fingerprint,
      severity: error.severity,
      reason: reason,
      channels: Enum.reverse(channels)
    })
    |> Repo.insert()
  end

  defp rate_limited?(fingerprint, now) do
    fingerprint_limit = Config.notification_fingerprint_rate_limit_seconds()
    total_window = Config.notification_total_rate_limit_seconds()
    total_max = Config.notification_total_rate_limit_max()

    fingerprint_cutoff = DateTime.add(now, -fingerprint_limit, :second)
    total_cutoff = DateTime.add(now, -total_window, :second)

    fingerprint_count =
      NotificationLog
      |> where([n], n.fingerprint == ^fingerprint and n.inserted_at >= ^fingerprint_cutoff)
      |> Repo.aggregate(:count, :id)

    total_count =
      NotificationLog
      |> where([n], n.inserted_at >= ^total_cutoff)
      |> Repo.aggregate(:count, :id)

    fingerprint_count >= 1 or total_count >= total_max
  end

  defp quiet_hours?(%NotificationSettings{quiet_hours_enabled: false}, _now), do: false

  defp quiet_hours?(%NotificationSettings{} = settings, now) do
    hour = now.hour
    start_hour = settings.quiet_hours_start
    end_hour = settings.quiet_hours_end

    if start_hour == end_hour do
      false
    else
      if start_hour < end_hour do
        hour >= start_hour and hour < end_hour
      else
        hour >= start_hour or hour < end_hour
      end
    end
  end

  defp severity_at_least?(value, minimum) do
    index = Enum.find_index(Error.severities(), &(&1 == value)) || 0
    minimum_index = Enum.find_index(Error.severities(), &(&1 == minimum)) || 0
    index >= minimum_index
  end

  defp webhook_payload(%Error{} = error, reason) do
    %{
      id: error.id,
      fingerprint: error.fingerprint,
      kind: error.kind,
      message: error.message,
      severity: error.severity,
      occurrence_count: error.occurrence_count,
      first_seen_at: error.first_seen_at,
      occurred_at: error.occurred_at,
      reason: reason,
      admin_url: admin_error_url(error)
    }
  end

  defp slack_payload(%Error{} = error, reason) do
    url = admin_error_url(error)

    %{
      text: "#{error.severity} #{error.kind} error: #{error.message}",
      attachments: [
        %{
          color: slack_color(error.severity),
          fields: [
            %{title: "Fingerprint", value: error.fingerprint, short: true},
            %{title: "Occurrences", value: "#{error.occurrence_count}", short: true},
            %{title: "First seen", value: format_timestamp(error.first_seen_at), short: true},
            %{title: "Reason", value: Atom.to_string(reason), short: true},
            %{title: "Admin", value: url, short: false}
          ],
          ts: DateTime.to_unix(error.occurred_at)
        }
      ]
    }
  end

  defp slack_color(:critical), do: "danger"
  defp slack_color(:error), do: "warning"
  defp slack_color(_), do: "#439FE0"

  defp admin_error_url(%Error{} = error) do
    MicelioWeb.Endpoint.url() <> "/admin/errors/#{error.id}"
  end

  defp format_timestamp(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
