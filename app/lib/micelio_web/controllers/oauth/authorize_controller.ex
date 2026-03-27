defmodule MicelioWeb.Oauth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use MicelioWeb, :controller

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner

  def oauth_module, do: Application.get_env(:micelio, :oauth_module, Boruta.Oauth)

  def authorize(conn, _params) do
    case conn.assigns[:current_user] do
      %_{} = current_user ->
        oauth_module().authorize(
          conn,
          %ResourceOwner{sub: to_string(current_user.id), username: current_user.email},
          __MODULE__
        )

      _ ->
        redirect_to_login(conn)
    end
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect(conn, external: AuthorizeResponse.redirect_to_url(response))
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_error(%Plug.Conn{} = conn, %Error{status: :unauthorized}) do
    redirect_to_login(conn)
  end

  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect(conn, external: Error.redirect_to_url(error))
  end

  def authorize_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    conn
    |> put_status(status)
    |> json(%{
      error: error,
      error_description: error_description
    })
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_success(_conn, _response), do: :ok

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_error(_conn, _response), do: :ok

  defp redirect_to_login(conn) do
    return_to = current_path(conn)
    encoded_return_to = URI.encode_www_form(return_to)

    conn
    |> redirect(to: ~p"/auth/login?return_to=#{encoded_return_to}")
  end
end
