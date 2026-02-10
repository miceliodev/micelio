defmodule Micelio.ValidationEnvironments.LocalExecutor do
  @moduledoc """
  Executes validation checks locally for development or fallback validation.
  """

  @behaviour Micelio.ValidationEnvironments.Executor

  @impl true
  def run(_instance_ref, command, args, env) do
    {stdout, exit_code} =
      System.cmd(command, args, env: env_list(env), stderr_to_stdout: true)

    {:ok, %{exit_code: exit_code, stdout: stdout, resource_usage: %{}, coverage_delta: nil}}
  rescue
    exception ->
      {:ok,
       %{
         exit_code: 1,
         stdout: Exception.message(exception),
         resource_usage: %{},
         coverage_delta: nil
       }}
  end

  defp env_list(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp env_list(_), do: []
end
