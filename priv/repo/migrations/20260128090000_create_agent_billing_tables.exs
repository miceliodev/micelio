defmodule Micelio.Repo.Migrations.CreateAgentBillingTables do
  use Ecto.Migration

  def change do
    create table(:agent_quotas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :cpu_core_seconds_limit, :bigint, null: false
      add :memory_mb_seconds_limit, :bigint, null: false
      add :disk_gb_seconds_limit, :bigint, null: false
      add :billable_units_limit, :bigint, null: false
      add :cpu_core_seconds_used, :bigint, null: false, default: 0
      add :memory_mb_seconds_used, :bigint, null: false, default: 0
      add :disk_gb_seconds_used, :bigint, null: false, default: 0
      add :billable_units_used, :bigint, null: false, default: 0
      add :cost_cents_used, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_quotas, [:account_id, :period_start])
    create index(:agent_quotas, [:account_id, :period_end])

    create table(:agent_usage_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source, :string, null: false
      add :cpu_core_seconds, :bigint, null: false
      add :memory_mb_seconds, :bigint, null: false
      add :disk_gb_seconds, :bigint, null: false
      add :billable_units, :bigint, null: false
      add :cost_cents, :bigint, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_usage_events, [:account_id])
    create index(:agent_usage_events, [:source])
  end
end
