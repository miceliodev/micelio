defmodule Micelio.Errors.NotificationEmail do
  @moduledoc """
  Email templates for error notifications.
  """

  import Swoosh.Email

  alias Micelio.Errors.Error

  def error_email(recipient, %Error{} = error, reason) when is_binary(recipient) do
    url = admin_error_url(error)
    first_seen_at = format_timestamp(error.first_seen_at || error.occurred_at)

    new()
    |> to(recipient)
    |> from(default_from())
    |> subject("[Micelio] #{error.severity} #{error.kind} error")
    |> html_body(
      error_html(%{error: error, reason: reason, url: url, first_seen_at: first_seen_at})
    )
    |> text_body(
      error_text(%{error: error, reason: reason, url: url, first_seen_at: first_seen_at})
    )
  end

  defp default_from do
    Application.get_env(:micelio, Micelio.Mailer, [])
    |> Keyword.get(:from, {"Micelio", "noreply@micelio.dev"})
  end

  defp admin_error_url(%Error{} = error) do
    MicelioWeb.Endpoint.url() <> "/admin/errors/#{error.id}"
  end

  defp error_html(assigns) do
    reason = Atom.to_string(assigns.reason)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="color-scheme" content="light dark">
      <meta name="supported-color-schemes" content="light dark">
      <style>
        :root {
          color-scheme: light dark;
        }
        body {
          font-family: system-ui, -apple-system, sans-serif;
          font-size: 16px;
          line-height: 1.5;
          color: #000000;
          background-color: #ffffff;
          margin: 0;
          padding: 0;
        }
        @media (prefers-color-scheme: dark) {
          body {
            color: #f5f5f5;
            background-color: #0b0d10;
          }
          .link { color: #f5f5f5; }
          .muted { color: #8a8a8a; }
          .mono { color: #b0b0b0; }
        }
        .container {
          max-width: 640px;
          margin: 0 auto;
          padding: 32px 16px;
        }
        .title {
          font-size: 16px;
          font-weight: 600;
          margin: 0 0 16px 0;
        }
        p {
          margin: 0 0 16px 0;
        }
        .meta {
          font-family: ui-monospace, monospace;
          font-size: 14px;
          color: #666666;
          margin: 0 0 16px 0;
        }
        .link {
          color: #000000;
        }
        .muted {
          color: #999999;
          margin-top: 32px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <p class="title">#{assigns.error.severity} #{assigns.error.kind} error detected</p>
        <p>#{assigns.error.message}</p>
        <p class="meta">
          Fingerprint: #{assigns.error.fingerprint}<br>
          Occurrences: #{assigns.error.occurrence_count}<br>
          First seen: #{assigns.first_seen_at}<br>
          Reason: #{reason}
        </p>
        <p>
          <a href="#{assigns.url}" class="link">View in admin dashboard</a>
        </p>
        <p class="muted">You are receiving this alert because you are an instance administrator.</p>
      </div>
    </body>
    </html>
    """
  end

  defp error_text(assigns) do
    reason = Atom.to_string(assigns.reason)

    """
    #{assigns.error.severity} #{assigns.error.kind} error detected

    #{assigns.error.message}

    Fingerprint: #{assigns.error.fingerprint}
    Occurrences: #{assigns.error.occurrence_count}
    First seen: #{assigns.first_seen_at}
    Reason: #{reason}

    View in admin dashboard: #{assigns.url}

    You are receiving this alert because you are an instance administrator.
    """
  end

  defp format_timestamp(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
