defmodule MicelioWeb.Plugs.OGRateLimitPlugTest do
  use MicelioWeb.ConnCase, async: true

  alias MicelioWeb.Plugs.OGRateLimitPlug

  setup do
    ip = "10.#{System.unique_integer([:positive]) |> rem(255)}.#{System.unique_integer([:positive]) |> rem(255)}.#{System.unique_integer([:positive]) |> rem(255)}"
    %{ip: ip}
  end

  defp call_plug(conn, rate_limits) do
    opts = OGRateLimitPlug.init(rate_limits: rate_limits)
    OGRateLimitPlug.call(conn, opts)
  end

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn, ip: ip} do
      config = [default: 200, window_ms: 60_000, overrides: %{"open_graph" => 5}]

      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> call_plug(config)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["5"]
    end

    test "returns 429 when rate limit exceeded", %{conn: conn, ip: ip} do
      config = [default: 200, window_ms: 60_000, overrides: %{"open_graph" => 2}]

      for _ <- 1..2 do
        build_conn()
        |> put_req_header("x-forwarded-for", ip)
        |> call_plug(config)
      end

      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> call_plug(config)

      assert conn.halted
      assert conn.status == 429
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["0"]
      assert get_resp_header(conn, "retry-after") != []
    end

    test "uses default limit when no open_graph override", %{conn: conn, ip: ip} do
      config = [default: 100, window_ms: 60_000, overrides: %{}]

      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> call_plug(config)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
    end
  end

  describe "IP extraction" do
    test "uses first IP from x-forwarded-for", %{conn: conn} do
      config = [default: 200, window_ms: 60_000, overrides: %{"open_graph" => 100}]

      conn =
        conn
        |> put_req_header("x-forwarded-for", "203.0.113.1, 10.0.0.1")
        |> call_plug(config)

      refute conn.halted
    end

    test "falls back to remote_ip without x-forwarded-for", %{conn: conn} do
      config = [default: 200, window_ms: 60_000, overrides: %{"open_graph" => 100}]

      conn = call_plug(conn, config)
      refute conn.halted
    end
  end
end
