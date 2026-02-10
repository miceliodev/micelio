defmodule Micelio.RemoteExecutionTest do
  # async: false because tests spawn background tasks that need DB sandbox access
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.RemoteExecution
  alias Micelio.RemoteExecution.ExecutionTask
  alias Micelio.Repo

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("remote-exec@example.com")
    %{user: user, allowed_commands: ["echo"]}
  end

  test "create_task rejects disallowed commands", %{user: user, allowed_commands: allowed} do
    assert {:error, changeset} =
             RemoteExecution.create_task(user, %{command: "rm"}, allowed_commands: allowed)

    assert %{command: ["is not allowed"]} = errors_on(changeset)
  end

  test "execute_task runs allowed commands", %{user: user, allowed_commands: allowed} do
    {:ok, task} =
      RemoteExecution.create_task(user, %{command: "echo", args: ["hello"]},
        allowed_commands: allowed
      )

    assert {:ok, _task} = RemoteExecution.execute_task(task.id)

    task = Repo.get(ExecutionTask, task.id)
    assert task.status == :succeeded
    assert task.exit_code == 0
    assert String.contains?(task.stdout, "hello")
    assert task.completed_at
  end

  test "enqueue_task runs in the background", %{user: user, allowed_commands: allowed} do
    {:ok, task} =
      RemoteExecution.enqueue_task(user, %{command: "echo", args: ["queued"]},
        allowed_commands: allowed
      )

    task = wait_for_completion(task.id)
    assert task.status == :succeeded
  end

  test "enqueue_task marks task as failed if supervisor is unavailable", %{
    user: user,
    allowed_commands: allowed
  } do
    assert {:error, _reason} =
             RemoteExecution.enqueue_task(user, %{command: "echo"},
               allowed_commands: allowed,
               supervisor: :missing_supervisor
             )

    task = Repo.get_by!(ExecutionTask, user_id: user.id, command: "echo")
    assert task.status == :failed
    assert task.stderr =~ "noproc"
    assert task.completed_at
  end

  defp wait_for_completion(task_id) do
    # Increase timeout to 5 seconds to give background tasks more time
    deadline = System.monotonic_time(:millisecond) + 5_000
    poll_until(task_id, deadline)
  end

  defp poll_until(task_id, deadline) do
    task = Repo.get(ExecutionTask, task_id)

    cond do
      is_nil(task) ->
        task

      task.status in [:succeeded, :failed] ->
        task

      System.monotonic_time(:millisecond) > deadline ->
        task

      true ->
        Process.sleep(10)
        poll_until(task_id, deadline)
    end
  end
end
