defmodule MicelioWeb.Browser.LegalControllerTest do
  use MicelioWeb.ConnCase, async: true

  test "privacy page renders" do
    conn = build_conn() |> get("/privacy")

    assert html_response(conn, 200) =~ "Privacy"
  end

  test "terms page renders" do
    conn = build_conn() |> get("/terms")

    assert html_response(conn, 200) =~ "Terms"
  end

  test "cookies page renders" do
    conn = build_conn() |> get("/cookies")

    assert html_response(conn, 200) =~ "Cookie"
  end

  test "impressum page renders" do
    conn = build_conn() |> get("/impressum")

    assert html_response(conn, 200) =~ "Impressum"
  end
end
