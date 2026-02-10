defmodule Micelio.Accounts.AuthEmail do
  @moduledoc """
  Email templates for authentication.
  """

  import Swoosh.Email

  @from {"Micelio", "noreply@micelio.dev"}

  @doc """
  Builds the magic link login email.
  """
  def login_email(user, login_url) do
    new()
    |> to(user.email)
    |> from(@from)
    |> subject("Sign in to Micelio")
    |> html_body(login_html(login_url))
    |> text_body(login_text(login_url))
  end

  defp login_html(url) do
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
          max-width: 600px;
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
        .link {
          color: #000000;
        }
        .mono {
          font-family: ui-monospace, monospace;
          font-size: 16px;
          color: #666666;
          word-break: break-all;
        }
        .muted {
          color: #999999;
          margin-top: 32px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <p class="title">Sign in to Micelio</p>
        <p>Click the link below to sign in. This link expires in 15 minutes.</p>
        <p><a href="#{url}" class="link">#{url}</a></p>
        <p class="muted">If you did not request this email, you can ignore it.</p>
      </div>
    </body>
    </html>
    """
  end

  defp login_text(url) do
    """
    Sign in to Micelio

    Click the link below to sign in to your account. This link will expire in 15 minutes.

    #{url}

    If you didn't request this email, you can safely ignore it.
    """
  end
end
