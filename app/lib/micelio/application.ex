defmodule Micelio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Micelio.OTel.setup()
    maybe_add_logger_backend()
    maybe_attach_loki_handler()
    maybe_attach_sentry_handler()
    ensure_ets_tables()

    children =
      [
        Micelio.PromEx,
        MicelioWeb.Telemetry,
        Micelio.Mic.Telemetry,
        Micelio.Cloak,
        Micelio.Repo,
        {Task, fn -> Micelio.OAuth.ensure_cli_device_client() end},
        Micelio.Abuse.Blocklist,
        {Task.Supervisor, name: Micelio.Webhooks.Supervisor},
        {Task.Supervisor, name: Micelio.Notifications.Supervisor},
        {Task.Supervisor, name: Micelio.RemoteExecution.Supervisor},
        {Task.Supervisor, name: Micelio.ValidationEnvironments.Supervisor},
        {Task.Supervisor, name: Micelio.Mic.RollupSupervisor},
        Micelio.Mic.RollupScheduler,
        {Registry, keys: :unique, name: Micelio.Plans.AgentRegistry},
        {DynamicSupervisor, name: Micelio.Plans.AgentSupervisor, strategy: :one_for_one},
        Micelio.Forges.ForgeAboutCache,
        Micelio.Sandboxes.Watchdog,
        {DNSCluster, query: Application.get_env(:micelio, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Micelio.PubSub},
        # Start a worker by calling: Micelio.Worker.start_link(arg)
        # {Micelio.Worker, arg},
        # Start to serve requests, typically the last entry
        MicelioWeb.Endpoint
      ]
      |> maybe_add_browser_pool()
      |> maybe_add_grpc_server()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Micelio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MicelioWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_browser_pool(children) do
    og_config = Application.get_env(:micelio, :open_graph, [])

    if Keyword.get(og_config, :enabled, false) do
      pool_size = Keyword.get(og_config, :pool_size, 2)

      pool_opts =
        [name: Micelio.OG.BrowserPool, pool_size: pool_size]
        |> then(fn opts ->
          case Keyword.get(og_config, :chrome_path) do
            nil -> opts
            path -> Keyword.put(opts, :chrome_path, path)
          end
        end)

      children ++ [{BrowseChrome.BrowserPool, pool_opts}]
    else
      children
    end
  end

  defp maybe_add_grpc_server(children) do
    grpc_config = Application.get_env(:micelio, Micelio.GRPC, [])

    is_seed_run =
      System.get_env("MIX_TASK") == "run" or
        Enum.any?(System.argv(), &String.ends_with?(&1, "priv/repo/seeds.exs"))

    if Keyword.get(grpc_config, :enabled, false) and not is_seed_run do
      port = Keyword.get(grpc_config, :port, 50_051)
      env = Application.get_env(:micelio, :environment, :prod)

      if env == :dev and not port_available?(port) do
        if not is_seed_run do
          Logger.warning("gRPC port #{port} already in use; skipping gRPC server start.")
        end

        children
      else
        tls = Keyword.get(grpc_config, :tls, [])
        tls_mode = Keyword.get(grpc_config, :tls_mode, :required)

        if tls == [] and tls_mode == :required do
          raise """
          Micelio.GRPC is enabled but TLS is not configured.
          Configure MICELIO_GRPC_TLS_CERTFILE and MICELIO_GRPC_TLS_KEYFILE.
          """
        end

        adapter_opts =
          case tls do
            [] ->
              [status_handler: {"/up", Micelio.GRPC.StatusHandler, []}]

            _ ->
              [
                cred: GRPC.Credential.new(ssl: tls),
                status_handler: {"/up", Micelio.GRPC.StatusHandler, []}
              ]
          end

        children ++
          [
            {GRPC.Server.Supervisor,
             [
               port: port,
               endpoint: Micelio.GRPC.Endpoint,
               adapter_opts: adapter_opts,
               start_server: true
             ]}
          ]
      end
    else
      children
    end
  end

  defp port_available?(port) do
    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp maybe_attach_sentry_handler do
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: :all}
      })
    end
  end

  defp maybe_attach_loki_handler do
    case Application.get_env(:micelio, :loki) do
      config when is_list(config) and config != [] ->
        LokiLoggerHandler.attach(:micelio_loki, config)

      _ ->
        :ok
    end
  end

  defp ensure_ets_tables do
    :ets.new(Micelio.Plans.AgenticACPClient.Sessions, [:named_table, :public, :set])
  rescue
    ArgumentError -> :ok
  end

  defp maybe_add_logger_backend do
    if Application.get_env(:micelio, :environment, :prod) != :test do
      case Logger.add_backend(Micelio.Errors.LoggerBackend) do
        :ok -> :ok
        {:ok, _pid} -> :ok
        {:error, {:already_present, _}} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
