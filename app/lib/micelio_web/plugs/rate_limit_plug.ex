defmodule MicelioWeb.Plugs.RateLimitPlug do
  @moduledoc """
  Rate limiting plug using Hammer.

  Provides configurable rate limiting per IP address and authenticated user.
  """

  @behaviour Plug

  import Plug.Conn

  @default_limit 100
  @default_window_ms 60_000
  @default_abuse_threshold 5
  @default_abuse_window_ms 300_000
  @default_abuse_block_ms 3_600_000

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      bucket_prefix: Keyword.get(opts, :bucket_prefix, "api"),
      authenticated_limit: Keyword.get(opts, :authenticated_limit),
      authenticated_window_ms: Keyword.get(opts, :authenticated_window_ms),
      authenticated_bucket_prefix: Keyword.get(opts, :authenticated_bucket_prefix),
      skip_if_authenticated: Keyword.get(opts, :skip_if_authenticated, false),
      abuse_threshold: Keyword.get(opts, :abuse_threshold),
      abuse_window_ms: Keyword.get(opts, :abuse_window_ms),
      abuse_block_ms: Keyword.get(opts, :abuse_block_ms),
      abuse_bucket_prefix: Keyword.get(opts, :abuse_bucket_prefix)
    }
  end

  @impl true
  def call(conn, %{skip_if_authenticated: true} = opts) do
    if authenticated?(conn) do
      conn
    else
      apply_rate_limit(conn, opts, :unauthenticated)
    end
  end

  def call(conn, opts) do
    if authenticated?(conn) and not is_nil(opts.authenticated_limit) do
      apply_rate_limit(conn, opts, :authenticated)
    else
      apply_rate_limit(conn, opts, :unauthenticated)
    end
  end

  defp apply_rate_limit(conn, opts, :authenticated) do
    prefix = opts.authenticated_bucket_prefix || "#{opts.bucket_prefix}:auth"
    limit = opts.authenticated_limit
    window_ms = opts.authenticated_window_ms || opts.window_ms
    key = bucket_key(conn, prefix, :authenticated)

    apply_rate_limit_with_key(conn, limit, window_ms, key, abuse_opts(conn, opts, :authenticated))
  end

  defp apply_rate_limit(
         conn,
         %{limit: limit, window_ms: window_ms, bucket_prefix: prefix} = opts,
         :unauthenticated
       ) do
    key = bucket_key(conn, prefix, :unauthenticated)

    apply_rate_limit_with_key(
      conn,
      limit,
      window_ms,
      key,
      abuse_opts(conn, opts, :unauthenticated)
    )
  end

  defp apply_rate_limit_with_key(conn, limit, window_ms, key, abuse_opts) do
    case maybe_blocked_for_abuse(conn, abuse_opts) do
      {:blocked, retry_after_ms} ->
        respond_abuse_block(conn, retry_after_ms)

      :ok ->
        case Hammer.check_rate(key, window_ms, limit) do
          {:allow, count} ->
            conn
            |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(0, limit - count)))

          {:deny, _limit} ->
            case maybe_mark_abuse(abuse_opts) do
              {:blocked, retry_after_ms} ->
                respond_abuse_block(conn, retry_after_ms)

              :ok ->
                conn
                |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
                |> put_resp_header("x-ratelimit-remaining", "0")
                |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
                |> send_resp(429, "Rate limit exceeded. Please try again later.")
                |> halt()
            end
        end
    end
  end

  defp authenticated?(conn) do
    not is_nil(conn.assigns[:current_user])
  end

  defp bucket_key(conn, prefix, :authenticated) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> "#{prefix}:user:#{user_id}"
      _ -> bucket_key(conn, prefix, :unauthenticated)
    end
  end

  defp bucket_key(conn, prefix, :unauthenticated) do
    ip = get_client_ip(conn)
    "#{prefix}:ip:#{ip}"
  end

  defp get_client_ip(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    case forwarded_for do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      value ->
        value
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp abuse_opts(conn, opts, auth_type) do
    threshold = opts.abuse_threshold || @default_abuse_threshold
    window_ms = opts.abuse_window_ms || @default_abuse_window_ms
    block_ms = opts.abuse_block_ms || @default_abuse_block_ms

    if abuse_enabled?(opts) do
      prefix = opts.abuse_bucket_prefix || "#{opts.bucket_prefix}:abuse"
      key = bucket_key(conn, prefix, auth_type)
      %{key: key, threshold: threshold, window_ms: window_ms, block_ms: block_ms}
    end
  end

  defp abuse_enabled?(opts) do
    not is_nil(opts.abuse_threshold) or
      not is_nil(opts.abuse_window_ms) or
      not is_nil(opts.abuse_block_ms) or
      not is_nil(opts.abuse_bucket_prefix)
  end

  defp maybe_blocked_for_abuse(_conn, nil), do: :ok

  defp maybe_blocked_for_abuse(_conn, %{key: key}) do
    case Micelio.Abuse.Blocklist.blocked?(key) do
      {:blocked, remaining_ms} -> {:blocked, remaining_ms}
      :ok -> :ok
    end
  end

  defp maybe_mark_abuse(nil), do: :ok

  defp maybe_mark_abuse(%{
         key: key,
         threshold: threshold,
         window_ms: window_ms,
         block_ms: block_ms
       }) do
    case Hammer.check_rate("#{key}:violations", window_ms, threshold) do
      {:allow, count} when count >= threshold ->
        Micelio.Abuse.Blocklist.block(key, block_ms)
        {:blocked, block_ms}

      {:deny, _limit} ->
        Micelio.Abuse.Blocklist.block(key, block_ms)
        {:blocked, block_ms}

      _ ->
        :ok
    end
  end

  defp respond_abuse_block(conn, retry_after_ms) do
    retry_after_seconds = max(1, ceil_div(retry_after_ms, 1000))

    conn
    |> put_resp_header("x-abuse-blocked", "true")
    |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
    |> send_resp(429, "Abuse detected. Please try again later.")
    |> halt()
  end

  defp ceil_div(value, divisor) do
    div(value + divisor - 1, divisor)
  end
end
