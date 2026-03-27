defmodule MicelioWeb.WellKnownControllerTest do
  use MicelioWeb.ConnCase, async: true

  test "micelio discovery returns urls", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/micelio.json")
    response = json_response(conn, 200)

    assert response["service"] == "micelio"
    assert is_binary(response["web_url"])
    assert is_binary(response["grpc_url"])
    assert response["api_base_path"] == "/api"
    assert response["rest_api_base"] == response["web_url"] <> "/api"
  end
end
