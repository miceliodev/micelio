defmodule MicelioWeb.Plugs.OGRateLimitPlugTest do
  use MicelioWeb.ConnCase, async: false

  alias MicelioWeb.Plugs.OGRateLimitPlug

  setup do
    # Use a unique IP per test to avoid cross-test interference
    ip = "10.0.0.#{System.unique_integer([:positive]) |> rem(255)}"
    %{ip: ip}
  end

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn, ip: ip} do
      Application.put_env(:micelio, :rate_limits,
        default: 200,
        window_ms: 60_000,
        overrides: %{"open_graph" => 5}
      )

      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> OGRateLimitPlug.call(OGRateLimitPlug.init([]))

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["5"]
    end

    test "returns 429 when rate limit exceeded", %{conn: conn, ip: ip} do
      Application.put_env(:micelio, :rate_limits,
        default: 200,
        window_ms: 60_000,
        overrides: %{"open_graph" => 2}
      )

      # Exhaust the limit
      for _ <- 1..2 do
        build_conn()
        |> put_req_header("x-forwarded-for", ip)
        |> OGRateLimitPlug.call(OGRateLimitPlug.init([]))
      end

      # Next request should be denied
      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> OGRateLimitPlug.call(OGRateLimitPlug.init([]))

      assert conn.halted
      assert conn.status == 429
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["0"]
      assert get_resp_header(conn, "retry-after") != []
    end

    test "uses default limit when no open_graph override", %{conn: conn, ip: ip} do
      Application.put_env(:micelio, :rate_limits,
        default: 100,
        window_ms: 60_000,
        overrides: %{}
      )

      conn =
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> OGRateLimitPlug.call(OGRateLimitPlug.init([]))

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
    end
  end

  describe "IP extraction" do
    test "uses x-forwarded-for header when present", %{conn: conn} do
      Application.put_env(:micelio, :rate_limits,
        default: 200,
        window_ms: 60_000,
        overrides: %{"open_graph" => 100}
      )

      conn =
        conn
        |> put_req_header("x-forwarded-for", "203.0.113.1, 10.0.0.1")
        |> OGRateLimitPlug.call(OGRateLimitPlug.init([]))

      refute conn.halted
    end

    test "falls back to remote_ip without x-forwarded-for", %{conn: conn} do
      Application.put_env(:micelio, :rate_limits,
        default: 200,
        window_ms: 60_000,
        overrides: %{"open_graph" => 100}
      )

      conn = OGRateLimitPlug.call(conn, OGRateLimitPlug.init([]))
      refute conn.halted
    end
  end
end
