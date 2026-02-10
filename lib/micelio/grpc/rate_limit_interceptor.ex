defmodule Micelio.GRPC.RateLimitInterceptor do
  @moduledoc """
  gRPC server interceptor for rate limiting using Hammer.
  """

  @behaviour GRPC.Server.Interceptor

  @default_limit 100
  @default_window_ms 60_000

  @impl true
  def init(opts) do
    [
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    ]
  end

  @impl true
  def call(req, stream, next, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    key = bucket_key(stream)

    case Hammer.check_rate(key, window_ms, limit) do
      {:allow, _count} ->
        next.(req, stream)

      {:deny, _limit} ->
        raise GRPC.RPCError,
          status: GRPC.Status.resource_exhausted(),
          message: "Rate limit exceeded. Please try again later."
    end
  end

  defp bucket_key(stream) do
    ip = get_client_ip(stream)
    "grpc:#{ip}"
  end

  defp get_client_ip(stream) do
    case stream.http_request_headers do
      %{"x-forwarded-for" => forwarded} when is_binary(forwarded) ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      _ ->
        case stream.adapter do
          {_mod, %{socket: socket}} ->
            case :inet.peername(socket) do
              {:ok, {ip, _port}} -> :inet.ntoa(ip) |> to_string()
              _ -> "unknown"
            end

          _ ->
            "unknown"
        end
    end
  end
end
