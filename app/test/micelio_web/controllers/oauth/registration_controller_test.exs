defmodule MicelioWeb.Oauth.RegistrationControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.OAuth

  test "registers a client and returns credentials", %{conn: conn} do
    payload = %{
      "client_name" => "Test Client",
      "redirect_uris" => []
    }

    conn = post(conn, "/oauth/register", payload)

    assert %{"client_id" => client_id, "client_secret" => client_secret} =
             json_response(conn, 201)

    assert is_binary(client_id)
    assert is_binary(client_secret)

    assert %{} = OAuth.get_device_client(client_id)
  end
end
