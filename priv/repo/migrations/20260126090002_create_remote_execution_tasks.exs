defmodule Micelio.Repo.Migrations.CreateRemoteExecutionTasks do
  use Ecto.Migration

  def change do
    create table(:remote_execution_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :command, :string, null: false
      add :args, {:array, :string}, null: false, default: []
      add :env, :map, null: false, default: %{}
      add :status, :string, null: false, default: "queued"
      add :stdout, :text
      add :stderr, :text
      add :exit_code, :integer
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:remote_execution_tasks, [:user_id])
    create index(:remote_execution_tasks, [:status])
    create index(:remote_execution_tasks, [:inserted_at])
  end
end
