defmodule Micelio.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :goal, :text, null: false
      add :status, :string, null: false, default: "active"

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :conversation, :jsonb, default: "[]"
      add :decisions, :jsonb, default: "[]"
      add :metadata, :jsonb, default: "{}"

      add :started_at, :utc_datetime
      add :landed_at, :utc_datetime

      timestamps()
    end

    create index(:sessions, [:project_id])
    create index(:sessions, [:user_id])
    create index(:sessions, [:status])
    create unique_index(:sessions, [:session_id])
  end
end
