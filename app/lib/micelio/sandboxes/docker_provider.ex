defmodule Micelio.Sandboxes.DockerProvider do
  @moduledoc """
  Docker-based sandbox provider for local development.

  Spawns a Deno process that fetches and executes TypeScript modules
  served by the Micelio server. Communicates ACP JSON-RPC 2.0 over
  bidirectional stdio.

  Process lifecycle is managed by ACPex's DynamicSupervisor. Note that
  muontrap cannot be used here because it hijacks stdin for its own
  flow control protocol, making bidirectional stdio communication
  impossible.
  """

  @behaviour Micelio.Sandboxes.Provider

  alias Micelio.Sandboxes.Token

  require Logger

  @impl true
  def create_workspace(_plan, opts) do
    case find_deno() do
      nil ->
        {:error, "deno not found in PATH. Install Deno to use sandbox modules."}

      deno_path ->
        workspace_id = generate_workspace_id()
        cwd = Keyword.get(opts, :cwd, File.cwd!())
        env = Keyword.get(opts, :env, [])
        server_url = Keyword.get(opts, :server_url, default_server_url())

        sandbox_token = Token.generate()
        module_url = "#{server_url}/sandbox/modules/agent.ts"
        host = URI.parse(server_url).host
        deno_auth = "#{sandbox_token}@#{host}"

        env = [{"DENO_AUTH_TOKENS", deno_auth} | env]
        {agent_path, agent_args} = build_agent_command(deno_path, env, module_url)

        {:ok,
         %{
           workspace_id: workspace_id,
           connection_info: %{
             type: :stdio,
             agent_path: agent_path,
             agent_args: agent_args,
             websocket_url: nil,
             cwd: cwd
           },
           metadata: %{
             "provider" => "docker",
             "sandbox_token" => sandbox_token
           }
         }}
    end
  end

  @impl true
  def destroy_workspace(_workspace_id) do
    :ok
  end

  @impl true
  def status(_workspace_id) do
    {:ok, :running}
  end

  defp build_agent_command(deno_path, env, module_url) do
    env_args = Enum.map(env, fn {key, value} -> "#{key}=#{value}" end)

    if env_args == [] do
      {deno_path, ["run", "--allow-all", "--reload", module_url]}
    else
      {find_env(), env_args ++ [deno_path, "run", "--allow-all", "--reload", module_url]}
    end
  end

  defp find_deno, do: System.find_executable("deno")
  defp find_env, do: System.find_executable("env") || "/usr/bin/env"

  defp default_server_url do
    Application.get_env(:micelio, Micelio.Sandboxes, [])
    |> Keyword.get(:module_server_url, "http://localhost:4000")
  end

  defp generate_workspace_id do
    "docker-local-#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
  end
end
