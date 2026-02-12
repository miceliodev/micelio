defmodule MicelioWeb.Plugs.ApiScopePlugTest do
  use MicelioWeb.ConnCase, async: true

  alias MicelioWeb.Plugs.ApiScopePlug

  describe "call/2" do
    test "passes when token has required scope", %{conn: conn} do
      conn =
        conn
        |> assign(:token_scopes, ["repositories:read", "sessions:write"])
        |> ApiScopePlug.call(["repositories:read"])

      refute conn.halted
    end

    test "passes when token has all required scopes", %{conn: conn} do
      conn =
        conn
        |> assign(:token_scopes, ["repositories:read", "sessions:write", "content:read"])
        |> ApiScopePlug.call(["repositories:read", "content:read"])

      refute conn.halted
    end

    test "halts with 403 when token lacks required scope", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:token_scopes, ["repositories:read"])
        |> ApiScopePlug.call(["sessions:write"])

      assert conn.halted
      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "insufficient_scope"
    end

    test "halts with 403 when token_scopes is nil", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> ApiScopePlug.call(["repositories:read"])

      assert conn.halted
      assert conn.status == 403
    end

    test "halts with 403 when token has only some required scopes", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:token_scopes, ["repositories:read"])
        |> ApiScopePlug.call(["repositories:read", "sessions:write"])

      assert conn.halted
      assert conn.status == 403
    end
  end

  describe "init/1" do
    test "passes through required scopes" do
      assert ApiScopePlug.init(["repositories:read"]) == ["repositories:read"]
    end
  end
end
