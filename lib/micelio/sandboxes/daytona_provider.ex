defmodule Micelio.Sandboxes.DaytonaProvider do
  @moduledoc """
  Daytona-based sandbox provider for production environments.

  Provisions remote sandboxed workspaces via the Daytona API where coding
  agents run with full filesystem and terminal access.
  """

  @behaviour Micelio.Sandboxes.Provider

  alias Micelio.Repo
  alias Micelio.Repositories.Repository

  require Logger

  @default_base_url "https://app.daytona.io/api"
  @default_preview_port 3000
  @default_auto_stop_interval 15
  @default_auto_archive_interval 30

  @impl true
  def create_workspace(plan, opts) do
    sandbox_token = Micelio.Sandboxes.Token.generate()
    server_url = Keyword.get(opts, :server_url, default_server_url())
    module_url = "#{server_url}/sandbox/modules/agent.ts"
    host = URI.parse(server_url).host
    deno_auth = "#{sandbox_token}@#{host}"

    env = Keyword.get(opts, :env, [])
    env = [{"DENO_AUTH_TOKENS", deno_auth} | env]
    opts = Keyword.put(opts, :env, env)

    with {:ok, api_key} <- api_key(),
         {:ok, sandbox} <- create_sandbox(api_key, plan),
         {:ok, local_checkout_path} <- clone_repository_for_plan(plan, sandbox, opts),
         {:ok, preview_url} <- maybe_preview_url(api_key, sandbox),
         {:ok, {agent_path, agent_args}} <- build_agent_command(opts, module_url) do
      {:ok,
       %{
         workspace_id: sandbox_id(sandbox),
         connection_info: %{
           type: :stdio,
           agent_path: agent_path,
           agent_args: agent_args,
           websocket_url: nil,
           cwd: local_checkout_path
         },
         metadata: %{
           "provider" => "daytona",
           "sandbox_id" => sandbox_id(sandbox),
           "sandbox_name" => sandbox_name(sandbox),
           "preview_url" => preview_url,
           "dashboard_url" => dashboard_url(sandbox),
           "sandbox_token" => sandbox_token
         }
       }}
    else
      {:error, reason} ->
        Logger.warning("Daytona workspace creation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def destroy_workspace(workspace_id) do
    case api_key() do
      {:ok, api_key} ->
        _ = delete_sandbox(api_key, workspace_id)
        _ = delete_local_checkout(workspace_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def status(workspace_id) do
    with {:ok, api_key} <- api_key(),
         {:ok, sandbox} <- get_sandbox(api_key, workspace_id) do
      {:ok, map_status(Map.get(sandbox, "state"))}
    end
  end

  defp api_key do
    case Keyword.get(config(), :api_key) do
      api_key when is_binary(api_key) and api_key != "" ->
        {:ok, api_key}

      _ ->
        {:error, :missing_daytona_api_key}
    end
  end

  defp create_sandbox(api_key, plan) do
    body =
      %{
        name: sandbox_name_for_plan(plan),
        snapshot: Keyword.get(config(), :sandbox_snapshot),
        target: Keyword.get(config(), :sandbox_target),
        class: Keyword.get(config(), :sandbox_class),
        autoStopInterval:
          Keyword.get(config(), :auto_stop_interval_minutes, @default_auto_stop_interval),
        autoArchiveInterval:
          Keyword.get(config(), :auto_archive_interval_minutes, @default_auto_archive_interval),
        labels: sandbox_labels(plan),
        public: false
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    request(:post, "/sandbox", api_key, json: body)
  end

  defp delete_sandbox(api_key, workspace_id) do
    case request(:delete, "/sandbox/#{workspace_id}", api_key) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_sandbox(api_key, workspace_id) do
    request(:get, "/sandbox/#{workspace_id}", api_key)
  end

  defp maybe_preview_url(api_key, sandbox) do
    workspace_id = sandbox_id(sandbox)
    port = Keyword.get(config(), :preview_port, @default_preview_port)

    case request(:get, "/sandbox/#{workspace_id}/ports/#{port}/signed-preview-url", api_key) do
      {:ok, %{"url" => url}} when is_binary(url) and url != "" -> {:ok, url}
      {:ok, %{"url" => _url}} -> {:ok, nil}
      {:error, _} -> {:ok, nil}
    end
  end

  defp build_agent_command(opts, module_url) do
    case System.find_executable("deno") do
      nil ->
        {:error, :deno_not_found}

      deno_path ->
        env_pairs =
          opts
          |> Keyword.get(:env, [])
          |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)

        if env_pairs == [] do
          {:ok, {deno_path, ["run", "--allow-all", "--reload", module_url]}}
        else
          env_binary = System.find_executable("env") || "/usr/bin/env"

          {:ok,
           {env_binary, env_pairs ++ [deno_path, "run", "--allow-all", "--reload", module_url]}}
        end
    end
  end

  defp default_server_url do
    Application.get_env(:micelio, Micelio.Sandboxes, [])
    |> Keyword.get(:module_server_url, "http://localhost:4000")
  end

  defp clone_repository_for_plan(plan, sandbox, _opts) do
    repository =
      plan
      |> Repo.preload(:repository)
      |> Map.get(:repository)

    with %Repository{} = repository <- repository,
         {:ok, clone_url} <- repository_clone_url(repository) do
      root = checkout_root()
      workspace_id = sandbox_id(sandbox)
      checkout_path = Path.join(root, workspace_id)
      _ = File.rm_rf(checkout_path)
      :ok = File.mkdir_p(root)

      case MuonTrap.cmd("git", ["clone", "--depth", "1", "--", clone_url, checkout_path],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          {:ok, checkout_path}

        {output, _exit_code} ->
          Logger.warning("Git clone failed, using empty checkout: #{output}")
          :ok = File.mkdir_p(checkout_path)
          {:ok, checkout_path}
      end
    else
      _ ->
        {:error, :repository_not_found}
    end
  end

  defp delete_local_checkout(workspace_id) do
    path = Path.join(checkout_root(), workspace_id)
    _ = File.rm_rf(path)
    :ok
  end

  defp checkout_root do
    Keyword.get(config(), :local_checkout_root, Path.join(System.tmp_dir!(), "micelio-daytona"))
  end

  defp repository_clone_url(%Repository{url: url}) when is_binary(url) and url != "" do
    {:ok, ensure_git_suffix(url)}
  end

  defp repository_clone_url(%Repository{forge_host: host, forge_owner: owner, forge_repo: repo})
       when is_binary(host) and is_binary(owner) and is_binary(repo) do
    {:ok, "https://#{host}/#{owner}/#{repo}.git"}
  end

  defp repository_clone_url(_repository), do: {:error, :missing_clone_url}

  defp ensure_git_suffix(url) do
    if String.ends_with?(url, ".git"), do: url, else: url <> ".git"
  end

  defp request(method, path, api_key, opts \\ []) do
    headers =
      [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
      |> maybe_put_org_header()

    request_opts =
      opts
      |> Keyword.put(:headers, headers)
      |> Keyword.put(:url, base_url() <> path)

    case Req.request(Keyword.put(request_opts, :method, method)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :invalid_credentials}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_org_header(headers) do
    case Keyword.get(config(), :organization_id) do
      org_id when is_binary(org_id) and org_id != "" ->
        [{"x-daytona-organization-id", org_id} | headers]

      _ ->
        headers
    end
  end

  defp sandbox_labels(plan) do
    %{
      "micelio.plan_id" => plan.id,
      "micelio.repository_id" => plan.repository_id,
      "micelio.user_id" => plan.user_id
    }
    |> Map.new(fn {key, value} -> {key, to_string(value)} end)
  end

  defp sandbox_name_for_plan(plan) do
    "micelio-#{String.slice(plan.id, 0, 12)}"
  end

  defp sandbox_id(%{"id" => id}) when is_binary(id), do: id
  defp sandbox_id(%{"sandboxId" => id}) when is_binary(id), do: id
  defp sandbox_id(_), do: Ecto.UUID.generate()

  defp sandbox_name(%{"name" => name}) when is_binary(name), do: name
  defp sandbox_name(_), do: nil

  defp dashboard_url(%{"id" => id}) when is_binary(id),
    do: "https://app.daytona.io/sandboxes/#{id}"

  defp dashboard_url(_), do: nil

  defp map_status("creating"), do: :provisioning
  defp map_status("starting"), do: :provisioning
  defp map_status("started"), do: :running
  defp map_status("stopping"), do: :stopping
  defp map_status("stopped"), do: :stopped
  defp map_status("error"), do: :error
  defp map_status("build_failed"), do: :error
  defp map_status(_), do: :provisioning

  defp base_url do
    Keyword.get(config(), :base_url, @default_base_url)
  end

  defp config do
    Application.get_env(:micelio, __MODULE__, [])
  end
end
