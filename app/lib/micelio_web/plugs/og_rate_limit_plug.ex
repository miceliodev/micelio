defmodule MicelioWeb.Plugs.OGRateLimitPlug do
  @moduledoc """
  Rate limiting plug for the OG image endpoint.

  Uses the global rate limit configuration with an OG-specific domain override.
  Reads from `config :micelio, :rate_limits` at runtime.

  Configure via environment variables:
  - `MICELIO_RATE_LIMIT_DEFAULT` - Global default (requests/window, default: 200)
  - `MICELIO_RATE_LIMIT_WINDOW_MS` - Global window (default: 60000ms)
  - `MICELIO_RATE_LIMIT_OG` - OG-specific override (default: 30)

  Includes abuse detection: after 10 rate-limit violations within 5 minutes,
  the IP is blocked for 1 hour.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(_opts), do: []

  @impl true
  def call(conn, _opts) do
    rate_limits = Application.get_env(:micelio, :rate_limits, [])
    default_limit = Keyword.get(rate_limits, :default, 200)
    window_ms = Keyword.get(rate_limits, :window_ms, 60_000)
    overrides = Keyword.get(rate_limits, :overrides, %{})
    limit = Map.get(overrides, "open_graph", default_limit)

    ip = get_client_ip(conn)
    key = "rate:og:ip:#{ip}"
    abuse_key = "rate:og:abuse:ip:#{ip}"

    case Micelio.Abuse.Blocklist.blocked?(abuse_key) do
      {:blocked, remaining_ms} ->
        retry_after = max(1, div(remaining_ms + 999, 1000))

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> send_resp(429, "Too many requests. Please try again later.")
        |> halt()

      :ok ->
        case Hammer.check_rate(key, window_ms, limit) do
          {:allow, count} ->
            conn
            |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(0, limit - count)))

          {:deny, _limit} ->
            maybe_block_for_abuse(abuse_key)

            conn
            |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", "0")
            |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
            |> send_resp(429, "Rate limit exceeded. Please try again later.")
            |> halt()
        end
    end
  end

  defp maybe_block_for_abuse(abuse_key) do
    case Hammer.check_rate("#{abuse_key}:violations", 300_000, 10) do
      {:allow, count} when count >= 10 ->
        Micelio.Abuse.Blocklist.block(abuse_key, 3_600_000)

      {:deny, _} ->
        Micelio.Abuse.Blocklist.block(abuse_key, 3_600_000)

      _ ->
        :ok
    end
  end

  defp get_client_ip(conn) do
    case conn |> get_req_header("x-forwarded-for") |> List.first() do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      value ->
        value |> String.split(",") |> List.first() |> String.trim()
    end
  end
end
