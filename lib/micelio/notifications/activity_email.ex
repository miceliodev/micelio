defmodule Micelio.Notifications.ActivityEmail do
  @moduledoc """
  Email templates for repository activity.
  """

  import Swoosh.Email

  alias Micelio.Repositories.Repository
  alias Micelio.Sessions.Session

  @doc """
  Builds a session landed notification email.
  """
  def session_landed_email(recipient, %Repository{} = repository, %Session{} = session) do
    org_handle = repository.organization.account.handle
    repo_handle = repository.handle
    repo_name = repository.name
    session_goal = session.goal || "Session landed"
    actor_email = session.user.email
    repo_url = build_url("/#{org_handle}/#{repo_handle}")
    session_url = build_url("/#{org_handle}/#{repo_handle}/sessions/#{session.id}")

    new()
    |> to(recipient.email)
    |> from(default_from())
    |> subject("[#{org_handle}/#{repo_handle}] #{session_goal}")
    |> html_body(
      session_landed_html(%{
        repo_name: repo_name,
        org_handle: org_handle,
        repo_handle: repo_handle,
        session_goal: session_goal,
        actor_email: actor_email,
        repo_url: repo_url,
        session_url: session_url
      })
    )
    |> text_body(
      session_landed_text(%{
        repo_name: repo_name,
        org_handle: org_handle,
        repo_handle: repo_handle,
        session_goal: session_goal,
        actor_email: actor_email,
        repo_url: repo_url,
        session_url: session_url
      })
    )
  end

  @doc """
  Builds a repository starred notification email.
  """
  def repository_starred_email(recipient, %Repository{} = repository, actor) do
    org_handle = repository.organization.account.handle
    repo_handle = repository.handle
    repo_name = repository.name
    actor_email = Map.get(actor, :email) || "Someone"
    repo_url = build_url("/#{org_handle}/#{repo_handle}")

    new()
    |> to(recipient.email)
    |> from(default_from())
    |> subject("[#{org_handle}/#{repo_handle}] Repository starred")
    |> html_body(
      repository_starred_html(%{
        repo_name: repo_name,
        org_handle: org_handle,
        repo_handle: repo_handle,
        actor_email: actor_email,
        repo_url: repo_url
      })
    )
    |> text_body(
      repository_starred_text(%{
        repo_name: repo_name,
        org_handle: org_handle,
        repo_handle: repo_handle,
        actor_email: actor_email,
        repo_url: repo_url
      })
    )
  end

  defp default_from do
    Application.get_env(:micelio, Micelio.Mailer, [])
    |> Keyword.get(:from, {"Micelio", "noreply@micelio.dev"})
  end

  defp build_url(path) do
    base = MicelioWeb.Endpoint.url()
    base <> path
  end

  defp session_landed_html(assigns) do
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
        .muted {
          color: #999999;
          margin-top: 32px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <p class="title">#{assigns.org_handle}/#{assigns.repo_handle} activity</p>
        <p>
          #{assigns.actor_email} landed a session in #{assigns.repo_name}.
        </p>
        <p>
          <strong>Goal:</strong> #{assigns.session_goal}
        </p>
        <p>
          <a href="#{assigns.session_url}" class="link">View session</a> ·
          <a href="#{assigns.repo_url}" class="link">Open repository</a>
        </p>
        <p class="muted">You are receiving this email because you are a member of this organization.</p>
      </div>
    </body>
    </html>
    """
  end

  defp session_landed_text(assigns) do
    """
    #{assigns.org_handle}/#{assigns.repo_handle} activity

    #{assigns.actor_email} landed a session in #{assigns.repo_name}.
    Goal: #{assigns.session_goal}

    View session: #{assigns.session_url}
    Open repository: #{assigns.repo_url}

    You are receiving this email because you are a member of this organization.
    """
  end

  defp repository_starred_html(assigns) do
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
        .muted {
          color: #999999;
          margin-top: 32px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <p class="title">#{assigns.org_handle}/#{assigns.repo_handle} activity</p>
        <p>
          #{assigns.actor_email} starred #{assigns.repo_name}.
        </p>
        <p>
          <a href="#{assigns.repo_url}" class="link">Open repository</a>
        </p>
        <p class="muted">You are receiving this email because you are a member of this organization.</p>
      </div>
    </body>
    </html>
    """
  end

  defp repository_starred_text(assigns) do
    """
    #{assigns.org_handle}/#{assigns.repo_handle} activity

    #{assigns.actor_email} starred #{assigns.repo_name}.

    Open repository: #{assigns.repo_url}

    You are receiving this email because you are a member of this organization.
    """
  end
end
