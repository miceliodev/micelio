defmodule Micelio.TestValidationProvider do
  @behaviour Micelio.AgentInfra.Provider

  @impl true
  def id, do: :test_provider

  @impl true
  def name, do: "Test Provider"

  @impl true
  def validate_request(request), do: validate_request(request, [])

  @impl true
  def validate_request(request, opts) do
    notify({:validate_request, request}, opts)
    :ok
  end

  @impl true
  def provision(request), do: provision(request, [])

  @impl true
  def provision(request, opts) do
    notify({:provision, request}, opts)
    {:ok, %{id: "test-vm"}}
  end

  @impl true
  def status(_ref), do: {:ok, %{state: :running, hostname: nil, ip_address: nil, metadata: %{}}}

  @impl true
  def terminate(ref), do: terminate(ref, [])

  @impl true
  def terminate(ref, opts) do
    notify({:terminate, ref}, opts)
    :ok
  end

  defp notify(message, opts) do
    if pid = Keyword.get(opts, :notify_pid) do
      send(pid, message)
    end

    :ok
  end
end

defmodule Micelio.TestValidationExecutor do
  @behaviour Micelio.ValidationEnvironments.Executor

  @impl true
  def run(_instance_ref, "mix", ["compile" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "compiled", resource_usage: %{cpu_seconds: 1.0}}}
  end

  def run(_instance_ref, "mix", ["format" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "formatted", resource_usage: %{cpu_seconds: 0.5}}}
  end

  def run(_instance_ref, "mix", ["test" | _], _env) do
    {:ok,
     %{
       exit_code: 0,
       stdout: "tests passed",
       resource_usage: %{cpu_seconds: 2.0, memory_mb: 128},
       coverage_delta: 0.03
     }}
  end

  def run(_instance_ref, _command, _args, _env) do
    {:ok, %{exit_code: 0, stdout: "ok", resource_usage: %{}}}
  end
end

defmodule Micelio.TestFailingValidationExecutor do
  @behaviour Micelio.ValidationEnvironments.Executor

  @impl true
  def run(_instance_ref, "mix", ["compile" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "compiled", resource_usage: %{cpu_seconds: 1.0}}}
  end

  def run(_instance_ref, "mix", ["format" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "formatted", resource_usage: %{cpu_seconds: 0.5}}}
  end

  def run(_instance_ref, "mix", ["test" | _], _env) do
    {:ok,
     %{
       exit_code: 1,
       stdout: "tests failed",
       resource_usage: %{cpu_seconds: 1.5, memory_mb: 128},
       coverage_delta: -0.02
     }}
  end

  def run(_instance_ref, _command, _args, _env) do
    {:ok, %{exit_code: 0, stdout: "ok", resource_usage: %{}}}
  end
end
