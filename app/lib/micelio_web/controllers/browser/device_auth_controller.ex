defmodule MicelioWeb.Browser.DeviceAuthController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.OAuth
  alias MicelioWeb.PageMeta

  def new(conn, params) do
    user_code =
      params
      |> Map.get("user_code")
      |> present_or_nil()

    conn =
      if user_code do
        put_session(conn, :device_user_code, user_code)
      else
        conn
      end

    user_code = user_code || get_session(conn, :device_user_code) || ""
    form = to_form(%{"user_code" => user_code}, as: :device)

    conn
    |> PageMeta.put(
      title_parts: ["Device authorization"],
      description: "Authorize a device to access your Micelio account.",
      canonical_url: url(~p"/device/auth")
    )
    |> render(:new, form: form)
  end

  def verify(conn, %{"device" => %{"user_code" => user_code}}) do
    base_meta = [
      description: "Authorize a device to access your Micelio account.",
      canonical_url: url(~p"/device/auth")
    ]

    case OAuth.approve_device_grant(user_code, conn.assigns.current_user) do
      {:ok, grant} ->
        conn
        |> delete_session(:device_user_code)
        |> PageMeta.put(Keyword.merge([title_parts: ["Device authorized"]], base_meta))
        |> render(:success, grant: grant)

      {:error, :not_found} ->
        conn
        |> put_session(:device_user_code, user_code)
        |> PageMeta.put(Keyword.merge([title_parts: ["Device authorization"]], base_meta))
        |> put_flash(:error, "That code was not found. Please check and try again.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))

      {:error, :expired_token} ->
        conn
        |> delete_session(:device_user_code)
        |> PageMeta.put(Keyword.merge([title_parts: ["Device authorization"]], base_meta))
        |> put_flash(:error, "This device code has expired. Please start again.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))

      {:error, _reason} ->
        conn
        |> put_session(:device_user_code, user_code)
        |> PageMeta.put(Keyword.merge([title_parts: ["Device authorization"]], base_meta))
        |> put_flash(:error, "Unable to approve this device right now.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))
    end
  end

  defp present_or_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp present_or_nil(_value), do: nil
end
