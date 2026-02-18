defmodule Micelio.Plans.AgenticACPClient do
  @moduledoc """
  ACP client for agentic sessions where the agent runs inside a sandbox.

  Unlike `ACPClient` which blocks writes and terminal access, this client
  allows all operations since the agent runs in an isolated environment
  (Docker container or Daytona workspace).

  Session metadata (session_id, notify_pid) is stored in an ETS table
  rather than Registry values, since the initialization runs in a Task
  and Registry values can only be updated by the owning process.
  """

  @behaviour ACPex.Client

  alias ACPex.Protocol.Connection
  alias Micelio.Plans
  alias Micelio.Plans.PlanMessage

  require Logger

  @sessions_table __MODULE__.Sessions

  defstruct [
    :plan_id,
    :notify_pid,
    :connection_pid,
    :session_id,
    :current_message_id,
    :agent,
    :model,
    :llm_provider,
    :cwd,
    status: :idle,
    sequence: 0,
    accumulated_text: ""
  ]

  def start(plan_id, opts) do
    ensure_table()

    notify_pid = Keyword.fetch!(opts, :notify_pid)
    connection_info = Keyword.fetch!(opts, :connection_info)
    agent = Keyword.get(opts, :agent, "pi")
    model = Keyword.get(opts, :model)
    llm_provider = Keyword.get(opts, :llm_provider)

    init_args = %{
      plan_id: plan_id,
      notify_pid: notify_pid,
      agent: agent,
      model: model,
      llm_provider: llm_provider,
      cwd: connection_info.cwd
    }

    case ACPex.start_client(__MODULE__, init_args,
           agent_path: connection_info.agent_path,
           agent_args: connection_info.agent_args,
           name: {:via, Registry, {Micelio.Plans.AgentRegistry, {:agentic, plan_id}}}
         ) do
      {:ok, conn_pid} ->
        Task.start(fn ->
          initialize_connection(conn_pid, plan_id, notify_pid, connection_info.cwd,
            model: model,
            llm_provider: llm_provider
          )
        end)

        {:ok, conn_pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def prompt(plan_id, text) do
    case lookup(plan_id) do
      {:ok, conn_pid, session_id, notify_pid} ->
        Task.start(fn ->
          try do
            request_payload = %{
              "sessionId" => session_id,
              "prompt" => [%{"type" => "text", "text" => text}]
            }

            persist_event(plan_id, "request", "session/prompt", request_payload)

            response =
              Connection.send_request(
                conn_pid,
                "session/prompt",
                request_payload,
                :infinity
              )

            persist_event(plan_id, "response", "session/prompt", %{"result" => response})

            finalized = Plans.finalize_plan_streaming_messages(plan_id)

            for msg <- finalized do
              send(notify_pid, {:agent_event, {:message_finalized, msg}})
            end

            send(notify_pid, {:agent_event, {:complete, %{result: "", cost: nil}}})
          rescue
            e ->
              persist_event(plan_id, "error", "session/prompt", %{
                "error" => Exception.message(e)
              })

              Logger.error("AgenticACPClient prompt error: #{inspect(e)}")
              Plans.finalize_plan_streaming_messages(plan_id)
              send(notify_pid, {:agent_event, {:error, inspect(e)}})
          end
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop(plan_id) do
    if :ets.whereis(@sessions_table) != :undefined do
      :ets.delete(@sessions_table, plan_id)
    end

    case Registry.lookup(Micelio.Plans.AgentRegistry, {:agentic, plan_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(ACPex.Protocol.ConnectionSupervisor, pid)

      [] ->
        :ok
    end
  catch
    :exit, _ -> :ok
  end

  def running?(plan_id) do
    case Registry.lookup(Micelio.Plans.AgentRegistry, {:agentic, plan_id}) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  def update_notify_pid(plan_id, new_pid) do
    if :ets.whereis(@sessions_table) == :undefined do
      {:error, :not_running}
    else
      case :ets.lookup(@sessions_table, plan_id) do
        [{^plan_id, data}] ->
          :ets.insert(@sessions_table, {plan_id, Map.put(data, :notify_pid, new_pid)})
          :ok

        [] ->
          {:error, :not_running}
      end
    end
  end

  @impl ACPex.Client
  def init(args) do
    state = %__MODULE__{
      plan_id: args.plan_id,
      notify_pid: args.notify_pid,
      agent: args.agent,
      model: args.model,
      llm_provider: args[:llm_provider],
      cwd: args.cwd
    }

    {:ok, state}
  end

  @impl ACPex.Client
  def handle_session_update(notification, state) do
    persist_event(state.plan_id, "update", session_update_type(notification.update), %{
      "update" => notification.update
    })

    state = handle_update(notification.update, state)
    {:noreply, state}
  end

  @impl ACPex.Client
  def handle_fs_read_text_file(request, state) do
    case File.read(request.path) do
      {:ok, content} ->
        response = %ACPex.Schema.Client.FsReadTextFileResponse{content: content}
        {:ok, response, state}

      {:error, reason} ->
        {:error, %{code: -32001, message: "File read error: #{inspect(reason)}"}, state}
    end
  end

  @impl ACPex.Client
  def handle_fs_write_text_file(request, state) do
    case File.write(request.path, request.content) do
      :ok ->
        {:ok, %{}, state}

      {:error, reason} ->
        {:error, %{code: -32002, message: "File write error: #{inspect(reason)}"}, state}
    end
  end

  @impl ACPex.Client
  def handle_terminal_create(_request, state) do
    {:ok, %{id: "sandbox-terminal-#{state.plan_id}"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_output(_request, state) do
    {:ok, %{}, state}
  end

  @impl ACPex.Client
  def handle_terminal_wait_for_exit(_request, state) do
    {:ok, %{exit_code: 0}, state}
  end

  @impl ACPex.Client
  def handle_terminal_kill(_request, state) do
    {:ok, %{}, state}
  end

  @impl ACPex.Client
  def handle_terminal_release(_request, state) do
    {:ok, %{}, state}
  end

  defp handle_update(%{"sessionUpdate" => "agent_message_chunk"} = update, state) do
    text = extract_text_from_content(update["content"])

    if text == "" do
      state
    else
      new_accumulated = state.accumulated_text <> text
      new_state = %{state | status: :streaming, accumulated_text: new_accumulated}

      case state.current_message_id do
        nil ->
          case create_streaming_message(new_state, new_accumulated) do
            {:ok, msg} ->
              new_state = %{new_state | current_message_id: msg.id}
              notify(new_state.plan_id, {:agent_event, {:streaming, msg}})
              new_state

            {:error, _} ->
              new_state
          end

        message_id ->
          case update_streaming_message(message_id, new_accumulated) do
            {:ok, msg} ->
              notify(new_state.plan_id, {:agent_event, {:streaming, msg}})
              new_state

            {:error, _} ->
              new_state
          end
      end
    end
  end

  defp handle_update(%{"sessionUpdate" => "agent_thought_chunk"}, state), do: state
  defp handle_update(%{"sessionUpdate" => "tool_call"}, state), do: state
  defp handle_update(%{"sessionUpdate" => "tool_call_update"}, state), do: state
  defp handle_update(_update, state), do: state

  defp ensure_table do
    if :ets.whereis(@sessions_table) == :undefined do
      :ets.new(@sessions_table, [:named_table, :public, :set])
    end
  rescue
    ArgumentError -> :ok
  end

  defp initialize_connection(conn_pid, plan_id, notify_pid, cwd, opts) do
    model = Keyword.get(opts, :model)
    llm_provider = Keyword.get(opts, :llm_provider)

    initialize_payload = %{
      "protocolVersion" => 1,
      "clientInfo" => %{
        "name" => "micelio-agentic",
        "version" => "0.1.0"
      },
      "capabilities" => %{
        "roots" => %{},
        "sampling" => %{}
      }
    }

    persist_event(plan_id, "request", "initialize", initialize_payload)

    initialize_response =
      Connection.send_request(
        conn_pid,
        "initialize",
        initialize_payload,
        120_000
      )

    persist_event(plan_id, "response", "initialize", %{"result" => initialize_response})

    session_params =
      %{"cwd" => cwd, "mcpServers" => []}
      |> maybe_put("model", model)
      |> maybe_put("provider", llm_provider)

    persist_event(plan_id, "request", "session/new", session_params)

    response =
      Connection.send_request(
        conn_pid,
        "session/new",
        session_params,
        60_000
      )

    persist_event(plan_id, "response", "session/new", %{"result" => response})

    session_id =
      case response do
        %{session_id: sid} -> sid
        %{"sessionId" => sid} -> sid
        %{"session_id" => sid} -> sid
        %{"result" => %{"sessionId" => sid}} -> sid
        %{"result" => %{"session_id" => sid}} -> sid
        _ -> nil
      end

    if session_id do
      :ets.insert(
        @sessions_table,
        {plan_id,
         %{
           connection_pid: conn_pid,
           session_id: session_id,
           notify_pid: notify_pid
         }}
      )

      send(notify_pid, {:agent_event, :connected})
      {:ok, conn_pid}
    else
      Logger.error(
        "AgenticACPClient: session/new did not return session_id: #{inspect(response)}"
      )

      send(notify_pid, {:agent_event, {:error, "Agent did not return a session ID"}})
      {:error, :no_session_id}
    end
  rescue
    e ->
      persist_event(plan_id, "error", "initialize", %{"error" => Exception.message(e)})

      Logger.error("AgenticACPClient initialization error: #{inspect(e)}")

      send(
        notify_pid,
        {:agent_event, {:error, "Agent connection failed: #{Exception.message(e)}"}}
      )

      {:error, e}
  catch
    :exit, reason ->
      persist_event(plan_id, "error", "initialize", %{"error" => inspect(reason)})

      Logger.error("AgenticACPClient initialization exit: #{inspect(reason)}")
      send(notify_pid, {:agent_event, {:error, "Agent connection timed out"}})
      {:error, reason}
  end

  defp lookup(plan_id) do
    with [{pid, _}] <- Registry.lookup(Micelio.Plans.AgentRegistry, {:agentic, plan_id}),
         [{^plan_id, data}] <- :ets.lookup(@sessions_table, plan_id) do
      {:ok, pid, data.session_id, data.notify_pid}
    else
      [] -> {:error, :not_running}
      _ -> {:error, :not_running}
    end
  end

  defp extract_text_from_content(%{type: "text", text: text}) when is_binary(text), do: text

  defp extract_text_from_content(%{"type" => "text", "text" => text}) when is_binary(text),
    do: text

  defp extract_text_from_content(_), do: ""

  defp create_streaming_message(state, content) do
    Plans.create_plan_message(state.plan_id, %{
      role: "assistant",
      content: content,
      model: state.model,
      agent: state.agent,
      status: "streaming",
      sequence: state.sequence + 1
    })
  end

  defp update_streaming_message(message_id, content) do
    case Micelio.Repo.get(PlanMessage, message_id) do
      nil -> {:error, :not_found}
      msg -> Plans.update_plan_message(msg, %{content: content})
    end
  end

  defp notify(plan_id, message) do
    case :ets.lookup(@sessions_table, plan_id) do
      [{^plan_id, %{notify_pid: pid}}] when is_pid(pid) ->
        send(pid, message)

      _ ->
        :ok
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp session_update_type(update) when is_map(update) do
    Map.get(update, "sessionUpdate") || Map.get(update, :sessionUpdate) || "session/update"
  end

  defp session_update_type(_), do: "session/update"

  defp persist_event(plan_id, direction, event_type, payload) do
    _ =
      Plans.persist_acp_envelope(plan_id, %{
        direction: direction,
        event_type: event_type,
        payload: payload
      })

    :ok
  end
end
