defmodule MicelioWeb.Browser.ProfileController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.Accounts
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Storage
  alias MicelioWeb.PageMeta

  def show(conn, _params) do
    user = conn.assigns.current_user

    profile_form =
      user
      |> Accounts.change_user_profile()
      |> to_form(as: :user)

    s3_config = Storage.get_user_s3_config(user)

    conn
    |> put_profile_meta(user)
    |> render(
      :show,
      Map.merge(profile_assigns(conn, user, s3_config: s3_config), %{
        user: user,
        profile_form: profile_form
      })
    )
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated.")
        |> redirect(to: ~p"/account")

      {:error, changeset} ->
        profile_form = to_form(%{changeset | action: :update}, as: :user)

        conn
        |> put_profile_meta(user)
        |> render(
          :show,
          Map.merge(profile_assigns(conn, user), %{user: user, profile_form: profile_form})
        )
    end
  end

  def update_s3(conn, %{"s3_config" => params}) do
    user = conn.assigns.current_user
    validator_opts = s3_validator_opts(conn)

    case Storage.upsert_user_s3_config(user, params, validator_opts) do
      {:ok, _config, {:ok, _result}} ->
        conn
        |> put_flash(:info, "S3 configuration saved and validated.")
        |> redirect(to: ~p"/settings/storage")

      {:ok, _config, {:error, _result}} ->
        conn
        |> put_flash(:error, "S3 configuration saved, but validation failed.")
        |> redirect(to: ~p"/settings/storage")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "S3 configuration could not be saved.")
        |> redirect(to: ~p"/settings/storage")
    end
  end

  defp s3_validator_opts(conn) do
    case conn.assigns[:s3_validator] do
      nil -> []
      validator -> [validator: validator]
    end
  end

  defp profile_assigns(conn, user, opts \\ []) do
    activity_counts = Sessions.activity_counts_for_user(user)
    passkeys = Accounts.list_passkeys_for_user(user)
    organizations = Accounts.list_organizations_for_user_with_member_counts(user)
    totp_setup = totp_setup_from_session(conn, user)
    s3_config = Keyword.get(opts, :s3_config, Storage.get_user_s3_config(user))

    owned_repositories =
      user
      |> Accounts.list_organizations_for_user_with_role("admin")
      |> Enum.map(& &1.id)
      |> Repositories.list_repositories_for_organizations()

    %{
      activity_counts: activity_counts,
      passkeys: passkeys,
      owned_repositories: owned_repositories,
      organizations: organizations,
      s3_config: s3_config,
      totp_enabled: Accounts.totp_enabled?(user),
      totp_setup: totp_setup
    }
  end

  defp put_profile_meta(conn, user) do
    PageMeta.put(conn,
      title_parts: ["@#{user.account.handle}"],
      description: "Account settings and personal preferences.",
      canonical_url: url(~p"/account")
    )
  end

  defp totp_setup_from_session(conn, user) do
    case get_session(conn, :totp_setup_secret) do
      nil ->
        nil

      secret_base64 ->
        case Base.decode64(secret_base64) do
          {:ok, secret} ->
            %{
              secret: Base.encode32(secret, padding: false),
              uri: NimbleTOTP.otpauth_uri("Micelio", user.account.handle, secret)
            }

          _ ->
            nil
        end
    end
  end
end
