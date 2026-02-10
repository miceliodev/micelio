defmodule MicelioWeb.AuthenticationPlug do
  @moduledoc """
  Plug that loads the current user from the session.
  """
  import Plug.Conn

  alias Micelio.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Accounts.get_user_with_account(user_id) do
        nil ->
          conn
          |> clear_session()
          |> assign(:current_user, nil)

        user ->
          assign(conn, :current_user, user)
      end
    else
      assign(conn, :current_user, nil)
    end
  end
end
