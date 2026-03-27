defmodule Micelio.RemoteExecution.ExecutionTask do
  use Micelio.Schema

  import Ecto.Changeset

  @statuses [:queued, :running, :succeeded, :failed]

  schema "remote_execution_tasks" do
    field :command, :string
    field :args, {:array, :string}, default: []
    field :env, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :stdout, :string
    field :stderr, :string
    field :exit_code, :integer
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(task, attrs, opts \\ []) do
    task
    |> cast(attrs, [:user_id, :command, :args, :env])
    |> validate_required([:user_id, :command])
    |> validate_allowed_command(opts)
    |> assoc_constraint(:user)
  end

  def running_changeset(task) do
    change(task,
      status: :running,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  def complete_changeset(task, attrs) do
    task
    |> cast(attrs, [:status, :stdout, :stderr, :exit_code, :completed_at])
    |> validate_required([:status, :completed_at])
  end

  defp validate_allowed_command(changeset, opts) do
    allowed =
      case Keyword.get(opts, :allowed_commands) do
        nil ->
          :micelio
          |> Application.get_env(:remote_execution, [])
          |> Keyword.get(:allowed_commands, [])

        commands ->
          commands
      end

    command = get_field(changeset, :command)

    cond do
      is_nil(command) ->
        changeset

      allowed == [] ->
        add_error(changeset, :command, "is not allowed")

      command in allowed ->
        changeset

      true ->
        add_error(changeset, :command, "is not allowed")
    end
  end
end
