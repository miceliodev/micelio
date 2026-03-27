defmodule Micelio.Plans.ACPClient do
  @moduledoc """
  Local ACP (Agent Client Protocol) client for interactive plan creation.

  Manages communication with AI coding agents (Claude Code, Codex, Gemini CLI)
  through the standardized ACP protocol via ACPex. Each plan conversation gets
  its own client instance.

  This module is the **local/development adapter** that spawns an ACP agent as a
  local subprocess via stdio. In production, agent execution happens in a sandboxed
  environment with a separate remote adapter.
  """

  @behaviour ACPex.Client

  alias ACPex.Protocol.Connection
  alias Micelio.Plans
  alias Micelio.Plans.PlanMessage

  require Logger

  defstruct [
    :plan_id,
    :notify_pid,
    :connection_pid,
    :session_id,
    :current_message_id,
    :agent,
    :model,
    status: :idle,
    sequence: 0,
    accumulated_text: ""
  ]

  def start(plan_id, opts) do
    notify_pid = Keyword.fetch!(opts, :notify_pid)
    agent = Keyword.get(opts, :agent, "claude")
    model = Keyword.get(opts, :model, default_model())

    agent_path = find_executable(agent)

    if agent_path == nil do
      {:error, "#{agent} CLI not found in PATH"}
    else
      agent_args = agent_args_for(agent)

      init_args = %{
        plan_id: plan_id,
        notify_pid: notify_pid,
        agent: agent,
        model: model
      }

      case ACPex.start_client(__MODULE__, init_args,
             agent_path: agent_path,
             agent_args: agent_args,
             name: {:via, Registry, {Micelio.Plans.AgentRegistry, {:acp, plan_id}}}
           ) do
        {:ok, conn_pid} ->
          Task.start(fn ->
            initialize_connection(conn_pid, plan_id, notify_pid)
          end)

          {:ok, conn_pid}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def prompt(plan_id, text) do
    case lookup(plan_id) do
      {:ok, conn_pid, state} ->
        Task.start(fn ->
          try do
            request_payload = %{
              "sessionId" => state.session_id,
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
            send(state.notify_pid, {:agent_event, {:complete, %{result: "", cost: nil}}})
          rescue
            e ->
              persist_event(plan_id, "error", "session/prompt", %{
                "error" => Exception.message(e)
              })

              Logger.error("ACPClient prompt error: #{inspect(e)}")
              send(state.notify_pid, {:agent_event, {:error, inspect(e)}})
          end
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop(plan_id) do
    case Registry.lookup(Micelio.Plans.AgentRegistry, {:acp, plan_id}) do
      [{pid, _}] ->
        GenServer.stop(pid, :normal)

      [] ->
        :ok
    end
  catch
    :exit, _ -> :ok
  end

  def get_status(plan_id) do
    case Registry.lookup(Micelio.Plans.AgentRegistry, {:acp, plan_id}) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :get_acp_status)
        catch
          :exit, _ -> :not_running
        end

      [] ->
        :not_running
    end
  end

  @impl ACPex.Client
  def init(args) do
    state = %__MODULE__{
      plan_id: args.plan_id,
      notify_pid: args.notify_pid,
      agent: args.agent,
      model: args.model
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
  def handle_fs_write_text_file(_request, state) do
    {:error, %{code: -32002, message: "Write access is not permitted during planning"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_create(_request, state) do
    {:error, %{code: -32003, message: "Terminal access is not permitted during planning"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_output(_request, state) do
    {:error, %{code: -32003, message: "Terminal access is not permitted during planning"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_wait_for_exit(_request, state) do
    {:error, %{code: -32003, message: "Terminal access is not permitted during planning"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_kill(_request, state) do
    {:error, %{code: -32003, message: "Terminal access is not permitted during planning"}, state}
  end

  @impl ACPex.Client
  def handle_terminal_release(_request, state) do
    {:error, %{code: -32003, message: "Terminal access is not permitted during planning"}, state}
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
              notify(new_state, {:agent_event, {:streaming, msg}})
              new_state

            {:error, _} ->
              new_state
          end

        message_id ->
          case update_streaming_message(message_id, new_accumulated) do
            {:ok, msg} ->
              notify(new_state, {:agent_event, {:streaming, msg}})
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

  defp initialize_connection(conn_pid, plan_id, notify_pid) do
    initialize_payload = %{
      "protocolVersion" => 1,
      "clientInfo" => %{
        "name" => "micelio",
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
        30_000
      )

    persist_event(plan_id, "response", "initialize", %{"result" => initialize_response})

    session_payload = %{
      "cwd" => File.cwd!(),
      "mcpServers" => []
    }

    persist_event(plan_id, "request", "session/new", session_payload)

    response =
      Connection.send_request(
        conn_pid,
        "session/new",
        session_payload,
        30_000
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
      Registry.update_value(Micelio.Plans.AgentRegistry, {:acp, plan_id}, fn _ ->
        %{connection_pid: conn_pid, session_id: session_id}
      end)

      send(notify_pid, {:agent_event, :connected})
      {:ok, conn_pid}
    else
      Logger.error("ACPClient: session/new did not return session_id: #{inspect(response)}")
      send(notify_pid, {:agent_event, {:error, "Agent did not return a session ID"}})
      {:error, :no_session_id}
    end
  rescue
    e ->
      persist_event(plan_id, "error", "initialize", %{"error" => Exception.message(e)})

      Logger.error("ACPClient initialization error: #{inspect(e)}")

      send(
        notify_pid,
        {:agent_event, {:error, "Agent connection failed: #{Exception.message(e)}"}}
      )

      {:error, e}
  catch
    :exit, reason ->
      persist_event(plan_id, "error", "initialize", %{"error" => inspect(reason)})

      Logger.error("ACPClient initialization exit: #{inspect(reason)}")
      send(notify_pid, {:agent_event, {:error, "Agent connection timed out"}})
      {:error, reason}
  end

  defp lookup(plan_id) do
    case Registry.lookup(Micelio.Plans.AgentRegistry, {:acp, plan_id}) do
      [{pid, value}] when is_map(value) ->
        {:ok, pid,
         %__MODULE__{
           connection_pid: value.connection_pid,
           session_id: value.session_id,
           notify_pid: nil
         }}

      [{pid, _}] ->
        {:ok, pid, %__MODULE__{}}

      [] ->
        {:error, :not_running}
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

  defp notify(%{notify_pid: pid}, message) when is_pid(pid) do
    send(pid, message)
  end

  defp notify(_, _), do: :ok

  defp find_executable("claude"), do: System.find_executable("claude")
  defp find_executable("codex"), do: System.find_executable("codex")
  defp find_executable("gemini"), do: System.find_executable("gemini")
  defp find_executable(other), do: System.find_executable(other)

  defp agent_args_for("gemini"), do: ["--experimental-acp"]
  defp agent_args_for(_agent), do: []

  defp default_model do
    config = Application.get_env(:micelio, __MODULE__, [])
    Keyword.get(config, :default_model, "sonnet")
  end

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
