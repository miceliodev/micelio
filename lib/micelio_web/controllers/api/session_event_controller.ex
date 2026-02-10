defmodule MicelioWeb.Api.SessionEventController do
  use MicelioWeb, :controller

  alias Micelio.Sessions.EventSchema
  alias Micelio.{Authorization, Sessions}

  @default_poll_ms 1_000
  @heartbeat_ms 15_000

  def stream(conn, %{"id" => identifier} = params) do
    with %Sessions.Session{} = session <-
           Sessions.get_session_with_associations_by_identifier(identifier),
         :ok <- authorize_session(conn, session),
         {:ok, types} <- parse_types(params),
         {:ok, since} <- parse_since(params),
         {:ok, limit} <- parse_limit(params) do
      after_cursor = parse_after_cursor(conn, params)
      follow = follow?(params)

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")

      if follow do
        conn
        |> send_chunked(200)
        |> stream_follow(session.session_id, types, since, after_cursor, limit)
      else
        stream_snapshot(conn, session.session_id, types, since, after_cursor, limit)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})

      {:error, :invalid_types} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid event types"})

      {:error, :invalid_since} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid since cursor"})

      {:error, :invalid_limit} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid limit"})
    end
  end

  defp authorize_session(conn, session) do
    case Authorization.authorize(:repository_read, conn.assigns[:current_user], session.project) do
      :ok -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp parse_types(params) do
    types = Map.get(params, "types") || Map.get(params, "type")

    normalized =
      cond do
        is_nil(types) -> nil
        is_list(types) -> Enum.map(types, &String.trim/1)
        is_binary(types) -> String.split(types, ",", trim: true) |> Enum.map(&String.trim/1)
        true -> []
      end

    allowed = EventSchema.event_types()

    if is_nil(normalized) or Enum.all?(normalized, &(&1 in allowed)) do
      {:ok, normalized}
    else
      {:error, :invalid_types}
    end
  end

  defp parse_since(params) do
    case Map.get(params, "since") do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          {_, ""} -> {:error, :invalid_since}
          _ -> parse_since_iso(value)
        end

      _ ->
        {:error, :invalid_since}
    end
  end

  defp parse_since_iso(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_since}
    end
  end

  defp parse_limit(params) do
    case Map.get(params, "limit") do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, :invalid_limit}
        end

      _ ->
        {:error, :invalid_limit}
    end
  end

  defp parse_after_cursor(conn, params) do
    last_event_id =
      conn
      |> get_req_header("last-event-id")
      |> List.first()

    last_event_id || Map.get(params, "after") || Map.get(params, "cursor")
  end

  defp follow?(params) do
    case Map.get(params, "follow") do
      nil -> true
      value when value in ["false", "0", "no"] -> false
      _ -> true
    end
  end

  defp stream_snapshot(conn, session_id, types, since, after_cursor, limit) do
    opts =
      [
        types: types,
        since: since,
        after: after_cursor,
        limit: limit
      ] ++ storage_opts(conn)

    case Sessions.list_session_events(session_id, opts) do
      {:ok, events} ->
        body = retry_line() <> Enum.map_join(events, "", &format_sse_event/1)
        send_resp(conn, 200, body)

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to load session events"})
    end
  end

  defp stream_follow(conn, session_id, types, since, after_cursor, limit) do
    start = System.monotonic_time(:millisecond)
    conn = send_retry_line(conn)
    do_stream_follow(conn, session_id, types, since, after_cursor, limit, start)
  end

  defp do_stream_follow(conn, session_id, types, since, after_cursor, limit, last_heartbeat) do
    opts =
      [
        types: types,
        since: since,
        after: after_cursor,
        limit: limit
      ] ++ storage_opts(conn)

    case Sessions.list_session_events(session_id, opts) do
      {:ok, events} ->
        {conn, cursor} = send_events(conn, events, after_cursor)

        if conn.state == :chunked do
          now = System.monotonic_time(:millisecond)

          {conn, last_heartbeat} =
            if now - last_heartbeat >= @heartbeat_ms do
              case chunk(conn, ": ping\n\n") do
                {:ok, conn} -> {conn, now}
                {:error, _} -> {conn, now}
              end
            else
              {conn, last_heartbeat}
            end

          Process.sleep(@default_poll_ms)
          do_stream_follow(conn, session_id, types, since, cursor, limit, last_heartbeat)
        else
          conn
        end

      {:error, _reason} ->
        _ = chunk(conn, ~s(event: error\ndata: {"message":"Event stream failed"}\n\n))
        conn
    end
  end

  defp send_events(conn, events, cursor) do
    Enum.reduce_while(events, {conn, cursor}, fn event, {conn, _cursor} ->
      case chunk(conn, format_sse_event(event)) do
        {:ok, conn} -> {:cont, {conn, event.storage_key}}
        {:error, _} -> {:halt, {conn, event.storage_key}}
      end
    end)
  end

  defp format_sse_event(%{storage_key: storage_key, json: json}) do
    "id: #{storage_key}\n" <>
      "event: session_event\n" <>
      "data: #{json}\n\n"
  end

  defp retry_line do
    "retry: #{@default_poll_ms}\n\n"
  end

  defp send_retry_line(conn) do
    case chunk(conn, retry_line()) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp storage_opts(conn) do
    case conn.assigns[:storage_config] do
      nil -> []
      config -> [storage_config: config]
    end
  end
end
