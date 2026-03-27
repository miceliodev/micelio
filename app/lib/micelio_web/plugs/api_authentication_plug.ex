defmodule MicelioWeb.Plugs.ApiAuthenticationPlug do
  @moduledoc """
  Authenticates API requests using bearer tokens.
  """
  import Plug.Conn

  alias Boruta.Oauth.Token
  alias Micelio.Accounts
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Scopes

  def init(opts), do: opts

  def call(conn, _opts) do
    case fetch_bearer_token(conn) do
      {:ok, token} ->
        with %Token{} = access_token <- AccessTokens.get_by(value: token),
             user when not is_nil(user) <- Accounts.get_user(access_token.sub) do
          token_scopes = Scopes.from_string(access_token.scope)

          conn
          |> assign(:current_user, user)
          |> assign(:token_scopes, token_scopes)
        else
          _ -> conn
        end

      :error ->
        conn
    end
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      ["bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end
end
