defmodule MicelioWeb.Api.RemoteExecutionController do
  use MicelioWeb, :controller

  alias Micelio.RemoteExecution

  def create(conn, params) do
    with {:ok, user} <- fetch_user(conn),
         {:ok, task} <- RemoteExecution.enqueue_task(user, params, remote_execution_opts(conn)) do
      conn
      |> put_status(:created)
      |> json(%{data: task_payload(task)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Execution failed"})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, user} <- fetch_user(conn),
         task when not is_nil(task) <- RemoteExecution.get_task_for_user(user, id) do
      json(conn, %{data: task_payload(task)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})
    end
  end

  defp fetch_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp remote_execution_opts(conn) do
    case conn.assigns[:remote_execution_allowed_commands] do
      nil -> []
      commands -> [allowed_commands: commands]
    end
  end

  defp task_payload(task) do
    %{
      id: task.id,
      status: Atom.to_string(task.status),
      command: task.command,
      args: task.args,
      exit_code: task.exit_code,
      stdout: task.stdout,
      stderr: task.stderr,
      inserted_at: format_datetime(task.inserted_at),
      started_at: format_datetime(task.started_at),
      completed_at: format_datetime(task.completed_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
