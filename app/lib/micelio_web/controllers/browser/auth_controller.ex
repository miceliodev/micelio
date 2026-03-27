defmodule MicelioWeb.Browser.AuthController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.Accounts
  alias Micelio.Accounts.AuthEmail
  alias Micelio.Auth.GitHub
  alias Micelio.Auth.GitLab
  alias Micelio.Mailer
  alias MicelioWeb.PageMeta

  require Logger

  @doc """
  Renders the login form.
  """
  def new(conn, params) do
    email = Map.get(params, "email", "")
    form = to_form(%{"email" => email}, as: :login)
    dev_mode = Application.get_env(:micelio, :environment, :prod) == :dev

    conn
    |> PageMeta.put(
      title_parts: ["Log in"],
      description: "Log in to Micelio.",
      canonical_url: url(~p"/auth/login")
    )
    |> render(:new, form: form, dev_mode: dev_mode)
  end

  @doc """
  Handles the login form submission.
  Sends a magic link email to the user.
  """
  def create(conn, %{"login" => %{"email" => email}}) do
    handle_login(conn, email)
  end

  def create(conn, %{"email" => email}) do
    handle_login(conn, email)
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Please enter a valid email.")
    |> redirect(to: ~p"/auth/login")
  end

  defp handle_login(conn, email) do
    case Accounts.initiate_login(email) do
      {:ok, login_token} ->
        login_url = url(~p"/auth/verify/#{login_token.token}")

        email =
          login_token.user
          |> AuthEmail.login_email(login_url)

        case Mailer.deliver(email) do
          {:ok, _response} ->
            Logger.info("Login email delivered",
              user_id: login_token.user.id,
              email: login_token.user.email
            )

          {:error, reason} ->
            Logger.error(
              "Login email delivery failed",
              [user_id: login_token.user.id, email: login_token.user.email] ++
                delivery_error_metadata(reason)
            )
        end

        conn
        |> put_flash(:info, "Check your email for a login link!")
        |> redirect(to: ~p"/auth/sent")

      {:error, reason} ->
        Logger.warning("Login email initiation failed",
          email: email,
          reason: inspect(reason)
        )

        conn
        |> put_flash(:error, "Something went wrong. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Renders the "check your email" page.
  """
  def sent(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Check your email"],
      description: "We sent you a login link. Check your inbox to continue.",
      canonical_url: url(~p"/auth/sent")
    )
    |> render(:sent)
  end

  @doc """
  Logs in as the dev seed user (development only).
  """
  def dev_seed(conn, _params) do
    if Application.get_env(:micelio, :environment, :prod) == :dev do
      case Accounts.get_or_create_user_by_email("test@micelio.dev") do
        {:ok, user} ->
          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, gettext("Logged in as seed user."))
          |> redirect(to: ~p"/")

        {:error, _reason} ->
          conn
          |> put_flash(:error, gettext("Seed user not available."))
          |> redirect(to: ~p"/auth/login")
      end
    else
      conn
      |> send_resp(:not_found, "Not found")
      |> halt()
    end
  end

  @doc """
  Redirects the user to GitHub for OAuth authentication.
  """
  def github_start(conn, params) do
    state = generate_oauth_state()
    return_to = params["return_to"]

    conn =
      if is_binary(return_to) and String.starts_with?(return_to, "/") do
        put_session(conn, :redirect_after_oauth, return_to)
      else
        conn
      end

    case GitHub.authorize_url(state) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:github_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, reason} ->
        Logger.warning("GitHub OAuth not configured", reason: inspect(reason))

        conn
        |> put_flash(:error, "GitHub login is not available right now.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Redirects the user to GitLab for OAuth authentication.
  """
  def gitlab_start(conn, _params) do
    state = generate_oauth_state()

    case GitLab.authorize_url(state) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:gitlab_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, reason} ->
        Logger.warning("GitLab OAuth not configured", reason: inspect(reason))

        conn
        |> put_flash(:error, "GitLab login is not available right now.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Handles the GitHub OAuth callback and signs the user in.
  """
  def github_callback(conn, %{"error" => error} = params) do
    Logger.warning("GitHub OAuth callback error", error: error)
    description = Map.get(params, "error_description")

    conn
    |> oauth_failure_flash("GitHub", {:oauth_error, error, description})
    |> redirect(to: ~p"/auth/login")
  end

  def github_callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :github_oauth_state)

    if session_state == state and is_binary(session_state) do
      conn = delete_session(conn, :github_oauth_state)

      with {:ok, profile} <- GitHub.fetch_user_profile(code),
           {:ok, user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email,
               access_token: profile.access_token
             ) do
        maybe_require_totp(conn, user)
      else
        {:error, reason} ->
          Logger.warning("GitHub OAuth callback failed", reason: inspect(reason))

          conn
          |> oauth_failure_flash("GitHub", reason)
          |> redirect(to: ~p"/auth/login")
      end
    else
      conn
      |> oauth_failure_flash("GitHub", :invalid_oauth_state)
      |> redirect(to: ~p"/auth/login")
    end
  end

  # Handle GitHub App installation callback (no state parameter)
  def github_callback(conn, %{
        "code" => code,
        "installation_id" => _installation_id,
        "setup_action" => "install"
      }) do
    current_user = conn.assigns[:current_user]

    if current_user do
      # User is already logged in, just update their GitHub token
      with {:ok, profile} <- GitHub.fetch_user_profile(code),
           {:ok, _user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email,
               access_token: profile.access_token
             ) do
        redirect_to = get_session(conn, :redirect_after_oauth) || ~p"/repositories"

        conn
        |> delete_session(:redirect_after_oauth)
        |> put_flash(:info, gettext("GitHub App installed successfully."))
        |> redirect(to: redirect_to)
      else
        {:error, reason} ->
          Logger.warning("GitHub App installation callback failed", reason: inspect(reason))

          conn
          |> oauth_failure_flash("GitHub", reason)
          |> redirect(to: ~p"/repositories")
      end
    else
      # User not logged in, treat as regular OAuth
      with {:ok, profile} <- GitHub.fetch_user_profile(code),
           {:ok, user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email,
               access_token: profile.access_token
             ) do
        maybe_require_totp(conn, user)
      else
        {:error, reason} ->
          Logger.warning("GitHub App installation callback failed", reason: inspect(reason))

          conn
          |> oauth_failure_flash("GitHub", reason)
          |> redirect(to: ~p"/auth/login")
      end
    end
  end

  @doc """
  Handles the GitLab OAuth callback and signs the user in.
  """
  def gitlab_callback(conn, %{"error" => error} = params) do
    Logger.warning("GitLab OAuth callback error", error: error)
    description = Map.get(params, "error_description")

    conn
    |> oauth_failure_flash("GitLab", {:oauth_error, error, description})
    |> redirect(to: ~p"/auth/login")
  end

  def gitlab_callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :gitlab_oauth_state)

    if session_state == state and is_binary(session_state) do
      conn = delete_session(conn, :gitlab_oauth_state)

      with {:ok, profile} <- GitLab.fetch_user_profile(code),
           {:ok, user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email
             ) do
        maybe_require_totp(conn, user)
      else
        {:error, reason} ->
          Logger.warning("GitLab OAuth callback failed", reason: inspect(reason))

          conn
          |> oauth_failure_flash("GitLab", reason)
          |> redirect(to: ~p"/auth/login")
      end
    else
      conn
      |> oauth_failure_flash("GitLab", :invalid_oauth_state)
      |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Verifies the magic link token and logs the user in.
  """
  def verify(conn, %{"token" => token}) do
    case Accounts.verify_login_token(token) do
      {:ok, user} ->
        maybe_require_totp(conn, user)

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "This login link is invalid or has expired.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Logs the user out.
  """
  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  defp oauth_failure_flash(conn, provider, reason) do
    message =
      case oauth_failure_details(reason) do
        nil ->
          gettext("%{provider} login failed. Please try again.", provider: provider)

        details ->
          gettext("%{provider} login failed. Reason: %{reason}",
            provider: provider,
            reason: details
          )
      end

    put_flash(conn, :error, message)
  end

  defp oauth_failure_details({:oauth_error, error, description}) do
    error = normalize_oauth_text(error)
    description = normalize_oauth_text(description)

    cond do
      error && description ->
        gettext("%{error}: %{description}", error: error, description: description)

      error ->
        gettext("oauth error: %{error}", error: error)

      description ->
        description

      true ->
        nil
    end
  end

  defp oauth_failure_details({type, status, body})
       when type in [:token_exchange_failed, :user_fetch_failed, :emails_fetch_failed] do
    type_label =
      case type do
        :token_exchange_failed -> gettext("token exchange failed")
        :user_fetch_failed -> gettext("user fetch failed")
        :emails_fetch_failed -> gettext("email fetch failed")
      end

    case oauth_status_details(status, body) do
      nil -> type_label
      details -> gettext("%{type} (%{details})", type: type_label, details: details)
    end
  end

  defp oauth_failure_details(:email_not_available),
    do: gettext("email not available from provider")

  defp oauth_failure_details(:missing_email), do: gettext("email not available from provider")

  defp oauth_failure_details(:missing_provider_user_id), do: gettext("provider user id missing")

  defp oauth_failure_details(:invalid_oauth_state), do: gettext("invalid OAuth state")

  defp oauth_failure_details(%Ecto.Changeset{}), do: nil

  defp oauth_failure_details(%Req.TransportError{reason: reason}),
    do: gettext("network error: %{reason}", reason: inspect(reason))

  defp oauth_failure_details(reason) when is_binary(reason), do: reason
  defp oauth_failure_details(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp oauth_failure_details(reason), do: inspect(reason)

  defp oauth_status_details(status, body) when is_integer(status) do
    message = oauth_body_message(body)

    if message do
      gettext("status %{status}: %{message}", status: status, message: message)
    else
      gettext("status %{status}", status: status)
    end
  end

  defp oauth_status_details(_status, _body), do: nil

  defp oauth_body_message(%{} = body) do
    error = normalize_oauth_text(Map.get(body, "error"))

    description =
      normalize_oauth_text(Map.get(body, "error_description")) ||
        normalize_oauth_text(Map.get(body, "message"))

    cond do
      error && description -> "#{error} - #{description}"
      error -> error
      description -> description
      true -> nil
    end
  end

  defp oauth_body_message(body) when is_binary(body) do
    body
    |> String.trim()
    |> normalize_oauth_text()
    |> truncate_oauth_text()
  end

  defp oauth_body_message(_body), do: nil

  defp normalize_oauth_text(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp normalize_oauth_text(_value), do: nil

  defp truncate_oauth_text(nil), do: nil

  defp truncate_oauth_text(text) do
    if String.length(text) > 160 do
      String.slice(text, 0, 157) <> "..."
    else
      text
    end
  end

  defp delivery_error_metadata(reason) do
    details = [reason: inspect(reason, pretty: true, limit: :infinity)]

    cond do
      is_map(reason) and Map.get(reason, :__struct__) == Swoosh.Error ->
        details ++
          [
            error: Exception.message(reason),
            swoosh_reason: inspect(Map.get(reason, :reason), pretty: true, limit: :infinity)
          ]

      match?(%{__exception__: true}, reason) ->
        details ++ [error: Exception.message(reason)]

      true ->
        details
    end
  end

  defp login_redirect_path(conn) do
    if get_session(conn, :device_user_code) do
      ~p"/device/auth"
    else
      ~p"/"
    end
  end

  defp maybe_require_totp(conn, user) do
    {conn, redirect_to} = pop_post_auth_redirect(conn)

    if Accounts.totp_enabled?(user) do
      conn
      |> put_session(:totp_pending_user_id, user.id)
      |> put_session(:totp_pending_redirect, redirect_to)
      |> redirect(to: ~p"/auth/totp")
    else
      conn
      |> put_session(:user_id, user.id)
      |> put_flash(:info, "Welcome back, #{user.account.handle}!")
      |> redirect(to: redirect_to)
    end
  end

  defp pop_post_auth_redirect(conn) do
    case get_session(conn, :redirect_after_oauth) do
      path when is_binary(path) ->
        if String.starts_with?(path, "/") do
          {delete_session(conn, :redirect_after_oauth), path}
        else
          {conn, login_redirect_path(conn)}
        end

      _ ->
        {conn, login_redirect_path(conn)}
    end
  end

  defp generate_oauth_state do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
