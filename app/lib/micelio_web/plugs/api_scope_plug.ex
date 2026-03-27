defmodule MicelioWeb.Plugs.ApiScopePlug do
  @moduledoc """
  Verifies that the current OAuth2 token has the required scope(s).

  Usage as a plug in a controller:

      plug MicelioWeb.Plugs.ApiScopePlug, ["repositories:read"] when action in [:index, :show]
      plug MicelioWeb.Plugs.ApiScopePlug, ["repositories:write"] when action in [:create, :update, :delete]
  """
  import Plug.Conn

  def init(required_scopes) when is_list(required_scopes), do: required_scopes

  def call(conn, required_scopes) do
    token_scopes = conn.assigns[:token_scopes] || []

    if Enum.all?(required_scopes, &(&1 in token_scopes)) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{
        error: "insufficient_scope",
        error_description: "Required scope(s): #{Enum.join(required_scopes, ", ")}"
      })
      |> halt()
    end
  end
end
