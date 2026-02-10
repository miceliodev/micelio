defmodule MicelioWeb.LiveAuth do
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  alias Micelio.Accounts

  def on_mount(:require_auth, _params, session, socket) do
    case fetch_current_user(session) do
      nil ->
        {:halt, redirect(socket, to: "/auth/login")}

      user ->
        {:cont, assign(socket, current_user: user, current_scope: nil)}
    end
  end

  def on_mount(:current_user, _params, session, socket) do
    {:cont, assign(socket, current_user: fetch_current_user(session), current_scope: nil)}
  end

  defp fetch_current_user(session) do
    case session["user_id"] do
      nil -> nil
      user_id -> Accounts.get_user_with_account(user_id)
    end
  end
end
