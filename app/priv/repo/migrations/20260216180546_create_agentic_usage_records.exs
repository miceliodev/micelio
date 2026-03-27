defmodule Micelio.Repo.Migrations.CreateAgenticUsageRecords do
  use Ecto.Migration

  def change do
    create table(:agentic_usage_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :active_workspaces, :integer, default: 0
      add :daily_minutes_used, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agentic_usage_records, [:user_id, :date])
    create index(:agentic_usage_records, [:user_id])
  end
end
