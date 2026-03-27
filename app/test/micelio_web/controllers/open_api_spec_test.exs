defmodule MicelioWeb.OpenApiSpecTest do
  use MicelioWeb.ConnCase, async: true

  test "serves the OpenAPI spec", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/openapi")

    payload = json_response(conn, 200)

    assert %{"info" => %{"title" => "Micelio API"}, "openapi" => openapi} = payload
    assert is_binary(openapi)
  end

  test "serves the Swagger UI", %{conn: conn} do
    html = get(conn, "/api/docs") |> html_response(200)

    assert html =~ "Swagger UI"
  end
end
