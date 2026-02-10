defmodule Micelio.RemoteExecution do
  @moduledoc """
  Provides a queue-backed remote execution service for running CLI tools.
  """

  alias Micelio.Accounts.User
  alias Micelio.RemoteExecution.ExecutionTask
  alias Micelio.Repo

  @supervisor Micelio.RemoteExecution.Supervisor

  def enqueue_task(%User{} = user, attrs) when is_map(attrs) do
    enqueue_task(user, attrs, [])
  end

  def enqueue_task(%User{} = user, attrs, opts) when is_map(attrs) and is_list(opts) do
    supervisor = Keyword.get(opts, :supervisor, @supervisor)

    case create_task(user, attrs, opts) do
      {:ok, task} ->
        case start_task(supervisor, task.id) do
          {:ok, _pid} ->
            {:ok, task}

          {:error, reason} ->
            mark_task_failed(task, reason)
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_task(%User{} = user, attrs) when is_map(attrs) do
    create_task(user, attrs, [])
  end

  def create_task(%User{} = user, attrs, opts) when is_map(attrs) and is_list(opts) do
    attrs = put_user_id(attrs, user.id)

    %ExecutionTask{}
    |> ExecutionTask.create_changeset(attrs, opts)
    |> Repo.insert()
  end

  defp put_user_id(attrs, user_id) do
    # Detect if attrs use string or atom keys and maintain consistency
    cond do
      Map.has_key?(attrs, "command") -> Map.put(attrs, "user_id", user_id)
      Map.has_key?(attrs, :command) -> Map.put(attrs, :user_id, user_id)
      true -> Map.put(attrs, :user_id, user_id)
    end
  end

  def get_task_for_user(%User{} = user, task_id) do
    Repo.get_by(ExecutionTask, id: task_id, user_id: user.id)
  end

  def execute_task(task_id) do
    with %ExecutionTask{} = task <- Repo.get(ExecutionTask, task_id),
         {:ok, task} <- Repo.update(ExecutionTask.running_changeset(task)) do
      run_command(task)
    else
      nil ->
        {:error, :not_found}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp run_command(%ExecutionTask{} = task) do
    {stdout, exit_code} =
      System.cmd(task.command, task.args, env: env_list(task.env), stderr_to_stdout: true)

    status = if exit_code == 0, do: :succeeded, else: :failed

    Repo.update(
      ExecutionTask.complete_changeset(task, %{
        status: status,
        stdout: stdout,
        stderr: nil,
        exit_code: exit_code,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
  rescue
    exception ->
      Repo.update(
        ExecutionTask.complete_changeset(task, %{
          status: :failed,
          stdout: "",
          stderr: Exception.message(exception),
          exit_code: nil,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      )
  end

  defp env_list(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp env_list(_), do: []

  defp start_task(supervisor, task_id) do
    # Get the caller PID to allow sandbox access in tests
    caller = self()

    Task.Supervisor.start_child(supervisor, fn ->
      # Allow this process to use the sandbox connection from the caller
      # This is a no-op in production but enables async tests
      if function_exported?(Ecto.Adapters.SQL.Sandbox, :allow, 3) do
        Ecto.Adapters.SQL.Sandbox.allow(Micelio.Repo, caller, self())
      end

      execute_task(task_id)
    end)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp mark_task_failed(%ExecutionTask{} = task, reason) do
    Repo.update(
      ExecutionTask.complete_changeset(task, %{
        status: :failed,
        stdout: "",
        stderr: format_reason(reason),
        exit_code: nil,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
  end

  defp format_reason(reason) do
    inspect(reason)
  end
end
