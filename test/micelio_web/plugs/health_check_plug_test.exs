defmodule MicelioWeb.HealthCheckPlugTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  test "returns 200 when the path is /up" do
    assert html_response(
             MicelioWeb.HealthCheckPlug.call(
               build_conn(:get, "/up"),
               MicelioWeb.HealthCheckPlug.init([])
             ),
             200
           ) =~ "ok"
  end

  test "returns the same connection when the path is not /up" do
    conn = build_conn(:get, "/account/repo")

    got =
      MicelioWeb.HealthCheckPlug.call(
        conn,
        MicelioWeb.HealthCheckPlug.init([])
      )

    assert(got == conn)
  end
end
