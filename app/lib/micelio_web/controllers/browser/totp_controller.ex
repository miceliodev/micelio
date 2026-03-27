defmodule MicelioWeb.Browser.TotpController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias MicelioWeb.PageMeta

  def new(conn, _params) do
    if get_session(conn, :totp_pending_user_id) do
      conn
      |> PageMeta.put(
        title_parts: ["Two-factor authentication"],
        description: "Enter your authentication code to finish signing in.",
        canonical_url: url(~p"/auth/totp")
      )
      |> render(:new)
    else
      conn
      |> put_flash(:error, "Please sign in to continue.")
      |> redirect(to: ~p"/auth/login")
    end
  end

  def create(conn, %{"code" => code}) do
    with user_id when is_binary(user_id) <- get_session(conn, :totp_pending_user_id),
         %Accounts.User{} = user <- Accounts.get_user_with_account(user_id),
         {:ok, _user} <- Accounts.verify_totp_code(user, normalize_code(code)) do
      redirect_path = get_session(conn, :totp_pending_redirect) || ~p"/"

      conn
      |> delete_session(:totp_pending_user_id)
      |> delete_session(:totp_pending_redirect)
      |> put_session(:user_id, user.id)
      |> put_flash(:info, "Welcome back, #{user.account.handle}!")
      |> redirect(to: redirect_path)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid authentication code.")
        |> redirect(to: ~p"/auth/totp")
    end
  end

  def start(conn, _params) do
    user = conn.assigns.current_user

    if Accounts.totp_enabled?(user) do
      conn
      |> put_flash(:info, "Two-factor authentication is already enabled.")
      |> redirect(to: ~p"/account")
    else
      secret = Accounts.generate_totp_secret()

      conn
      |> put_session(:totp_setup_secret, Base.encode64(secret))
      |> put_flash(:info, "Scan the QR code or enter the secret to finish setup.")
      |> redirect(to: ~p"/account")
    end
  end

  def verify(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    with secret_base64 when is_binary(secret_base64) <- get_session(conn, :totp_setup_secret),
         {:ok, secret} <- Base.decode64(secret_base64),
         {:ok, _user} <- Accounts.enable_totp(user, secret, normalize_code(code)) do
      conn
      |> delete_session(:totp_setup_secret)
      |> put_flash(:info, "Two-factor authentication is now enabled.")
      |> redirect(to: ~p"/account")
    else
      :error ->
        conn
        |> put_flash(:error, "Two-factor setup expired. Please try again.")
        |> redirect(to: ~p"/account")

      {:error, :already_enabled} ->
        conn
        |> delete_session(:totp_setup_secret)
        |> put_flash(:info, "Two-factor authentication is already enabled.")
        |> redirect(to: ~p"/account")

      _ ->
        conn
        |> put_flash(:error, "Invalid authentication code.")
        |> redirect(to: ~p"/account")
    end
  end

  def cancel(conn, _params) do
    conn
    |> delete_session(:totp_setup_secret)
    |> put_flash(:info, "Two-factor setup canceled.")
    |> redirect(to: ~p"/account")
  end

  def disable(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    case Accounts.disable_totp(user, normalize_code(code)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Two-factor authentication has been disabled.")
        |> redirect(to: ~p"/account")

      _ ->
        conn
        |> put_flash(:error, "Invalid authentication code.")
        |> redirect(to: ~p"/account")
    end
  end

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> String.replace(~r/[\s-]/, "")
  end

  defp normalize_code(_), do: ""
end
