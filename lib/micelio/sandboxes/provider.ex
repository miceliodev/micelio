defmodule Micelio.Sandboxes.Provider do
  @moduledoc """
  Behaviour for sandbox providers that run coding agents in isolated environments.

  Implementations manage the lifecycle of sandboxed workspaces where agents
  can read/write files and execute commands safely.
  """

  @type workspace_id :: String.t()
  @type workspace_status :: :provisioning | :running | :stopping | :stopped | :error

  @type connection_info :: %{
          type: :stdio | :websocket,
          agent_path: String.t() | nil,
          agent_args: [String.t()],
          websocket_url: String.t() | nil,
          cwd: String.t()
        }

  @type workspace :: %{
          workspace_id: workspace_id(),
          connection_info: connection_info()
        }

  @doc """
  Creates a sandboxed workspace for a plan.

  The workspace should contain the repository files and have the coding agent
  CLI available. Returns connection info for establishing an ACP connection.
  """
  @callback create_workspace(plan :: map(), opts :: keyword()) ::
              {:ok, workspace()} | {:error, term()}

  @doc """
  Destroys a sandboxed workspace and frees its resources.
  """
  @callback destroy_workspace(workspace_id()) :: :ok | {:error, term()}

  @doc """
  Returns the current status of a workspace.
  """
  @callback status(workspace_id()) :: {:ok, workspace_status()} | {:error, term()}
end
